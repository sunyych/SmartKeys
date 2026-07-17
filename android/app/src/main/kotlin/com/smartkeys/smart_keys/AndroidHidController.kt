package com.smartkeys.smart_keys

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidHidController(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val manager = activity.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = manager?.adapter
    private val encoder = HidReportEncoder()
    private val handler = Handler(Looper.getMainLooper())
    private val stepQueue = ArrayDeque<HidActionData>()

    private var hidDevice: BluetoothHidDevice? = null
    private var appRegistered = false
    private var currentDevice: BluetoothDevice? = null
    private var pendingConnectAddress: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var status = initialStatus()
    private var lastError: String? = null
    private var stepInFlight = false
    private var stepGeneration = 0

    init {
        channel.setMethodCallHandler(this)
        if (bluetoothEnabled()) ensureProfileProxy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getConnectionStatus" -> result.success(status)
            "getConnectionSnapshot" -> result.success(snapshot())
            "requestBluetoothAccess" -> requestBluetoothAccess(result)
            "makeDiscoverable" -> makeDiscoverable(result)
            "openBluetoothSettings" -> openBluetoothSettings(result)
            "refreshPairedHosts" -> {
                refreshState()
                result.success(snapshot())
            }
            "connect" -> connect(call.argument<String>("address"), result)
            "disconnect" -> disconnect(result)
            "sendPress" -> sendSingle(encoder.press(HidActionData.from(call.arguments)), result)
            "sendRelease" -> sendSingle(encoder.release(HidActionData.from(call.arguments)), result)
            "sendStep" -> sendStep(HidActionData.from(call.arguments), result)
            "releaseAllKeys" -> {
                releaseAllInput()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onForeground() {
        refreshState()
        if (bluetoothEnabled()) ensureProfileProxy()
    }

    fun releaseForBackground() {
        releaseAllInput()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != BLUETOOTH_PERMISSION_REQUEST) return
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            lastError = null
            status = if (bluetoothEnabled()) STATUS_REGISTERING else STATUS_BLUETOOTH_OFF
            emitState()
            if (bluetoothEnabled()) ensureProfileProxy()
            result?.success(snapshot())
        } else {
            status = STATUS_PERMISSION_REQUIRED
            lastError = "Nearby devices permission is required to register as a Bluetooth HID device."
            emitState()
            result?.error("PERMISSION_DENIED", lastError, null)
        }
    }

    @SuppressLint("MissingPermission")
    fun close() {
        releaseAllInput()
        if (appRegistered) runCatching { hidDevice?.unregisterApp() }
        hidDevice?.let { proxy -> runCatching { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, proxy) } }
        appRegistered = false
        hidDevice = null
        currentDevice = null
        channel.setMethodCallHandler(null)
    }

    private fun requestBluetoothAccess(result: MethodChannel.Result) {
        if (!isPlatformSupported()) {
            result.error("UNSUPPORTED", "Bluetooth HID Device requires Android 9 or newer.", null)
            return
        }
        if (adapter == null) {
            status = STATUS_UNAVAILABLE
            result.error("NO_BLUETOOTH", "This device does not provide Bluetooth.", null)
            return
        }
        if (!hasBluetoothPermissions()) {
            if (pendingPermissionResult != null) {
                result.error("REQUEST_ACTIVE", "A Bluetooth permission request is already active.", null)
                return
            }
            pendingPermissionResult = result
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                activity.requestPermissions(
                    arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE),
                    BLUETOOTH_PERMISSION_REQUEST,
                )
            }
            return
        }
        refreshState()
        if (bluetoothEnabled()) ensureProfileProxy()
        result.success(snapshot())
    }

    private fun makeDiscoverable(result: MethodChannel.Result) {
        if (!requireReadyPermission(result)) return
        if (!bluetoothEnabled()) {
            status = STATUS_BLUETOOTH_OFF
            emitState()
            result.error("BLUETOOTH_OFF", "Turn on Bluetooth before making this phone discoverable.", null)
            return
        }
        ensureProfileProxy()
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
            putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, DISCOVERABLE_SECONDS)
        }
        activity.startActivity(intent)
        result.success(null)
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
        activity.startActivity(intent)
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String?, result: MethodChannel.Result) {
        if (!requireReadyPermission(result)) return
        if (!bluetoothEnabled()) {
            status = STATUS_BLUETOOTH_OFF
            emitState()
            result.error("BLUETOOTH_OFF", "Bluetooth is turned off.", null)
            return
        }
        val host = pairedDevices().firstOrNull { it.address == address }
        if (host == null) {
            result.error("HOST_NOT_PAIRED", "Select a host already paired in Android Bluetooth settings.", null)
            return
        }
        pendingConnectAddress = host.address
        lastError = null
        if (!appRegistered || hidDevice == null) {
            status = STATUS_REGISTERING
            ensureProfileProxy()
            emitState()
            result.success(null)
            return
        }
        status = STATUS_CONNECTING
        emitState()
        if (hidDevice?.connect(host) != true) {
            status = STATUS_DISCONNECTED
            lastError = "Android rejected the HID connection request. Confirm the computer is paired."
            emitState()
            result.error("CONNECT_REJECTED", lastError, null)
            return
        }
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun disconnect(result: MethodChannel.Result) {
        if (!requireReadyPermission(result)) return
        val host = currentDevice
        releaseAllInput()
        if (host == null) {
            status = STATUS_DISCONNECTED
            emitState()
            result.success(null)
            return
        }
        if (hidDevice?.disconnect(host) != true) {
            result.error("DISCONNECT_REJECTED", "Android rejected the disconnect request.", null)
            return
        }
        result.success(null)
    }

    private fun sendSingle(report: HidReport?, result: MethodChannel.Result) {
        if (report == null) {
            result.error("INVALID_ACTION", "The configured HID action is not supported.", null)
            return
        }
        if (!sendReport(report)) {
            result.error("NOT_CONNECTED", "Connect a paired computer before sending input.", null)
            return
        }
        result.success(null)
    }

    private fun sendStep(action: HidActionData, result: MethodChannel.Result) {
        if (action.type !in setOf("keyboard", "consumerControl", "mouseWheel", "mouseMove")) {
            result.error("INVALID_ACTION", "The configured navigation action is not supported.", null)
            return
        }
        if (status != STATUS_CONNECTED || currentDevice == null) {
            result.error("NOT_CONNECTED", "Connect a paired computer before sending input.", null)
            return
        }
        stepQueue.addLast(action)
        processNextStep()
        result.success(null)
    }

    private fun processNextStep() {
        if (stepInFlight || stepQueue.isEmpty()) return
        val action = stepQueue.removeFirst()
        val pressed = encoder.press(action) ?: run {
            processNextStep()
            return
        }
        stepInFlight = true
        val generation = stepGeneration
        sendReport(pressed)
        handler.postDelayed({
            if (generation != stepGeneration) return@postDelayed
            encoder.release(action)?.let(::sendReport)
            handler.postDelayed({
                if (generation != stepGeneration) return@postDelayed
                stepInFlight = false
                processNextStep()
            }, REPORT_GAP_MS)
        }, REPORT_RELEASE_DELAY_MS)
    }

    private fun releaseAllInput() {
        stepQueue.clear()
        stepGeneration++
        stepInFlight = false
        sendReports(encoder.releaseAll())
    }

    @SuppressLint("MissingPermission")
    private fun sendReport(report: HidReport): Boolean {
        if (!hasBluetoothPermissions() || status != STATUS_CONNECTED) return false
        val host = currentDevice ?: return false
        return runCatching { hidDevice?.sendReport(host, report.id, report.data) == true }.getOrDefault(false)
    }

    private fun sendReports(reports: List<HidReport>) {
        reports.forEach(::sendReport)
    }

    @SuppressLint("MissingPermission")
    private fun ensureProfileProxy() {
        val bluetoothAdapter = adapter ?: return
        if (!isPlatformSupported() || !bluetoothEnabled()) return
        if (hidDevice != null) {
            if (!appRegistered) registerApp()
            return
        }
        status = STATUS_REGISTERING
        emitState()
        val accepted = bluetoothAdapter.getProfileProxy(activity, profileListener, BluetoothProfile.HID_DEVICE)
        if (!accepted) {
            status = STATUS_UNAVAILABLE
            lastError = "Android did not provide the Bluetooth HID Device profile."
            emitState()
        }
    }

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            hidDevice = proxy as? BluetoothHidDevice
            registerApp()
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            appRegistered = false
            hidDevice = null
            currentDevice = null
            status = if (bluetoothEnabled()) STATUS_DISCONNECTED else STATUS_BLUETOOTH_OFF
            emitState()
        }
    }

    @SuppressLint("MissingPermission")
    private fun registerApp() {
        val proxy = hidDevice ?: return
        if (appRegistered) return
        val sdp = BluetoothHidDeviceAppSdpSettings(
            "SmartKeys",
            "SmartKeys keyboard, consumer control, and mouse navigation",
            "SmartKeys",
            BluetoothHidDevice.SUBCLASS1_COMBO,
            HidReportEncoder.REPORT_DESCRIPTOR,
        )
        status = STATUS_REGISTERING
        emitState()
        if (!proxy.registerApp(sdp, null, null, activity.mainExecutor, hidCallback)) {
            status = STATUS_UNAVAILABLE
            lastError = "Another app may already be registered as the Android HID device."
            emitState()
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            appRegistered = registered
            if (!registered) {
                currentDevice = null
                status = if (bluetoothEnabled()) STATUS_DISCONNECTED else STATUS_BLUETOOTH_OFF
                emitState()
                return
            }
            lastError = null
            if (pluggedDevice != null) currentDevice = pluggedDevice
            if (currentDevice != null) {
                status = STATUS_CONNECTED
            } else {
                status = STATUS_DISCONNECTED
            }
            emitState()
            val pending = pendingConnectAddress
            if (pending != null) {
                pendingConnectAddress = null
                connect(pending, NoopResult)
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    currentDevice = device
                    status = STATUS_CONNECTED
                    lastError = null
                }
                BluetoothProfile.STATE_CONNECTING -> status = STATUS_CONNECTING
                BluetoothProfile.STATE_DISCONNECTING -> status = STATUS_CONNECTING
                else -> {
                    if (currentDevice?.address == device.address) currentDevice = null
                    status = STATUS_DISCONNECTED
                }
            }
            emitState()
        }

        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            val report = encoder.reportForId(id.toInt())
            if (report == null) {
                hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_INVALID_RPT_ID)
            } else {
                hidDevice?.replyReport(device, type, id, report.data)
            }
        }

        override fun onVirtualCableUnplug(device: BluetoothDevice) {
            if (currentDevice?.address == device.address) currentDevice = null
            status = STATUS_DISCONNECTED
            emitState()
        }
    }

    private fun refreshState() {
        status = when {
            !isPlatformSupported() || adapter == null -> STATUS_UNAVAILABLE
            !hasBluetoothPermissions() -> STATUS_PERMISSION_REQUIRED
            !bluetoothEnabled() -> STATUS_BLUETOOTH_OFF
            currentDevice != null -> STATUS_CONNECTED
            hidDevice == null || !appRegistered -> STATUS_REGISTERING
            else -> STATUS_DISCONNECTED
        }
        emitState()
    }

    @SuppressLint("MissingPermission")
    private fun pairedDevices(): List<BluetoothDevice> {
        if (!hasBluetoothPermissions()) return emptyList()
        return runCatching { adapter?.bondedDevices?.toList().orEmpty() }.getOrDefault(emptyList())
    }

    @SuppressLint("MissingPermission")
    private fun snapshot(): Map<String, Any?> = mapOf(
        "status" to status,
        "registered" to appRegistered,
        "bluetoothEnabled" to bluetoothEnabled(),
        "permissionsGranted" to hasBluetoothPermissions(),
        "activeHost" to currentDevice?.let(::hostMap),
        "pairedHosts" to pairedDevices().map(::hostMap),
        "error" to lastError,
    )

    @SuppressLint("MissingPermission")
    private fun hostMap(device: BluetoothDevice): Map<String, String> = mapOf(
        "id" to device.address,
        "name" to (device.alias ?: device.name ?: "Paired device"),
        "address" to device.address,
    )

    private fun emitState() {
        handler.post {
            channel.invokeMethod("connectionSnapshotChanged", snapshot())
        }
    }

    private fun requireReadyPermission(result: MethodChannel.Result): Boolean {
        if (!isPlatformSupported()) {
            result.error("UNSUPPORTED", "Bluetooth HID Device requires Android 9 or newer.", null)
            return false
        }
        if (!hasBluetoothPermissions()) {
            status = STATUS_PERMISSION_REQUIRED
            emitState()
            result.error("PERMISSION_REQUIRED", "Grant Nearby devices access first.", null)
            return false
        }
        return true
    }

    private fun hasBluetoothPermissions(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
        (activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED)

    @SuppressLint("MissingPermission")
    private fun bluetoothEnabled(): Boolean {
        val bluetoothAdapter = adapter ?: return false
        if (!hasBluetoothPermissions()) return false
        return runCatching { bluetoothAdapter.isEnabled }.getOrDefault(false)
    }

    private fun isPlatformSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    private fun initialStatus(): String = when {
        !isPlatformSupported() || adapter == null -> STATUS_UNAVAILABLE
        !hasBluetoothPermissions() -> STATUS_PERMISSION_REQUIRED
        !bluetoothEnabled() -> STATUS_BLUETOOTH_OFF
        else -> STATUS_REGISTERING
    }

    private object NoopResult : MethodChannel.Result {
        override fun success(result: Any?) = Unit
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
        override fun notImplemented() = Unit
    }

    companion object {
        private const val CHANNEL_NAME = "smart_keys/hid"
        private const val BLUETOOTH_PERMISSION_REQUEST = 7001
        private const val DISCOVERABLE_SECONDS = 300
        private const val REPORT_RELEASE_DELAY_MS = 12L
        private const val REPORT_GAP_MS = 4L

        private const val STATUS_UNAVAILABLE = "unavailable"
        private const val STATUS_PERMISSION_REQUIRED = "permissionRequired"
        private const val STATUS_BLUETOOTH_OFF = "bluetoothOff"
        private const val STATUS_REGISTERING = "registering"
        private const val STATUS_DISCONNECTED = "disconnected"
        private const val STATUS_CONNECTING = "connecting"
        private const val STATUS_CONNECTED = "connected"
    }
}

package com.lumiaiq.smartkey

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
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
    private data class TextBatch(
        val sessionToken: String,
        val expectedAddress: String,
        val strokes: List<HidTextKeyStroke>,
        val result: MethodChannel.Result,
        var index: Int = 0,
    )

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val manager = activity.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = manager?.adapter
    private val preferences = activity.getSharedPreferences(HID_PREFERENCES, Context.MODE_PRIVATE)
    private val encoder = HidReportEncoder()
    private val textBatchGate = HidTextBatchGate()
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
    private var textBatch: TextBatch? = null
    private var textBatchGeneration = 0

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
            "sendPress" -> {
                if (textBatchGate.isActive()) releaseAllInput()
                sendSingle(encoder.press(HidActionData.from(call.arguments)), result)
            }
            "sendRelease" -> {
                if (textBatchGate.isActive()) releaseAllInput()
                sendSingle(encoder.release(HidActionData.from(call.arguments)), result)
            }
            "sendStep" -> sendStep(HidActionData.from(call.arguments), result)
            "sendTextBatch" -> sendTextBatch(call.arguments, result)
            "cancelTextBatch" -> cancelTextBatch(call.argument<String>("sessionToken"), result)
            "releaseAllKeys" -> {
                releaseAllInput()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onForeground() {
        refreshState()
        if (bluetoothEnabled()) {
            ensureProfileProxy()
            reconnectRememberedHost()
        }
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
        pendingConnectAddress = null
        result.success(null)
    }

    @SuppressLint("MissingPermission")
    private fun disconnect(result: MethodChannel.Result) {
        if (!requireReadyPermission(result)) return
        val host = currentDevice
        forgetLastHost()
        pendingConnectAddress = null
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
            handleSendFailure()
            result.error("NOT_CONNECTED", "Connect a paired computer before sending input.", null)
            return
        }
        result.success(null)
    }

    private fun sendStep(action: HidActionData, result: MethodChannel.Result) {
        if (textBatchGate.isActive()) releaseAllInput()
        if (action.type !in setOf("keyboard", "consumerControl", "mouseWheel", "mouseMove", "mouseButton")) {
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

    private fun sendTextBatch(arguments: Any?, result: MethodChannel.Result) {
        val request = HidTextBatchValidator.parse(arguments)
        if (request == null) {
            result.error("INVALID_BATCH", "The Bluetooth text batch is malformed or too large.", null)
            return
        }
        if (textBatchGate.isActive()) {
            result.error("TEXT_BATCH_BUSY", "Another Bluetooth text batch is already active.", null)
            return
        }
        if (!requireReadyPermission(result)) return
        if (status != STATUS_CONNECTED || currentDevice?.address != request.expectedAddress) {
            result.error("HOST_CHANGED", "The connected Bluetooth host changed. Dictation stopped.", snapshot())
            return
        }
        if (encoder.hasHeldInput || stepInFlight || stepQueue.isNotEmpty()) {
            result.error("INPUT_BUSY", "Release other Bluetooth input before dictation.", null)
            return
        }
        val batch = TextBatch(
            sessionToken = request.sessionToken,
            expectedAddress = request.expectedAddress,
            strokes = request.strokes,
            result = result,
        )
        if (!textBatchGate.begin(batch.sessionToken)) {
            result.error("TEXT_BATCH_BUSY", "Another Bluetooth text batch is already active.", null)
            return
        }
        textBatch = batch
        val generation = ++textBatchGeneration
        handler.post { processTextBatch(batch, generation) }
    }

    private fun processTextBatch(batch: TextBatch, generation: Int) {
        if (textBatch !== batch || generation != textBatchGeneration ||
            !textBatchGate.isActive(batch.sessionToken)
        ) return
        if (!batchTargetIsCurrent(batch)) {
            failTextBatch(batch, "HOST_CHANGED", "The Bluetooth host changed. Dictation stopped.")
            return
        }
        if (batch.index >= batch.strokes.size) {
            finishTextBatch(batch)
            return
        }
        val stroke = batch.strokes[batch.index]
        val pressed = if (stroke.unicodeHex) {
            encoder.pressUnicodeHexStroke(stroke)
        } else {
            encoder.pressTextStroke(HidTextStroke(stroke.usage, stroke.shift))
        }
        if (pressed == null || !sendReport(pressed)) {
            failTextBatch(batch, "REPORT_FAILED", "Bluetooth rejected a keyboard report. Dictation stopped.")
            handleSendFailure()
            return
        }
        handler.postDelayed({
            if (textBatch !== batch || generation != textBatchGeneration ||
                !textBatchGate.isActive(batch.sessionToken)
            ) return@postDelayed
            if (!batchTargetIsCurrent(batch)) {
                failTextBatch(batch, "HOST_CHANGED", "The Bluetooth host changed. Dictation stopped.")
                return@postDelayed
            }
            val released = if (stroke.unicodeHex) {
                encoder.releaseUnicodeHexStroke(stroke)
            } else {
                encoder.releaseTextStroke(HidTextStroke(stroke.usage, stroke.shift))
            }
            if (released == null || !sendReport(released)) {
                failTextBatch(batch, "REPORT_FAILED", "Bluetooth rejected a keyboard release report. Dictation stopped.")
                handleSendFailure()
                return@postDelayed
            }
            batch.index++
            handler.postDelayed({ processTextBatch(batch, generation) }, TEXT_REPORT_GAP_MS)
        }, TEXT_REPORT_RELEASE_DELAY_MS)
    }

    private fun batchTargetIsCurrent(batch: TextBatch): Boolean =
        status == STATUS_CONNECTED && currentDevice?.address == batch.expectedAddress

    private fun finishTextBatch(batch: TextBatch) {
        if (textBatch !== batch) return
        textBatch = null
        textBatchGate.finish(batch.sessionToken)
        textBatchGeneration++
        if (!sendReportsChecked(encoder.releaseAll())) {
            handleSendFailure()
            batch.result.error("REPORT_FAILED", "Bluetooth could not release all keyboard keys.", null)
            return
        }
        batch.result.success(snapshot())
    }

    private fun failTextBatch(batch: TextBatch, code: String, message: String) {
        if (textBatch !== batch) return
        // Attempt neutral reports while the original host is still pinned.
        sendReportsChecked(encoder.releaseAll())
        textBatch = null
        textBatchGate.finish(batch.sessionToken)
        textBatchGeneration++
        batch.result.error(code, message, null)
    }

    private fun cancelTextBatch(sessionToken: String?, result: MethodChannel.Result) {
        val active = textBatch
        if (active == null || active.sessionToken != sessionToken) {
            result.success(false)
            return
        }
        textBatch = null
        textBatchGate.cancel(sessionToken)
        textBatchGeneration++
        val hadHeldInput = encoder.hasHeldInput
        val neutralReports = encoder.releaseAll()
        val released = !hadHeldInput || sendReportsChecked(neutralReports)
        active.result.error("CANCELLED", "Bluetooth text output was cancelled.", null)
        if (released) {
            result.success(true)
        } else {
            handleSendFailure()
            result.error("REPORT_FAILED", "Bluetooth could not release all keyboard keys during cancellation.", null)
        }
    }

    private fun sendReportsChecked(reports: List<HidReport>): Boolean {
        var success = true
        reports.forEach { report -> if (!sendReport(report)) success = false }
        return success
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
        if (!sendReport(pressed)) {
            stepInFlight = false
            stepQueue.clear()
            handleSendFailure()
            return
        }
        handler.postDelayed({
            if (generation != stepGeneration) return@postDelayed
            encoder.release(action)?.let { released ->
                if (!sendReport(released)) handleSendFailure()
            }
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
        textBatch?.let { active ->
            textBatch = null
            textBatchGate.cancelForNavigation()
            textBatchGeneration++
            active.result.error("CANCELLED", "Bluetooth input was cancelled.", null)
        }
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

    private fun handleSendFailure() {
        currentDevice = null
        status = STATUS_DISCONNECTED
        lastError = "The computer is not accepting Bluetooth HID reports. Reconnect it and try again."
        emitState()
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
            "LumiaKey",
            "LumiaKey keyboard, consumer control, and mouse navigation",
            "LumiaKey",
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
        @SuppressLint("MissingPermission")
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            if (textBatch != null && pluggedDevice?.address != textBatch?.expectedAddress) {
                releaseAllInput()
            }
            appRegistered = registered
            if (!registered) {
                releaseAllInput()
                currentDevice = null
                status = if (bluetoothEnabled()) STATUS_DISCONNECTED else STATUS_BLUETOOTH_OFF
                emitState()
                return
            }
            lastError = null
            currentDevice = pluggedDevice?.takeIf { device ->
                hidDevice?.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED
            }
            if (currentDevice != null) {
                status = STATUS_CONNECTED
            } else {
                status = STATUS_DISCONNECTED
            }
            emitState()
            val pending = pendingConnectAddress
            val reconnectAddress = pending ?: rememberedHostAddress() ?: pluggedDevice?.address
            if (reconnectAddress != null && currentDevice == null) {
                pendingConnectAddress = null
                connect(reconnectAddress, NoopResult)
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            if (textBatch != null &&
                (device.address != textBatch?.expectedAddress || state != BluetoothProfile.STATE_CONNECTED)
            ) {
                releaseAllInput()
            }
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    if (textBatch != null && currentDevice?.address != device.address) {
                        releaseAllInput()
                    }
                    currentDevice = device
                    rememberHost(device.address)
                    status = STATUS_CONNECTED
                    lastError = null
                }
                BluetoothProfile.STATE_CONNECTING -> status = STATUS_CONNECTING
                BluetoothProfile.STATE_DISCONNECTING -> status = STATUS_CONNECTING
                else -> {
                    if (currentDevice?.address == device.address) {
                        releaseAllInput()
                        currentDevice = null
                    }
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
            if (currentDevice?.address == device.address) {
                releaseAllInput()
                currentDevice = null
            }
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

    private fun reconnectRememberedHost() {
        if (!appRegistered || currentDevice != null || pendingConnectAddress != null) return
        val address = rememberedHostAddress() ?: return
        connect(address, NoopResult)
    }

    private fun rememberHost(address: String) {
        preferences.edit().putString(LAST_HOST_ADDRESS, address).apply()
    }

    private fun rememberedHostAddress(): String? = preferences.getString(LAST_HOST_ADDRESS, null)

    private fun forgetLastHost() {
        preferences.edit().remove(LAST_HOST_ADDRESS).apply()
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
        private const val HID_PREFERENCES = "smart_keys_hid"
        private const val LAST_HOST_ADDRESS = "last_host_address"
        private const val BLUETOOTH_PERMISSION_REQUEST = 7001
        private const val DISCOVERABLE_SECONDS = 300
        private const val REPORT_RELEASE_DELAY_MS = 12L
        private const val REPORT_GAP_MS = 4L
        private const val TEXT_REPORT_RELEASE_DELAY_MS = 8L
        private const val TEXT_REPORT_GAP_MS = 2L

        private const val STATUS_UNAVAILABLE = "unavailable"
        private const val STATUS_PERMISSION_REQUIRED = "permissionRequired"
        private const val STATUS_BLUETOOTH_OFF = "bluetoothOff"
        private const val STATUS_REGISTERING = "registering"
        private const val STATUS_DISCONNECTED = "disconnected"
        private const val STATUS_CONNECTING = "connecting"
        private const val STATUS_CONNECTED = "connected"
    }
}

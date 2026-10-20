package com.lumiaiq.smartkey

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hidController: AndroidHidController? = null
    private var powerController: AndroidPowerController? = null
    private var desktopInstallerController: DesktopInstallerController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hidController = AndroidHidController(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        powerController = AndroidPowerController(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        desktopInstallerController = DesktopInstallerController(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onStart() {
        super.onStart()
        hidController?.onForeground()
        powerController?.onForeground()
    }

    override fun onStop() {
        hidController?.releaseForBackground()
        super.onStop()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        hidController?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        desktopInstallerController?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        powerController?.close()
        desktopInstallerController?.close()
        if (!isChangingConfigurations) {
            hidController?.close()
        }
        hidController = null
        powerController = null
        desktopInstallerController = null
        super.onDestroy()
    }
}

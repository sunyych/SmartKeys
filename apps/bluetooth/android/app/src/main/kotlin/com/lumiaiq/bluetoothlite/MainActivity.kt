package com.lumiaiq.bluetoothlite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hidController: AndroidHidController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hidController = AndroidHidController(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onStart() { super.onStart(); hidController?.onForeground() }
    override fun onResume() { super.onResume(); hidController?.resumeInput() }
    override fun onPause() { hidController?.releaseForBackground(); super.onPause() }
    override fun onStop() { hidController?.releaseForBackground(); super.onStop() }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        hidController?.onRequestPermissionsResult(requestCode, grantResults)
    }
    override fun onDestroy() {
        if (!isChangingConfigurations) hidController?.close()
        hidController = null
        super.onDestroy()
    }
}

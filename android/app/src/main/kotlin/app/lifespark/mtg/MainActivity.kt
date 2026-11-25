package app.lifespark.mtg

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var keyboardHolds = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.lifespark.mtg/keyboard",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "holdLayout" -> {
                    keyboardHolds += 1
                    window.setSoftInputMode(
                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING,
                    )
                    result.success(null)
                }
                "releaseLayout" -> {
                    keyboardHolds = (keyboardHolds - 1).coerceAtLeast(0)
                    if (keyboardHolds == 0) {
                        window.setSoftInputMode(
                            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

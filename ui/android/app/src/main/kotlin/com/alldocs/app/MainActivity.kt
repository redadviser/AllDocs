package com.alldocs.app

import android.net.Uri
import android.view.WindowManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Hide previews" setting: FLAG_SECURE blanks the app in the recent
        // apps switcher and blocks screenshots/screen recording.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alldocs/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // On-device OCR for scans and search (TextRecognition on the Dart side).
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alldocs/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                    ?: return@setMethodCallHandler result.error("bad_args", "path missing", null)
                val image = try {
                    InputImage.fromFilePath(this, Uri.fromFile(File(path)))
                } catch (error: Exception) {
                    return@setMethodCallHandler result.error("ocr_failed", error.message, null)
                }
                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                            val box = line.boundingBox ?: return@mapNotNull null
                            mapOf(
                                "text" to line.text,
                                "left" to box.left,
                                "top" to box.top,
                                "width" to box.width(),
                                "height" to box.height(),
                            )
                        }
                        result.success(mapOf("text" to text.text, "lines" to lines))
                    }
                    .addOnFailureListener { error -> result.error("ocr_failed", error.message, null) }
            }
    }
}

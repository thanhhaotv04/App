package com.example.vietnam_map_01

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "vietnam_map_checkin/update"
    private val photoChannel = "vietnam_map_checkin/photos"
    private val savePhotoRequestCode = 9373
    private var pendingPhotoSave: Pair<ByteArray, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_path", "APK path is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(path)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("install_failed", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, photoChannel).setMethodCallHandler { call, result ->
            if (call.method != "saveImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            if (bytes == null || bytes.isEmpty()) {
                result.error("empty_photo", "Photo has no data", null)
                return@setMethodCallHandler
            }
            if (pendingPhotoSave != null) {
                result.error("save_busy", "Another photo is being saved", null)
                return@setMethodCallHandler
            }
            pendingPhotoSave = bytes to result
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "image/jpeg"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "memory.jpg")
                }
                startActivityForResult(intent, savePhotoRequestCode)
            } catch (error: Exception) {
                pendingPhotoSave = null
                result.error("save_failed", error.message, null)
            }
        }
    }

    @Deprecated("Handled by the Android document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != savePhotoRequestCode) return
        val pending = pendingPhotoSave ?: return
        pendingPhotoSave = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.second.success(false)
            return
        }
        try {
            val stream = contentResolver.openOutputStream(data.data!!)
                ?: throw IllegalStateException("Could not open the selected location")
            stream.use { it.write(pending.first) }
            pending.second.success(true)
        } catch (error: Exception) {
            pending.second.error("save_failed", error.message, null)
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("APK file does not exist: $path")
        }
        val uri: Uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}

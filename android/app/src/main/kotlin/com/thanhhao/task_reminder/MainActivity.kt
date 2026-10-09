package com.thanhhao.task_reminder

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "task_reminder/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("missing_path", "APK path is required.", null)
                    return@setMethodCallHandler
                }
                try {
                    installApk(path)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun installApk(path: String) {
        val apk = File(path).canonicalFile
        val updateDirectory = File(cacheDir, "updates").canonicalFile
        require(apk.isFile && apk.path.startsWith(updateDirectory.path + File.separator)) {
            "Only a verified APK from the app update cache can be installed."
        }
        val archive = packageManager.getPackageArchiveInfo(apk.path, 0)
            ?: throw IllegalArgumentException("The downloaded file is not a valid APK.")
        require(archive.packageName == applicationContext.packageName) {
            "The downloaded APK belongs to a different application."
        }
        val installed = packageManager.getPackageInfo(applicationContext.packageName, 0)
        val nextVersion = if (android.os.Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val currentVersion = if (android.os.Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        require(nextVersion > currentVersion) { "This APK is not newer than the installed app." }
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            apk,
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}

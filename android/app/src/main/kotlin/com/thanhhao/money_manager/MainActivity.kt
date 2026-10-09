package com.thanhhao.money_manager

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "money_manager/update")
            .setMethodCallHandler { call, result ->
                if (call.method == "getCacheDirectory") {
                    result.success(cacheDir.absolutePath)
                    return@setMethodCallHandler
                }
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path")
                    require(!path.isNullOrBlank()) { "APK path is required." }
                    installApk(path)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun fingerprints(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun installApk(path: String) {
        val apk = File(path).canonicalFile
        val allowed = File(cacheDir, "money-manager-updates").canonicalFile
        require(apk.parentFile == allowed && apk.extension == "apk" && apk.isFile) {
            "Download a verified update before installing."
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else PackageManager.GET_SIGNATURES
        val candidate = packageManager.getPackageArchiveInfo(apk.path, flags)
            ?: throw IllegalArgumentException("The downloaded APK is invalid.")
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(candidate.packageName == packageName) { "This update belongs to another app." }
        val candidateCode = if (Build.VERSION.SDK_INT >= 28) candidate.longVersionCode else candidate.versionCode.toLong()
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        require(candidateCode > installedCode) { "This update is older than the installed app." }
        val signers = fingerprints(candidate)
        require(signers.isNotEmpty() && signers == fingerprints(installed)) {
            "The update signing key does not match this app. Contact the server owner."
        }
        require((candidate.applicationInfo?.flags ?: 0) and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            "Debug builds cannot be installed as updates."
        }
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            throw IllegalStateException("Allow updates from Money Manager, then check for updates again.")
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}

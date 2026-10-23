package com.duanju.duanju_app

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class UpdateFileProvider : FileProvider()

class AppUpdateBridge(private val activity: Activity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "duanju/update")
    private val certificate = "2B1F9DEC180E972D6C3736C5EFD52EE7952EDE4155EEECDBBC23EA331FFA076E"

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "version" to info.versionName,
                            "build" to (code - 2000).toString(),
                            "canInstall" to (activity.packageName == "com.duanju.duanju_app")
                        ))
                    }
                    "openLink" -> {
                        val uri = Uri.parse(requireNotNull(call.argument<String>("url")))
                        require(uri.scheme == "https" && uri.host == "github.com") { "链接地址无效" }
                        activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(null)
                    }
                    "install" -> result.success(install(requireNotNull(call.argument<String>("path"))))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("update_failed", error.message ?: "无法完成更新操作", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun install(path: String): String {
        require(activity.packageName == "com.duanju.duanju_app") { "开发包请从 Release 安装正式版" }
        val file = File(path).canonicalFile
        val directory = File(activity.cacheDir, "app-updates").canonicalFile
        require(file.parentFile == directory && file.isFile && file.extension == "apk") { "安装包路径无效" }
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else PackageManager.GET_SIGNATURES
        val manager = activity.packageManager
        val archive = requireNotNull(manager.getPackageArchiveInfo(file.path, flags)) { "无法读取 APK" }
        require(archive.packageName == activity.packageName) { "安装包应用标识不匹配" }
        val installed = manager.getPackageInfo(activity.packageName, flags)
        val archiveCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        require(archiveCode > installedCode) { "更新包构建号必须高于当前版本" }
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            archive.signingInfo?.apkContentsSigners
        } else archive.signatures
        val installedSignatures = if (Build.VERSION.SDK_INT >= 28) {
            installed.signingInfo?.apkContentsSigners
        } else installed.signatures
        fun digests(items: Array<android.content.pm.Signature>?): Set<String> =
            items.orEmpty().map { signature ->
                MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                    .joinToString("") { "%02X".format(it.toInt() and 255) }
            }.toSet()
        require(digests(signatures) == setOf(certificate) &&
            digests(installedSignatures) == setOf(certificate)) { "安装包或当前应用的签名与正式发布证书不一致" }
        if (!manager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
            return "permissionRequired"
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri("update", uri)
        }
        activity.startActivity(intent)
        return "installerOpened"
    }
}

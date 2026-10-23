package com.duanju.duanju_app

import io.flutter.embedding.android.FlutterActivity
import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.net.ConnectivityManager
import android.net.Uri
import android.util.Rational
import android.util.Log
import android.view.WindowManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deviceChannel: MethodChannel? = null
    private var playbackChannel: MethodChannel? = null
    private var playbackOwner: String? = null
    private var playbackSnapshot: String? = null
    private var restoredPlayback: String? = null
    private var activityResumed = false
    private val continuityPreferences by lazy {
        getSharedPreferences("playback_continuity", Context.MODE_PRIVATE)
    }
    private val flipDevice by lazy {
        runCatching {
            Class.forName("miui.util.MiuiMultiDisplayTypeInfo")
                .getMethod("isFlipDevice").invoke(null) == true
        }.getOrDefault(false) ||
            (Build.MANUFACTURER.equals("Xiaomi", ignoreCase = true) &&
                Build.MODEL.replace(" ", "").startsWith("MIXFLIP", ignoreCase = true))
    }

    private fun coverWindow(): Boolean {
        val configuration = resources.configuration
        return flipDevice && !isInPictureInPictureMode &&
            configuration.screenWidthDp in 1..599 && configuration.screenHeightDp in 1..599
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (coverWindow()) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        notifyWindowChanged("configuration")
    }

    override fun setRequestedOrientation(requestedOrientation: Int) {
        super.setRequestedOrientation(
            if (coverWindow()) ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            else requestedOrientation
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState?.getBoolean("duanju.restorePlayback") == true || flipDevice) {
            restoredPlayback = continuityPreferences.getString("snapshot", null)
            playbackSnapshot = restoredPlayback
        }
        super.onCreate(savedInstanceState)
        if (restoredPlayback != null) {
            Log.i("PlaybackContinuity", "restore available: savedState=${savedInstanceState != null}")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onResume() {
        activityResumed = true
        super.onResume()
        retainTaskInRecents()
        notifyWindowChanged("resume")
    }

    override fun onPause() {
        activityResumed = false
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        retainTaskInRecents()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && activityResumed) notifyWindowChanged("focus")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        retainTaskInRecents()
        notifyWindowChanged("launch")
    }

    private fun notifyWindowChanged(reason: String) {
        if (flipDevice) {
            val configuration = resources.configuration
            Log.i("PlaybackContinuity",
                "$reason: task=$taskId display=${window.decorView.display?.displayId} " +
                    "window=${configuration.screenWidthDp}x${configuration.screenHeightDp} " +
                    "cover=${coverWindow()} pip=$isInPictureInPictureMode resumed=$activityResumed")
        }
        playbackChannel?.invokeMethod("windowChanged", null)
    }

    private fun clearPlaybackSnapshot() {
        playbackOwner = null
        playbackSnapshot = null
        restoredPlayback = null
        continuityPreferences.edit().remove("snapshot").remove("owner").apply()
    }

    @Suppress("DEPRECATION")
    private fun retainTaskInRecents() {
        runCatching {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            manager?.appTasks?.firstOrNull {
                val info = it.taskInfo
                val id = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.taskId else info.id
                id == taskId
            }?.let { task ->
                if ((task.taskInfo.baseIntent.flags and Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS) != 0) {
                    task.setExcludeFromRecents(false)
                }
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("duanju.restorePlayback", playbackSnapshot != null)
        super.onSaveInstanceState(outState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AppUpdateBridge(this, flutterEngine)
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/playback")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "checkpoint" -> {
                            val owner = call.argument<String>("owner")
                            val snapshot = call.argument<String>("snapshot")
                            if (owner == null || snapshot == null || snapshot.length > 65536) {
                                result.error("invalid_snapshot", "播放恢复信息无效", null)
                            } else {
                                playbackOwner = owner
                                playbackSnapshot = snapshot
                                continuityPreferences.edit()
                                    .putString("snapshot", snapshot)
                                    .putString("owner", owner).apply()
                                result.success(null)
                            }
                        }
                        "clear" -> {
                            val owner = call.argument<String>("owner")
                            val preserve = call.argument<Boolean>("preserveForRestart") == true
                            if (owner != null && owner == playbackOwner &&
                                owner == continuityPreferences.getString("owner", null) &&
                                !isChangingConfigurations &&
                                !(preserve && !activityResumed)) {
                                clearPlaybackSnapshot()
                            }
                            result.success(null)
                        }
                        "discardRestore" -> {
                            if (playbackOwner == null &&
                                continuityPreferences.getString("snapshot", null) == playbackSnapshot) {
                                clearPlaybackSnapshot()
                            }
                            result.success(null)
                        }
                        "takeRestore" -> {
                            result.success(restoredPlayback)
                            restoredPlayback = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duanju/device")
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "deviceInfo" -> {
                            val version = packageManager.getPackageInfo(packageName, 0).versionName
                            result.success(mapOf(
                                "version" to version,
                                "flipDevice" to flipDevice,
                                "pictureInPicture" to isInPictureInPictureMode
                            ))
                        }
                        "systemProxy" -> {
                            val connection = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                            val proxy = connection.defaultProxy
                            val host = proxy?.host.orEmpty()
                            val address = if (host.isNotEmpty() && (proxy?.port ?: 0) > 0) {
                                "http://${if (host.contains(':')) "[$host]" else host}:${proxy!!.port}"
                            } else ""
                            result.success(mapOf(
                                "http" to address,
                                "https" to address,
                                "bypass" to (proxy?.exclusionList?.toList() ?: emptyList<String>()),
                                "pac" to (proxy != null && proxy.pacFileUrl != Uri.EMPTY)
                            ))
                        }
                        "pictureInPictureStatus" -> result.success(pictureInPictureStatus())
                        "enterPictureInPicture" -> {
                            val width = call.argument<Int>("width") ?: 16
                            val height = call.argument<Int>("height") ?: 9
                            result.success(enterPlayerPictureInPicture(
                                width,
                                height,
                                call.argument<Int>("left"),
                                call.argument<Int>("top"),
                                call.argument<Int>("right"),
                                call.argument<Int>("bottom")
                            ))
                        }
                        "getBrightness" -> {
                            val lp = window.attributes
                            val current = if (lp.screenBrightness >= 0f) {
                                lp.screenBrightness.toDouble()
                            } else {
                                try {
                                    val sys = Settings.System.getInt(
                                        contentResolver,
                                        Settings.System.SCREEN_BRIGHTNESS
                                    )
                                    (sys / 255.0).coerceIn(0.0, 1.0)
                                } catch (e: Exception) {
                                    0.5
                                }
                            }
                            result.success(current)
                        }
                        "setBrightness" -> {
                            val value = call.argument<Double>("brightness")?.toFloat()
                            if (value != null) {
                                val lp = window.attributes
                                lp.screenBrightness = value.coerceIn(0.01f, 1.0f)
                                window.attributes = lp
                                result.success(true)
                            } else {
                                result.error("invalid_arg", "缺少亮度数值", null)
                            }
                        }
                        "resetBrightness" -> {
                            val lp = window.attributes
                            lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = lp
                            result.success(true)
                        }
                        "openExternalPlayer" -> {
                            val url = call.argument<String>("url")
                            val title = call.argument<String>("title") ?: "短剧"
                            if (!url.isNullOrEmpty()) {
                                try {
                                    val intent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(Uri.parse(url), "video/*")
                                        putExtra("title", title)
                                        putExtra("return_result", true)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    result.error("no_player", "未找到外部播放器: ${e.message}", null)
                                }
                            } else {
                                result.error("invalid_url", "播放地址为空", null)
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun pictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun pictureInPictureStatus(): Map<String, Any> {
        return mapOf(
            "supported" to pictureInPictureSupported(),
            "active" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode)
        )
    }

    private fun enterPlayerPictureInPicture(
        width: Int,
        height: Int,
        left: Int?,
        top: Int?,
        right: Int?,
        bottom: Int?
    ): Map<String, Any> {
        if (!pictureInPictureSupported()) return pictureInPictureStatus()
        val safeWidth = width.coerceIn(1, 10000)
        val safeHeight = height.coerceIn(1, 10000)
        return runCatching {
            val builder = PictureInPictureParams.Builder()
            builder.setAspectRatio(Rational(safeWidth, safeHeight))
            if (left != null && top != null && right != null && bottom != null &&
                right > left && bottom > top) {
                builder.setSourceRectHint(Rect(left, top, right, bottom))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(false)
            }
            val entered = enterPictureInPictureMode(builder.build())
            pictureInPictureStatus() + ("requested" to entered)
        }.getOrElse { pictureInPictureStatus() }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!isInPictureInPictureMode) retainTaskInRecents()
        notifyWindowChanged("pictureInPicture")
        deviceChannel?.invokeMethod(
            "pictureInPictureChanged",
            mapOf("active" to isInPictureInPictureMode)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        playbackChannel?.setMethodCallHandler(null)
        playbackChannel = null
        deviceChannel?.setMethodCallHandler(null)
        deviceChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

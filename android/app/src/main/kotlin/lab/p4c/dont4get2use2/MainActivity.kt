package lab.p4c.dont4get2use2

import android.app.AlarmManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG_SCREENSHOT = "GifticonScreenshot"
        private const val TAG_LATEST_IMAGE = "GifticonLatestImage"

        private const val METHOD_CHANNEL = "gifticon/latest_image_finder"
        private const val EVENT_CHANNEL = "gifticon/screenshot_events"
        private const val EXACT_ALARM_CHANNEL = "gifticon/exact_alarm"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var screenshotObserver: ContentObserver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "findLatestImage" -> {
                    try {
                        val latest = findLatestScreenshot()
                        result.success(latest)
                    } catch (e: Exception) {
                        result.error("LATEST_IMAGE_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXACT_ALARM_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canScheduleExactAlarms" -> {
                    try {
                        result.success(canScheduleExactAlarmsCompat())
                    } catch (e: Exception) {
                        result.error("EXACT_ALARM_CHECK_ERROR", e.message, null)
                    }
                }

                "openExactAlarmSettings" -> {
                    try {
                        openExactAlarmSettingsCompat()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXACT_ALARM_SETTINGS_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Log.d(TAG_SCREENSHOT, "event channel onListen")
                eventSink = events
                registerScreenshotObserver()
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG_SCREENSHOT, "event channel onCancel")
                unregisterScreenshotObserver()
                eventSink = null
            }
        })
    }

    override fun onDestroy() {
        unregisterScreenshotObserver()
        super.onDestroy()
    }

    private fun canScheduleExactAlarmsCompat(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true
        }

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun openExactAlarmSettingsCompat() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }

        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        startActivity(intent)
    }

    private fun findLatestScreenshot(): Map<String, Any?> {
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val debugLogs = mutableListOf<String>()

        val projection = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.RELATIVE_PATH
        ).apply {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                add(MediaStore.Images.Media.DATA)
            }
        }.toTypedArray()

        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        resolver.query(
            collection,
            projection,
            null,
            null,
            sortOrder
        )?.use { cursor ->
            debugLogs.add("cursor count=${cursor.count}")

            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val relativePathColumn =
                cursor.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)

            val dataColumn =
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                } else {
                    -1
                }

            var checked = 0

            while (cursor.moveToNext() && checked < 20) {
                checked++

                val id = cursor.getLong(idColumn)
                val fileName = cursor.getString(nameColumn)
                val sizeBytes = cursor.getLong(sizeColumn)
                val relativePath = cursor.getString(relativePathColumn) ?: ""
                val absolutePath =
                    if (dataColumn >= 0) cursor.getString(dataColumn) else null

                val isScreenshot = isLikelyScreenshot(
                    fileName = fileName,
                    relativePath = relativePath
                )

                debugLogs.add(
                    "candidate[$checked] fileName=$fileName, relativePath=$relativePath, absolutePath=$absolutePath, isScreenshot=$isScreenshot"
                )

                if (!isScreenshot) continue

                val contentUri = ContentUris.withAppendedId(collection, id)
                val cachePath = copyContentUriToCache(contentUri, fileName)

                Log.d(TAG_LATEST_IMAGE, "selected contentUri=$contentUri")
                Log.d(TAG_LATEST_IMAGE, "cachePath=$cachePath")

                return mapOf(
                    "path" to cachePath,
                    "fileName" to fileName,
                    "sizeBytes" to sizeBytes.toInt(),
                    "relativePath" to relativePath,
                    "contentUri" to contentUri.toString(),
                    "debugLogs" to debugLogs,
                )
            }
        }

        debugLogs.add("no screenshot found")

        return mapOf(
            "path" to null,
            "fileName" to null,
            "sizeBytes" to null,
            "relativePath" to null,
            "contentUri" to null,
            "debugLogs" to debugLogs,
        )
    }

    private fun isLikelyScreenshot(
        fileName: String?,
        relativePath: String?
    ): Boolean {
        val lowerName = fileName?.lowercase() ?: ""
        val lowerPath = relativePath?.lowercase() ?: ""

        return lowerName.contains("screenshot") ||
                lowerName.contains("screen_shot") ||
                lowerName.contains("screen-shot") ||
                lowerName.contains("capture") ||
                lowerName.contains("캡처") ||
                lowerName.contains("스크린샷") ||
                lowerPath.contains("screenshot") ||
                lowerPath.contains("screenshots") ||
                lowerPath.contains("screen_capture") ||
                lowerPath.contains("capture")
    }

    private fun copyContentUriToCache(
        contentUri: Uri,
        fileName: String?
    ): String? {
        val safeName = fileName ?: "latest_image.jpg"
        val outFile = File(cacheDir, "gifticon_$safeName")

        applicationContext.contentResolver.openInputStream(contentUri)?.use { input ->
            FileOutputStream(outFile).use { output ->
                input.copyTo(output)
            }
        } ?: return null

        return outFile.absolutePath
    }

    private fun registerScreenshotObserver() {
        if (screenshotObserver != null) {
            Log.d(TAG_SCREENSHOT, "observer already registered")
            return
        }

        Log.d(TAG_SCREENSHOT, "register screenshot observer")

        screenshotObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                Log.d(TAG_SCREENSHOT, "media store changed (legacy)")
                notifyScreenshotEvent("media_changed")
            }

            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                Log.d(TAG_SCREENSHOT, "media store changed uri=$uri")
                notifyScreenshotEvent("media_changed")
            }
        }

        applicationContext.contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            screenshotObserver!!
        )
    }

    private fun unregisterScreenshotObserver() {
        screenshotObserver?.let {
            Log.d(TAG_SCREENSHOT, "unregister screenshot observer")
            applicationContext.contentResolver.unregisterContentObserver(it)
        }
        screenshotObserver = null
    }

    private fun notifyScreenshotEvent(reason: String) {
        try {
            Log.d(TAG_SCREENSHOT, "emit screenshot event: $reason")
            eventSink?.success(
                mapOf(
                    "type" to "screenshot_candidate",
                    "reason" to reason,
                    "timestamp" to System.currentTimeMillis()
                )
            )
        } catch (e: Exception) {
            Log.e(TAG_SCREENSHOT, "failed to emit event: ${e.message}", e)
        }
    }
}
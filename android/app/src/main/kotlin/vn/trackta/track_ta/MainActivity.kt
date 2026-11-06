package vn.trackta.track_ta

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "vn.trackta.track_ta/rest_alarm"
    private val notificationRequestCode = 7011
    private var notificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotifications" -> requestNotifications(result)
                    "start" -> {
                        val seconds = call.argument<Int>("seconds")
                        if (seconds == null || seconds !in 1..3600) {
                            result.error("invalid_duration", "Thời gian nghỉ không hợp lệ", null)
                        } else if (!RestAlarm.canNotify(this)) {
                            result.error("notification_permission", "Cần bật thông báo", null)
                        } else if (!RestAlarm.canScheduleExactly(this)) {
                            result.error("exact_alarm_permission", "Cần cho phép báo thức chính xác", null)
                        } else {
                            try {
                                result.success(RestAlarm.start(this, seconds))
                            } catch (e: SecurityException) {
                                result.error("exact_alarm_permission", e.message, null)
                            }
                        }
                    }
                    "status" -> result.success(RestAlarm.deadline(this))
                    "cancel" -> {
                        RestAlarm.cancel(this)
                        result.success(null)
                    }
                    "openExactAlarmSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (notificationResult != null) {
                result.error("busy", "Đang hỏi quyền thông báo", null)
                return
            }
            notificationResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
        } else {
            result.success(RestAlarm.canNotify(this))
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationRequestCode) {
            notificationResult?.success(RestAlarm.canNotify(this))
            notificationResult = null
        }
    }
}

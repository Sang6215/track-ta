import 'package:flutter/services.dart';

/// Android owns the alarm so it can finish after Flutter is closed.
class RestAlarm {
  static const channel = MethodChannel('vn.trackta.track_ta/rest_alarm');

  static Future<bool> requestNotifications() async =>
      await channel.invokeMethod<bool>('requestNotifications') ?? false;

  static Future<DateTime> start(int seconds) async {
    final millis = await channel.invokeMethod<int>('start', {
      'seconds': seconds,
    });
    if (millis == null) throw PlatformException(code: 'no_deadline');
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static Future<DateTime?> status() async {
    final millis = await channel.invokeMethod<int>('status') ?? 0;
    return millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  static Future<void> cancel() => channel.invokeMethod<void>('cancel');

  static Future<void> openExactAlarmSettings() =>
      channel.invokeMethod<void>('openExactAlarmSettings');

  static Future<void> openNotificationSettings() =>
      channel.invokeMethod<void>('openNotificationSettings');
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
        
    const DarwinInitializationSettings iosSettings = 
        DarwinInitializationSettings(requestAlertPermission: true);
        
    const InitializationSettings settings = 
        InitializationSettings(android: androidSettings, iOS: iosSettings);
        
    await _notificationsPlugin.initialize(settings);
  }

  static Future<void> scheduleStreakReminder() async {
    await _notificationsPlugin.zonedSchedule(
      1, 
      'Keep your streak alive! 🔥',
      'Play a quick game today to protect your streak.',
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 24)),
      const NotificationDetails(
        android: AndroidNotificationDetails('streak_channel', 'Streaks', importance: Importance.max),
      ),
      // FIX: Changed from exactAllowWhileIdle to inexactAllowWhileIdle
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, 
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelStreakReminder() async {
    await _notificationsPlugin.cancel(1);
  }
}
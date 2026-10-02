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

  // NEW: Instant notification for Friend Challenge Invites
  static Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
    bool playSound = true,
    bool enableVibration = true,
  }) async {
    // Dynamic channel ID handles Android's immutable notification channel behavior
    final String channelId = 'challenge_channel_${playSound}_$enableVibration';
    
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      'Challenge Invites',
      importance: Importance.max,
      priority: Priority.high,
      playSound: playSound,
      enableVibration: enableVibration,
    );
    
    NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      id,
      title,
      body,
      details,
    );
  }

  static Future<void> scheduleStreakReminder({
    bool playSound = true,
    bool enableVibration = true,
  }) async {
    final String channelId = 'streak_channel_${playSound}_$enableVibration';

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      'Streaks', 
      importance: Importance.max,
      playSound: playSound,
      enableVibration: enableVibration,
    );

    await _notificationsPlugin.zonedSchedule(
      1, 
      'Keep your streak alive! 🔥',
      'Play a quick game today to protect your streak.',
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 24)),
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, 
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelStreakReminder() async {
    await _notificationsPlugin.cancel(1);
  }
}
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  static final plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  static Future<void> schedule(
    int id,
    String title,
    int hour,
    int minute,
  ) async {
    await init();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final permission = await android?.requestNotificationsPermission();
    if (permission == false) {
      throw StateError(
        'Permissão de notificação negada nas configurações do Android.',
      );
    }
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day, hour, minute);
    if (!date.isAfter(now)) date = date.add(const Duration(days: 1));
    // ponytail: one reminder at next chosen local time; daily recurring reminders need timezone-change handling.
    await plugin.zonedSchedule(
      id,
      title,
      'Seu ritmo importa. Registre quando fizer sentido para você.',
      tz.TZDateTime.from(date, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'gentle_reminders',
          'Lembretes de cuidado',
          channelDescription: 'Lembretes opcionais sem pressão',
          importance: Importance.defaultImportance,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) async {
    await init();
    await plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await init();
    await plugin.cancelAll();
  }
}

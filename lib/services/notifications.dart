import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Rappels locaux (Android / iOS). Sans effet sur les autres plateformes.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  // App personnelle : fuseau fixé. Changer ici si besoin.
  static const _timeZone = 'Europe/Paris';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'review_reminders',
      'Rappels de révision',
      channelDescription: 'Rappels pour revoir tes sujets',
      icon: 'ic_notification',
      color: Color(0xFF2A78D6),
    ),
    iOS: DarwinNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supported) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(_timeZone));
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications indisponibles : $e');
    }
  }

  /// Demande l'autorisation d'afficher des notifications.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final a = await android?.requestNotificationsPermission();
      final i = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return a ?? i ?? false;
    } catch (e) {
      debugPrint('Permission notifications : $e');
      return false;
    }
  }

  /// Programme une notification unique le jour [day] à [hour]:[minute].
  /// Ignorée si l'heure est déjà passée.
  Future<void> scheduleOnce({
    required int id,
    required DateTime day,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      final when = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        hour,
        minute,
      );
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details,
        // Inexact : pas besoin de la permission « alarmes exactes »
        // (l'heure peut varier de quelques minutes).
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Planification du rappel : $e');
    }
  }

  /// Affiche tout de suite une notification, pour vérifier les réglages.
  /// Renvoie faux si les notifications ne sont pas disponibles.
  Future<bool> showTest() async {
    if (!_ready) return false;
    try {
      await _plugin.show(
        0,
        'Les rappels fonctionnent',
        'Tu recevras une notification comme celle-ci les jours de révision.',
        _details,
      );
      return true;
    } catch (e) {
      debugPrint('Notification de test : $e');
      return false;
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Annulation des rappels : $e');
    }
  }
}

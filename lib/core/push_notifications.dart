import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final FlutterLocalNotificationsPlugin localNotificationsPlugin = FlutterLocalNotificationsPlugin();

/// Decodes the JSON payload string attached to a local notification (set
/// in [showForegroundNotification]) back into the string map used for
/// tap routing. Never throws — a malformed or missing payload just means
/// no routing data, not a crash on tap.
Map<String, String> decodeNotificationPayload(String? raw) {
  if (raw == null) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    }
  } catch (_) {
    // Fall through to the empty-map return below.
  }
  return {};
}

const AndroidNotificationChannel androidNotificationChannel = AndroidNotificationChannel(
  'meowes_default',
  'Meowes',
  description: 'Expense and pet-care alerts',
  importance: Importance.high,
);

/// Registered with `FirebaseMessaging.onBackgroundMessage` in main.dart.
/// Must be a top-level (or static) function — the plugin runs it in its
/// own isolate. Left empty: Android/iOS already render the FCM
/// `notification` payload as a system notification while the app is
/// backgrounded or terminated, without any app code needing to run. This
/// only exists because the plugin requires a handler to be registered at
/// all, even a no-op one.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// [onTap] fires for notifications *this app* displayed via
/// [showForegroundNotification] — a separate path from
/// `FirebaseMessaging.onMessageOpenedApp`/`getInitialMessage`, which only
/// cover notifications the OS posted natively for background/terminated
/// delivery. Both paths need their own tap handling.
Future<void> initLocalNotifications({
  required void Function(Map<String, String> data) onTap,
}) async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await localNotificationsPlugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (response) => onTap(decodeNotificationPayload(response.payload)),
  );
  await localNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidNotificationChannel);
}

/// FCM only auto-displays a system notification for background/terminated
/// messages — in the foreground it just hands the app a [RemoteMessage],
/// so this shows it explicitly via flutter_local_notifications instead.
void showForegroundNotification(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;
  localNotificationsPlugin.show(
    id: notification.hashCode,
    title: notification.title,
    body: notification.body,
    payload: jsonEncode(message.data),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        androidNotificationChannel.id,
        androidNotificationChannel.name,
        channelDescription: androidNotificationChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}

/// Requests permission and registers this device's FCM token against the
/// signed-in user via `register_device_token()` — a no-op until someone's
/// actually signed in, so this is safe to call from every auth-state
/// change rather than needing its own separate trigger.
Future<void> registerPushToken(SupabaseClient client) async {
  if (client.auth.currentUser == null) return;
  // iOS push isn't configured yet (no GoogleService-Info.plist / APNs key) —
  // see the matching guard around Firebase.initializeApp() in main.dart.
  if (!Platform.isAndroid) return;

  final settings = await FirebaseMessaging.instance.requestPermission();
  final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;
  if (!granted) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await client.rpc('register_device_token', params: {
    'p_token': token,
    'p_platform': Platform.isIOS ? 'ios' : 'android',
  });
}

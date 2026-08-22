import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meowes_app/core/app_theme.dart';
import 'package:meowes_app/core/push_notifications.dart';
import 'package:meowes_app/features/activity/activity_screen.dart';
import 'package:meowes_app/features/friends/join_by_invite_screen.dart';
import 'package:meowes_app/features/pet/pet_feed_deep_link_screen.dart';
import 'package:meowes_app/features/root/root_screen.dart';
import 'package:meowes_app/firebase_options.dart';

/// Lets the deep-link handling below push a route without threading a
/// BuildContext through — the link can arrive before any screen using ref
/// has mounted.
final rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  // Android reads its config natively from google-services.json (via the
  // Google Services Gradle plugin), so it must init with no explicit
  // options — passing DefaultFirebaseOptions.android here would point at
  // the wrong Firebase app id (com.meowes.meowesApp vs the actual
  // com.meowes.meowes_app applicationId).
  if (Platform.isAndroid) {
    await Firebase.initializeApp();
  } else if (Platform.isIOS) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.ios);
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await initLocalNotifications(onTap: _handleNotificationTap);
  runApp(const ProviderScope(child: MeowesApp()));
}

/// Where every push notification leads on tap. Most event kinds (expense
/// splits, streak milestones, friend reminders) already show up in the
/// Activity feed, so they route there. `pet_hungry` pushes carry a
/// `food_key` in their data payload and route straight to the feed
/// screen instead, with that food highlighted. Top-level rather than a
/// State method: [initLocalNotifications] is called from `main()`,
/// before any [_MeowesAppState] instance exists.
void _handleNotificationTap(Map<String, String> data) {
  if (data['type'] == 'pet_hungry') {
    _openFeedFlow(data['food_key']);
    return;
  }
  _openActivity();
}

void _openActivity() {
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const ActivityScreen()),
  );
}

void _openFeedFlow(String? foodKey) {
  rootNavigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => PetFeedDeepLinkScreen(foodKey: foodKey)),
  );
}

class MeowesApp extends StatefulWidget {
  const MeowesApp({super.key});

  @override
  State<MeowesApp> createState() => _MeowesAppState();
}

class _MeowesAppState extends State<MeowesApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _messageTapSub;

  /// An invite code from a `meowes://invite/<code>` link that arrived
  /// before sign-in finished — redeemed once a session shows up in
  /// [_authSub], since the join RPC needs an authenticated `auth.uid()`.
  String? _pendingInviteCode;

  @override
  void initState() {
    super.initState();
    _appLinks.getInitialLink().then(_handleLink);
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _consumePendingInvite();
      registerPushToken(Supabase.instance.client);
    });

    _foregroundMessageSub = FirebaseMessaging.onMessage.listen(showForegroundNotification);
    _messageTapSub = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleNotificationTap(Map<String, String>.from(message.data)),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(Map<String, String>.from(message.data));
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _authSub?.cancel();
    _foregroundMessageSub?.cancel();
    _messageTapSub?.cancel();
    super.dispose();
  }

  void _handleLink(Uri? uri) {
    if (uri == null || uri.scheme != 'meowes' || uri.host != 'invite') return;
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (code == null || code.isEmpty) return;
    _pendingInviteCode = code;
    _consumePendingInvite();
  }

  void _consumePendingInvite() {
    final code = _pendingInviteCode;
    if (code == null || Supabase.instance.client.auth.currentUser == null) return;
    _pendingInviteCode = null;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => JoinByInviteScreen(inviteCode: code)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Meowes',
      theme: AppTheme.light,
      // Dark mode is disabled for now — light is the only supported theme.
      themeMode: ThemeMode.light,
      home: const RootScreen(),
    );
  }
}

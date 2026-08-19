// lib/features/notifications/services/push_notification_service.dart

import 'dart:developer';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_notifier/local_notifier.dart'; // NEW: For native Windows toasts

/// Top-level function to handle background messages when the app is closed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  log('Handling a background message: ${message.messageId}');
}

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  RealtimeChannel? _desktopChannel;

  // Safely check for desktop platforms without breaking Web compilation
  bool get _isWindowsOrLinux => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (_isWindowsOrLinux) {
        // WINDOWS ROUTE: Bypass Firebase, use Supabase Realtime
        await _initializeDesktopRealtime();
      } else {
        // MOBILE/MAC/WEB ROUTE: Standard Firebase Cloud Messaging
        await _initializeFirebaseMobile();
      }

      _isInitialized = true;
    } catch (e) {
      log('Failed to initialize push notifications: $e');
    }
  }

  // --- NEW: DESKTOP IMPLEMENTATION ---
  Future<void> _initializeDesktopRealtime() async {
    log('Initializing Supabase Realtime for Desktop Notifications...');

    // 1. Setup native Windows toast integration
    await localNotifier.setup(
      appName: 'AEC LMS',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );

    // 2. Don't just check currentUser once — if the session hasn't finished
    // restoring yet at this exact moment, we'd give up permanently and the
    // listener would never be created for the rest of the app's lifetime.
    // Instead, react to auth state so the channel is (re)built whenever a
    // session actually becomes available (login, session restore, etc).
    final initialUser = Supabase.instance.client.auth.currentUser;
    if (initialUser != null) {
      _subscribeToDesktopNotifications(initialUser.id);
    }

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _subscribeToDesktopNotifications(user.id);
      } else {
        // Signed out — tear down the old channel so we don't leak a
        // subscription filtered on a stale user id.
        _desktopChannel?.unsubscribe();
        _desktopChannel = null;
      }
    });
  }

  void _subscribeToDesktopNotifications(String userId) {
    // Avoid creating a second overlapping channel if this fires more than
    // once (e.g. token refresh events also pass through onAuthStateChange).
    if (_desktopChannel != null) return;

    _desktopChannel = Supabase.instance.client
        .channel('desktop_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications', // NOTE: Verify this matches your table name exactly
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (payload) {
            log('🔔 Desktop notification payload received: ${payload.newRecord}');

            final record = payload.newRecord;
            final title = record['title'] as String? ?? 'AEC LMS Alert';
            final body = record['body'] as String? ?? 'You have a new notification.';

            // 3. Trigger the native Windows popup
            final notification = LocalNotification(
              title: title,
              body: body,
            );
            notification.show();
          },
        )
        .subscribe((status, error) {
          log('🔌 Desktop notification subscription status: $status');
          if (error != null) {
            log('❌ Desktop notification subscription error: $error');
          }
        });
  }

  // --- EXISTING: MOBILE IMPLEMENTATION ---
  Future<void> _initializeFirebaseMobile() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    log('User granted permission: ${settings.authorizationStatus}');

    await _setupForegroundNotifications();
    await _saveDeviceToken();

    _fcm.onTokenRefresh.listen((newToken) {
      _updateTokenInSupabase(newToken);
    });
  }

  Future<void> _setupForegroundNotifications() async {
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    // FIXED: Using 'settings:' to match the newer API signature
    await _localNotifications.initialize(settings: initSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', 
      'High Importance Notifications', 
      description: 'This channel is used for important alerts.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/launcher_icon',
              priority: Priority.high,
              importance: Importance.max,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
        );
      }
    });
  }

  Future<void> _saveDeviceToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _updateTokenInSupabase(token);
      }
    } catch (e) {
      log('Error getting FCM token: $e');
    }
  }

  Future<void> _updateTokenInSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);
      log('FCM Token saved to Supabase successfully.');
    } catch (e) {
      log('Failed to save FCM token to Supabase: $e');
    }
  }
}
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../screens/messages_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class AppNotificationService {
  AppNotificationService._();

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _messagesChannel =
      AndroidNotificationChannel(
        'messages_high_importance',
        'Messages',
        description: 'Notifications de nouveaux messages',
        importance: Importance.max,
        playSound: true,
      );

  static final Map<String, int> _lastUnreadCounts = <String, int>{};
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _conversationSubscription;
  static StreamSubscription<User?>? _authSubscription;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _initialized = false;
  static bool _seededConversationSnapshot = false;

  static Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _initializeLocalNotifications();
    await _initializeFirebaseMessaging();
    _listenToAuthChanges();
  }

  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (_) => _openMessagesPage(),
    );

    final androidPlatform = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlatform?.createNotificationChannel(_messagesChannel);
    await androidPlatform?.requestNotificationsPermission();
  }

  static Future<void> _initializeFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;
    if (!kIsWeb) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _saveTokenForUser(user.uid);
      unawaited(_startConversationWatcher(user.uid));
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openMessagesPage());
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _openMessagesPage();
    }

    messaging.onTokenRefresh.listen((_) async {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      await _saveTokenForUser(currentUser.uid);
    });
  }

  static void _listenToAuthChanges() {
    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) async {
      if (user == null) {
        await _stopConversationWatcher();
        return;
      }
      await _saveTokenForUser(user.uid);
      await _startConversationWatcher(user.uid);
    });
  }

  static Future<void> _saveTokenForUser(String uid) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('profiles').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token.trim()]),
      'lastFcmToken': token.trim(),
      'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _startConversationWatcher(String uid) async {
    await _stopConversationWatcher();
    _seededConversationSnapshot = false;
    _conversationSubscription = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
          final previousCounts = Map<String, int>.from(_lastUnreadCounts);
          _lastUnreadCounts.clear();

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final unreadBy = (data['unreadBy'] as Map<String, dynamic>?) ?? {};
            final unreadCount = (unreadBy[uid] as num?)?.toInt() ?? 0;
            _lastUnreadCounts[doc.id] = unreadCount;
            if (!_seededConversationSnapshot) continue;

            final previous = previousCounts[doc.id] ?? 0;
            final isMuted = ((data['mutedBy'] as List?) ?? const <dynamic>[])
                .map((value) => value.toString())
                .contains(uid);
            if (isMuted || unreadCount <= previous || unreadCount <= 0) {
              continue;
            }

            final preview = (data['lastMessage'] as String?)?.trim() ?? '';
            final title = (data['title'] as String?)?.trim();
            final safeTitle = title?.isNotEmpty == true
                ? title!
                : 'Nouveau message';
            final safeBody = preview.isNotEmpty
                ? preview
                : 'Vous avez reçu un nouveau message.';
            unawaited(
              showIncomingMessageNotification(title: safeTitle, body: safeBody),
            );
          }

          _seededConversationSnapshot = true;
        });
  }

  static Future<void> _stopConversationWatcher() async {
    await _conversationSubscription?.cancel();
    _conversationSubscription = null;
    _seededConversationSnapshot = false;
    _lastUnreadCounts.clear();
  }

  static Future<void> _handleForegroundRemoteMessage(
    RemoteMessage message,
  ) async {
    final notification = message.notification;
    final title = notification?.title?.trim().isNotEmpty == true
        ? notification!.title!.trim()
        : 'Nouveau message';
    final body = notification?.body?.trim().isNotEmpty == true
        ? notification!.body!.trim()
        : 'Vous avez reçu un nouveau message.';
    await showIncomingMessageNotification(title: title, body: body);
  }

  static Future<void> showIncomingMessageNotification({
    required String title,
    required String body,
  }) async {
    SystemSound.play(SystemSoundType.alert);
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const androidDetails = AndroidNotificationDetails(
      'messages_high_importance',
      'Messages',
      channelDescription: 'Notifications de nouveaux messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'message',
    );
    const details = NotificationDetails(android: androidDetails);
    await _localNotificationsPlugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static void _openMessagesPage() {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MessagesScreen()));
  }
}

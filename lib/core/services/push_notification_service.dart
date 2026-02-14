// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../firebase_options.dart';

/// Push 알림 서비스
/// - Firebase 초기화
/// - 알림 권한 요청
/// - FCM 토큰 획득 및 Supabase 저장
/// - 포그라운드 메시지 수신 처리
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const String _vapidKey = 'BHct41-ppJSfXJ5vTmPXDoRZ18qPE6Jk9u9Dv3qpI5wekoSAAJO49PuTn4fCDgoz8y9-OJW21d3mvvlpAjfrjEM';

  bool _initialized = false;
  String? _currentToken;

  String? get currentToken => _currentToken;
  bool get isInitialized => _initialized;

  /// 서비스 초기화 (앱 시작 시 1회 호출)
  Future<void> initialize() async {
    if (!kIsWeb || _initialized) return;

    try {
      // 1. Firebase 초기화
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('PushNotificationService: Firebase initialized');

      // 2. Service Worker 등록
      await _registerServiceWorker();

      // 3. 포그라운드 메시지 리스너 설정
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      _initialized = true;
      debugPrint('PushNotificationService: Initialized successfully');
    } catch (e) {
      debugPrint('PushNotificationService: Init error: $e');
    }
  }

  /// 알림 권한 요청 + 토큰 저장 (로그인 후 호출)
  Future<bool> requestPermissionAndSaveToken() async {
    if (!kIsWeb || !_initialized) return false;

    try {
      // 1. 알림 권한 요청
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('PushNotificationService: Permission granted');

        // 2. FCM 토큰 획득
        final token = await FirebaseMessaging.instance.getToken(vapidKey: _vapidKey);
        if (token != null) {
          _currentToken = token;
          debugPrint('PushNotificationService: Token acquired (${token.substring(0, 20)}...)');

          // 3. Supabase에 토큰 저장
          await _saveTokenToSupabase(token);

          // 4. 토큰 갱신 리스너
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
            _saveTokenToSupabase(newToken);
          });

          return true;
        }
      } else {
        debugPrint('PushNotificationService: Permission denied');
      }
    } catch (e) {
      debugPrint('PushNotificationService: Error: $e');
    }
    return false;
  }

  /// FCM 토큰을 Supabase에 저장
  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('PushNotificationService: No user logged in, skipping token save');
        return;
      }

      // 브라우저 정보
      final userAgent = html.window.navigator.userAgent;
      final deviceInfo = _parseDeviceInfo(userAgent);

      await Supabase.instance.client.from('fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'device_info': deviceInfo,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
      debugPrint('PushNotificationService: Token saved to Supabase');
    } catch (e) {
      debugPrint('PushNotificationService: Failed to save token: $e');
    }
  }

  /// 로그아웃 시 토큰 제거
  Future<void> removeToken() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null && _currentToken != null) {
        await Supabase.instance.client
            .from('fcm_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', _currentToken!);
        debugPrint('PushNotificationService: Token removed');
      }
      _currentToken = null;
    } catch (e) {
      debugPrint('PushNotificationService: Failed to remove token: $e');
    }
  }

  /// Service Worker 등록
  Future<void> _registerServiceWorker() async {
    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw != null) {
        await sw.register('/firebase-messaging-sw.js');
        debugPrint('PushNotificationService: Service worker registered');
      }
    } catch (e) {
      debugPrint('PushNotificationService: SW registration error: $e');
    }
  }

  /// 포그라운드 메시지 핸들러
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('PushNotificationService: Foreground message: ${message.notification?.title}');
    
    // 포그라운드에서는 브라우저 Notification API로 직접 표시
    if (message.notification != null) {
      final title = message.notification!.title ?? 'Grace Note';
      final body = message.notification!.body ?? '';
      
      // 브라우저 알림 표시
      try {
        html.Notification(title, body: body, icon: '/icons/Icon-192.png');
      } catch (e) {
        debugPrint('PushNotificationService: Notification display error: $e');
      }
    }
  }

  /// User-Agent에서 간단한 디바이스 정보 추출
  String _parseDeviceInfo(String userAgent) {
    if (userAgent.contains('iPhone') || userAgent.contains('iPad')) {
      return 'iOS Safari';
    } else if (userAgent.contains('Android')) {
      return 'Android Chrome';
    } else if (userAgent.contains('Mac')) {
      return 'macOS';
    } else if (userAgent.contains('Windows')) {
      return 'Windows';
    }
    return 'Web Browser';
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../firebase_options.dart';
import 'package:grace_note/features/home/presentation/screens/notice_list_screen.dart';
import 'package:grace_note/core/services/web_push_runtime.dart';

/// Push 알림 서비스
/// - Firebase 초기화
/// - 알림 권한 요청
/// - FCM 토큰 획득 및 Supabase 저장
/// - 포그라운드 메시지 수신 처리
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const String _vapidKey =
      'BKs48C2r24xErHWw892q9JK7IQbBY4fkcI_yEPSpZVWNR10iOz5sdCrYOVT1s0WJs2JgnDwQ-yrVM4Q2WaDUOvo';

  bool _initialized = false;
  String? _currentToken;

  /// 글로벌 Navigator Key (main.dart에서 설정)
  static GlobalKey<NavigatorState>? navigatorKey;

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

      // 4. Service Worker 메시지 리스너 (알림 클릭 딥링크)
      _listenForNotificationClicks();

      _initialized = true;
      debugPrint('PushNotificationService: Initialized successfully');
    } catch (e) {
      debugPrint('PushNotificationService: Init error: $e');
    }
  }

  /// 알림 권한 요청 + 토큰 저장 (로그인 후 호출)
  /// - 권한이 이미 허용된 경우에도 최신 토큰을 항상 저장
  ///   (Service Worker 업데이트 후 토큰이 갱신돼도 DB에 반영되도록)
  Future<bool> requestPermissionAndSaveToken() async {
    if (!kIsWeb || !_initialized) return false;

    try {
      // 1. 알림 권한 요청 (이미 허용된 경우 팝업 없이 바로 통과)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('PushNotificationService: Permission granted');

        // 2. FCM 토큰 획득 (Service Worker 업데이트 후 새 토큰이 발급됐을 수 있음)
        final token =
            await FirebaseMessaging.instance.getToken(vapidKey: _vapidKey);
        if (token != null) {
          _currentToken = token;
          debugPrint(
              'PushNotificationService: Token acquired (${token.substring(0, 20)}...)');

          // 3. Supabase에 토큰 저장 (항상 upsert → 배포 후 토큰 갱신 대응)
          await _saveTokenToSupabase(token);

          // 4. 토큰 갱신 리스너 (런타임 중 FCM이 토큰을 교체하는 경우 대응)
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
            debugPrint(
                'PushNotificationService: Token refreshed, updating DB...');
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
        debugPrint(
            'PushNotificationService: No user logged in, skipping token save');
        return;
      }

      // 브라우저 정보
      final userAgent = getBrowserUserAgent();
      final deviceInfo = _parseDeviceInfo(userAgent);

      // 같은 토큰이 다른 사용자에게 등록되어 있으면 삭제 (기기 전환 대응)
      await Supabase.instance.client
          .from('fcm_tokens')
          .delete()
          .eq('token', token)
          .neq('user_id', userId);

      await Supabase.instance.client.from('fcm_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'device_info': deviceInfo,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      await registerBrowserServiceWorker('/firebase-messaging-sw.js');
      debugPrint('PushNotificationService: Service worker registered');
    } catch (e) {
      debugPrint('PushNotificationService: SW registration error: $e');
    }
  }

  /// 포그라운드 메시지 핸들러 (data-only messages)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('PushNotificationService: Foreground message received');

    // data-only 메시지에서 title/body 추출
    final data = message.data;
    final title = data['title'] ?? message.notification?.title ?? 'Grace Note';
    final body = data['body'] ?? message.notification?.body ?? '';

    if (title.isNotEmpty) {
      try {
        showBrowserNotification(
          title,
          body: body,
          icon: '/icons/Icon-192.png',
        );
      } catch (e) {
        debugPrint('PushNotificationService: Notification display error: $e');
      }
    }
  }

  /// Service Worker에서 알림 클릭 메시지 수신
  void _listenForNotificationClicks() {
    try {
      listenForBrowserServiceWorkerMessages((link) {
        debugPrint(
            'PushNotificationService: Deep link from notification: $link');
        _handleDeepLink(link);
      });
      debugPrint('PushNotificationService: SW message listener registered');
    } catch (e) {
      debugPrint('PushNotificationService: SW message listener error: $e');
    }
  }

  /// 앱 시작 시 URL의 deeplink 쿼리 파라미터 확인 (새 창으로 열린 경우)
  void checkInitialDeepLink() {
    try {
      final uri = Uri.parse(getBrowserLocationHref());
      final deeplink = uri.queryParameters['deeplink'];
      if (deeplink != null && deeplink.isNotEmpty) {
        debugPrint('PushNotificationService: Initial deep link: $deeplink');
        // URL에서 deeplink 파라미터 제거
        replaceBrowserHistoryUrl('/');
        // 앱 로딩 완료 후 네비게이션
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleDeepLink(deeplink);
        });
      }
    } catch (e) {
      debugPrint('PushNotificationService: Initial deep link check error: $e');
    }
  }

  /// 딥링크 경로에 따라 화면 이동
  void _handleDeepLink(String link) {
    final nav = navigatorKey?.currentState;
    if (nav == null) {
      debugPrint('PushNotificationService: Navigator not available yet');
      return;
    }

    if (link.contains('notices')) {
      nav.push(MaterialPageRoute(builder: (_) => const NoticeListScreen()));
    }
    // 필요 시 다른 딥링크 경로 추가
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

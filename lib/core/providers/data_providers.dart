import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/repositories/grace_note_repository.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// Repository Providers
final repositoryProvider = Provider((ref) => GraceNoteRepository());

// Current User Profile Provider (Auth linked & Real-time Reactive)
final userProfileProvider = StreamProvider<ProfileModel?>((ref) async* {
  // Rebuild on auth changes (logout/login)
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    yield null;
    return;
  }

  ProfileModel? lastKnownProfile;

  try {
    final initialProfile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (initialProfile != null) {
      lastKnownProfile = ProfileModel.fromJson(initialProfile);
      yield lastKnownProfile;
    }
  } catch (e) {
    debugPrint('userProfileProvider: Initial profile fetch failed, falling back to realtime stream: $e');
  }

  // [FIX] 웹소켓 끊김/초기 네트워크 에러 시 무한 재시도로 강력하게 복구
  while (true) {
    try {
      final stream = Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', user.id)
          .map((data) {
            if (data.isEmpty) return lastKnownProfile;
            lastKnownProfile = ProfileModel.fromJson(data.first);
            return lastKnownProfile;
          })
          // [FIX] RealtimeSubscribeException(timedOut) 등 Realtime 에러를 stream 레벨에서 흡수
          // yield* 로 에러가 전파되기 전에 차단하여 provider가 AsyncError로 전환되지 않도록 방지
          .handleError((e) {
            debugPrint('userProfileProvider: Realtime stream error (swallowed, will retry): $e');
          })
          .distinct();

      yield* stream;

      // 스트림이 예기치 않게 종료된 경우 2초 대기 후 다시 열기 시도
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('userProfileProvider: Unexpected error, retrying in 2s: $e');
      await Future.delayed(const Duration(seconds: 2));
    }
  }
});

// [NEW] Helper provider for a definitive profile fetch (used to speed up redirection)
final userProfileFutureProvider = FutureProvider<ProfileModel?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  // Retry up to 10 times for the profile to appear (DB trigger delay can be high under load)
  for (int i = 0; i < 10; i++) {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        final profile = ProfileModel.fromJson(response);
        if (profile.isOnboardingComplete) {
          debugPrint('userProfileFutureProvider: Found completed profile');
          return profile;
        }
        debugPrint('userProfileFutureProvider: Found profile but onboarding incomplete. Retrying...');
      }
    } catch (e) {
      debugPrint('userProfileFutureProvider: Fetch attempt ${i + 1} failed: $e');
      // [FIX] Failed to fetch 등 네트워크 에러 시에도 잠시 대기 후 재시도
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }
  debugPrint('userProfileFutureProvider: Failed to find completed profile after retires');
  return null;
});

// Auth State Provider
final authStateProvider = StreamProvider<AuthState>((ref) {
  // Use a broadcast stream to allow multiple listeners
  return Supabase.instance.client.auth.onAuthStateChange.handleError((e) {
    // [ROOT CAUSE FIX] Ignore transient PKCE errors on web refresh
    if (e.toString().contains('Code verifier')) {
      debugPrint('Ignoring transient PKCE error: $e');
      return; 
    }
    throw e;
  });
});

// All churches available for selection
final allChurchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await Supabase.instance.client
      .from('churches')
      .select('id, name');
      
  return (response as List).map<Map<String, dynamic>>((e) => {
    'id': e['id'],
    'name': e['name'],
  }).toList();
});

// Fetch single church name by ID
final churchNameProvider = FutureProvider.family<String, String>((ref, churchId) async {
  final response = await Supabase.instance.client
      .from('churches')
      .select('name')
      .eq('id', churchId)
      .single();
  return response['name'] as String;
});

// Fetch single department name by ID
final departmentNameProvider = FutureProvider.family<String, String>((ref, departmentId) async {
  final response = await Supabase.instance.client
      .from('departments')
      .select('name')
      .eq('id', departmentId)
      .single();
  return response['name'] as String;
});

// All groups in the church
final churchGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, churchId) async {
  final response = await Supabase.instance.client
      .from('groups')
      .select('id, name')
      .eq('church_id', churchId)
      .eq('is_active', true);
      
  return (response as List).map<Map<String, dynamic>>((e) => {
    'id': e['id'],
    'name': e['name'],
  }).toList();
});

// [NEW] Get all existing week dates for navigation restriction
final availableWeeksProvider = StreamProvider.family<List<DateTime>, String>((ref, churchId) {
  return Supabase.instance.client
      .from('weeks')
      .stream(primaryKey: ['id'])
      .eq('church_id', churchId)
      .order('week_date', ascending: false) // 최신순 정렬
      .map((data) {
        return data.where((e) => e['is_active'] != false).map<DateTime>((e) {
          return DateTime.parse(e['week_date'] as String);
        }).toList();
      })
      .handleError((e) {
        debugPrint('availableWeeksProvider error: $e');
        return <DateTime>[];
      });
});

// User's assigned groups (Real-time Reactive)
final userGroupsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value([]);

  final controller = StreamController<List<Map<String, dynamic>>>();
  
  // Re-fetch logic with a small protective delay for DB triggers/sync
  Future<void> triggerUpdate() async {
    // 0.2s is enough for triggers and publication to sync
    await Future.delayed(const Duration(milliseconds: 200));
    if (controller.isClosed) return;
    
    // [FIX] Add infinite retry logic: 네트워크 회복 시 즉각 복구되도록 멈추지 않음
    bool success = false;
    int attempt = 0;
    while (!success && !controller.isClosed) {
      try {
        final data = await _fetchUserGroups(user.id);
        if (!controller.isClosed) {
          controller.add(data);
          success = true;
          return; // Success, exit
        }
      } catch (e) {
        attempt++;
        debugPrint('userGroupsProvider: Error refreshing user groups (attempt $attempt): $e');
        await Future.delayed(const Duration(seconds: 2)); // Wait before retrying
      }
    }
  }

  // Initial fetch
  triggerUpdate();

  // Listen to BOTH group_members and member_directory for changes
  final gmSub = Supabase.instance.client
      .from('group_members')
      .stream(primaryKey: ['id'])
      .eq('profile_id', user.id)
      .listen(
        (_) => triggerUpdate(),
        onError: (e, stack) {
          debugPrint('userGroupsProvider: group_members stream error: $e');
          // [FIX] 실시간 업데이트 실패가 전체 앱 구동을 막지 않도록 에러를 스트림 컨트롤러에 전달하지 않음
        },
      );

  final mdSub = Supabase.instance.client
      .from('member_directory')
      .stream(primaryKey: ['id'])
      .eq('profile_id', user.id)
      .listen(
        (_) => triggerUpdate(),
        onError: (e, stack) {
          debugPrint('userGroupsProvider: member_directory stream error: $e');
          // [FIX] 실시간 업데이트 실패가 전체 앱 구동을 막지 않도록 에러를 스트림 컨트롤러에 전달하지 않음
        },
      );

  ref.onDispose(() {
    gmSub.cancel();
    mdSub.cancel();
    controller.close();
  });

  return controller.stream;
});

// Helper for re-fetching detailed group data with joins
// [ENHANCEMENT] Use synced role_in_group from group_members and sort by privilege
Future<List<Map<String, dynamic>>> _fetchUserGroups(String profileId) async {
  final response = await Supabase.instance.client
      .from('group_members')
      .select('group_id, role_in_group, groups(name, church_id, department_id, color_hex, is_new_member_group, climbing_threshold, departments(name, profile_mode))')
      .eq('profile_id', profileId)
      .eq('is_active', true)
      .order('joined_at', ascending: false);
      
  final List<Map<String, dynamic>> rawGroups = (response as List).map<Map<String, dynamic>>((e) {
    return {
      'group_id': e['group_id']?.toString() ?? '',
      'group_name': e['groups']?['name']?.toString() ?? '알 수 없는 조',
      'church_id': e['groups']?['church_id']?.toString() ?? '',
      'department_id': e['groups']?['department_id']?.toString(), // [NEW] Added department_id
      'color_hex': e['groups']?['color_hex']?.toString() ?? '', // [NEW] 조 색상 추가
      'department_name': e['groups']?['departments']?['name']?.toString() ?? '부서 미정',
      'profile_mode': e['groups']?['departments']?['profile_mode']?.toString() ?? 'individual',
      'role_in_group': (e['role_in_group'] ?? 'member').toString(),
      'is_new_member_group': e['groups']?['is_new_member_group'] ?? false,
      'climbing_threshold': e['groups']?['climbing_threshold'],
    };
  }).toList();

  // [UNIQUE] 중복 데이터 제거 (group_id와 role_in_group의 조합이 동일한 경우 제거)
  final Set<String> seen = {};
  final groups = rawGroups.where((g) {
    final key = '${g['group_id']}_${g['role_in_group']}';
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();

  // [ROLE PRIORITY] 정렬 로직 추가: 관리자 > 조장 > 조원 순으로 정렬하여 대표 소속 결정 시 유리하게 함
  groups.sort((a, b) {
    final roleA = a['role_in_group'];
    final roleB = b['role_in_group'];
    
    int getPriority(String role) {
      if (role == 'admin') return 0;
      if (role == 'leader') return 1;
      return 2;
    }
    
    return getPriority(roleA).compareTo(getPriority(roleB));
  });

  return groups;
}

// Selected Week Provider (Current context for app — 기도소식 화면용)
final selectedWeekDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  // Snap to the most recent Sunday (or today if it's Sunday)
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7));
});

/// 기록(출석/기도) 화면 전용 주차 선택 상태.
/// 기도소식 화면의 날짜 변경이 기록 화면에 영향을 주지 않도록 분리.
final attendanceSelectedWeekProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7));
});

// [NEW] Attendance Screen Action Trigger Provider
enum AttendanceAction { share, addMember }
final attendanceActionProvider = StateProvider<AttendanceAction?>((ref) => null);

/// 대시보드에서 등록/수정 버튼을 통해 진입했을 때 출석체크 팝업을 즉시 띄우기 위한 트리거.
final shouldAutoOpenAttendanceCheckProvider = StateProvider<bool>((ref) => false);

/// 사용자가 텍스트 입력 중인지 추적하는 전역 가드.
/// true일 때 백그라운드 resume 시 data provider invalidation을 건너뜁니다.
final isUserEditingProvider = StateProvider<bool>((ref) => false);

// Week ID Provider (Computed from selected date)
final weekIdProvider = FutureProvider.family<String?, String>((ref, String churchId) async {
  final date = ref.watch(selectedWeekDateProvider);
  final groupsAsync = ref.watch(userGroupsProvider);
  final groups = groupsAsync.value ?? [];
  
  // 현재 교회의 조장이나 관리자인지 확인
  final isAuthorized = groups.any((g) => 
    g['church_id'] == churchId && 
    (g['role_in_group'] == 'leader' || g['role_in_group'] == 'admin')
  );

  return ref.watch(repositoryProvider).getOrCreateWeek(churchId, date, createIfMissing: isAuthorized);
});

// Departments Provider
final departmentsProvider = FutureProvider.family<List<DepartmentModel>, String>((ref, churchId) async {
  return ref.watch(repositoryProvider).getDepartments(churchId);
});

// All groups in a specific department
final departmentGroupsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, departmentId) async {
  return ref.watch(repositoryProvider).getGroupsInDepartment(departmentId);
});

// Weekly Data for Department (for "All" tab)
final departmentWeeklyDataProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, paramString) async {
  final parts = paramString.split(':');
  if (parts.length < 2) return {'groups': [], 'prayers': []};
  
  final String departmentId = parts[0];
  final String churchId = parts[1];
  
  final weekId = await ref.watch(weekIdProvider(churchId).future);
  if (weekId == null) return {'groups': [], 'prayers': []};
  return ref.watch(repositoryProvider).getDepartmentWeeklyData(departmentId, weekId);
});

// Group Members Provider
final groupMembersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, groupId) async {
  return ref.watch(repositoryProvider).getGroupMembers(groupId);
});

// [NEW] Member Climbing Progress Provider (Params: "directoryMemberId:groupId")
// [FIX] Member Climbing Progress Provider (Real-time Stream)
// Params: "directoryMemberId:groupId"
final memberClimbingProgressProvider = StreamProvider.family<int, String>((ref, params) {
  final parts = params.split(':');
  if (parts.length < 2) return Stream.value(0);
  final String directoryMemberId = parts[0];
  final String groupId = parts[1];
  
  return Supabase.instance.client
      .from('attendance')
      .stream(primaryKey: ['id'])
      .handleError((e) {
        debugPrint('memberClimbingProgressProvider stream error: $e');
        // Swallow error to prevent UI crash
      })
      .map((data) {
        return data.where((a) => 
          a['directory_member_id'] == directoryMemberId && 
          a['group_id'] == groupId &&
          a['status'] == 'present'
        ).length;
      });
});

// Weekly Data Provider (Attendance + Prayers)
// Params: "groupId:churchId" or "groupId:churchId:weekId"
final weeklyDataProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, String paramString) async {
  final parts = paramString.split(':');
  if (parts.length < 2) return {'attendance': [], 'prayers': []};
  
  final String groupId = parts[0];
  final String churchId = parts[1];
  
  String? weekId;
  if (parts.length >= 3) {
    weekId = parts[2];
  } else {
    // weekId가 없는 경우 (예: 출석체크 화면 진입 시) 현재 주차 사용
    weekId = await ref.watch(weekIdProvider(churchId).future);
  }

  if (weekId == null) return {'attendance': [], 'prayers': []};
  return ref.watch(repositoryProvider).getWeeklyData(groupId, weekId);
});
// Attendance History Provider for Dashboard (Params: "groupId:year:month")
final attendanceHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, paramString) async {
  final parts = paramString.split(':');
  final groupId = parts[0];
  
  if (parts.length >= 3) {
    final year = int.tryParse(parts[1]);
    final month = int.tryParse(parts[2]);
    return ref.watch(repositoryProvider).getGroupAttendanceHistory(groupId, year: year, month: month);
  }
  
  return ref.watch(repositoryProvider).getGroupAttendanceHistory(groupId);
});

// [NEW] Department Attendance History Provider (Params: "departmentId:year:month")
final departmentAttendanceHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, paramString) async {
  final parts = paramString.split(':');
  final departmentId = parts[0];
  
  if (parts.length >= 3) {
    final year = int.tryParse(parts[1]);
    final month = int.tryParse(parts[2]);
    return ref.watch(repositoryProvider).getDepartmentAttendanceHistory(departmentId, year: year, month: month);
  }

  return ref.watch(repositoryProvider).getDepartmentAttendanceHistory(departmentId);
});

// [NEW] Department Attendance Details (Members + Status)
// Param: "departmentId:weekId"
final departmentWeeklyAttendanceProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, paramString) async {
  final parts = paramString.split(':');
  if (parts.length < 2) return {'groups': []};
  
  final String departmentId = parts[0];
  final String weekId = parts[1];
  
  return ref.watch(repositoryProvider).getDepartmentWeeklyAttendanceDetails(departmentId, weekId);
});

// Prayer Interactions Provider
final prayerInteractionsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, profileId) async {
  return ref.watch(repositoryProvider).getPrayerInteractions(profileId);
});

// Saved Prayers with Data Provider
final savedPrayersProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, profileId) async {
  return ref.watch(repositoryProvider).getSavedPrayers(profileId);
});

// Member's Prayer History (Timeline) Provider
final memberPrayerHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, directoryMemberId) async {
  return ref.watch(repositoryProvider).getMemberPrayerHistory(directoryMemberId);
});

// Real-time Unread Inquiry Count Provider
final unreadInquiryCountProvider = StreamProvider<int>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value(0);

  return Supabase.instance.client
      .from('inquiries')
      .stream(primaryKey: ['id'])
      .handleError((e) {
        debugPrint('unreadInquiryCountProvider stream error: $e');
        // Swallow error
      })
      .map((data) {
        // Filter by user_id and unread status in memory
        return data.where((inq) => 
          inq['user_id'] == user.id && 
          inq['is_user_unread'] == true
        ).length;
      });
});

// All Notices Provider (Cached & Stable)
// All Notices Provider (Real-time with Joins)
final allNoticesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value([]);

  final controller = StreamController<List<Map<String, dynamic>>>();

  // Fetch Logic
  Future<void> fetchNotices() async {
    try {
      final response = await Supabase.instance.client
          .from('notices')
          .select('*, profiles!created_by(full_name), departments(name)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);
      
      if (!controller.isClosed) {
        controller.add(List<Map<String, dynamic>>.from(response));
      }
    } catch (e) {
      debugPrint('Error fetching notices: $e');
    }
  }

  // Initial Fetch
  fetchNotices();

  // Listen to table changes
  final subscription = Supabase.instance.client
      .from('notices')
      .stream(primaryKey: ['id'])
      .listen(
        (_) => fetchNotices(),
        onError: (e) => debugPrint('allNoticesProvider: stream error: $e'),
      );

  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});

// User's read notice IDs (Real-time)
final userReadNoticeIdsProvider = StreamProvider<Set<String>>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value({});

  return Supabase.instance.client
      .from('notice_reads')
      .stream(primaryKey: ['notice_id', 'user_id'])
      .map((data) {
        return data
            .where((row) => row['user_id'] == user.id)
            .map((row) => row['notice_id'].toString())
            .toSet();
      })
      .handleError((e) {
        debugPrint('userReadNoticeIdsProvider error: $e');
        return <String>{};
      });
});

// New Notices Provider
final hasNewNoticesProvider = StreamProvider<bool>((ref) {
  // Rebuild on auth changes
  ref.watch(authStateProvider);

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value(false);
  
  // Watch read IDs
  final readIdsAsync = ref.watch(userReadNoticeIdsProvider);
  
  return readIdsAsync.when(
    data: (readIds) {
      return Supabase.instance.client
          .from('notices')
          .stream(primaryKey: ['id'])
          .handleError((e) {
            debugPrint('hasNewNoticesProvider stream error: $e');
            // Swallow error
          })
          .map((data) {
            if (data.isEmpty) return false;
            // Any notice that isn't in the read set?
            return data.any((notice) => !readIds.contains(notice['id']));
          });
    },
    loading: () => Stream.value(false),
    error: (e, _) => Stream.value(false),
  );
});

/// 현재 사용자의 FCM 토큰 등록 여부 — 웹 알림 유도 배너 표시 조건
/// true = 토큰 있음(배너 숨김), false = 토큰 없음(배너 표시)
final hasFcmTokenProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!kIsWeb) return true;
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return true;
  final data = await Supabase.instance.client
      .from('fcm_tokens')
      .select('token')
      .eq('user_id', user.id)
      .limit(1);
  return (data as List).isNotEmpty;
});

// 특정 주차의 모임없는 날 조회
// key 형식: "$departmentId:YYYY-MM-DD" (YYYY-MM-DD는 해당 주 일요일)
final noMeetingDayProvider = FutureProvider.family<NoMeetingDayModel?, String>((ref, key) async {
  final colonIdx = key.indexOf(':');
  if (colonIdx <= 0) return null;
  final departmentId = key.substring(0, colonIdx);
  final weekDate = DateTime.parse(key.substring(colonIdx + 1));
  return ref.read(repositoryProvider).getNoMeetingDay(departmentId, weekDate);
});

// 특정 월의 모임없는 날 목록 조회 (대시보드용)
// key 형식: "$departmentId:$year:$month"
final noMeetingDaysInMonthProvider = FutureProvider.family<List<NoMeetingDayModel>, String>((ref, key) async {
  final parts = key.split(':');
  if (parts.length < 3 || parts[0].isEmpty) return [];
  final departmentId = parts[0];
  final year = int.parse(parts[1]);
  final month = int.parse(parts[2]);
  return ref.read(repositoryProvider).getNoMeetingDaysInMonth(departmentId, year, month);
});

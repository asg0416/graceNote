import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole {
  admin('관리자'),
  leader('조장'),
  member('일반 회원');

  final String label;
  const AppRole(this.label);
}

/// 사용자가 가질 수 있는 모든 역할 리스트를 분석하는 프로바이더
final availableRolesProvider = Provider<List<AppRole>>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final groups = ref.watch(userGroupsProvider).value ?? [];

  final List<AppRole> roles = [];

  // 1. 관리자 권한 확인 (사용자 프로필 기준)
  final isAdmin = profile?.role == 'admin' || profile?.isMaster == true;
  if (isAdmin) {
    roles.add(AppRole.admin);
  }

  // 2. 조장 권한 확인 (소속 그룹 중 하나라도 leader/admin 역할인 경우)
  final hasLeaderRole = groups.any((g) => g['role_in_group'] == 'leader' || g['role_in_group'] == 'admin');
  if (hasLeaderRole) {
    roles.add(AppRole.leader);
  }

  // 3. 일반 회원 권한
  // [LOGIC UPGRADE] group_members 테이블뿐만 아니라, member_directory에 조가 편성된 경우도 member 역할을 부여함
  // 이는 관리자 페이지에서 개별 조 편성만 하고 공식 조원 등록을 안 했을 때도 앱 작동을 보장하기 위함
  final hasMemberRole = groups.any((g) => g['role_in_group'] == 'member' || g['group_id'] == 'directory_only');
  if (hasMemberRole) {
    roles.add(AppRole.member);
  }

  return roles;
});

/// 현재 활성화된 역할을 관리하는 프로바이더
final activeRoleProvider = StateNotifierProvider<ActiveRoleNotifier, AppRole?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final availableRoles = ref.watch(availableRolesProvider);
  return ActiveRoleNotifier(ref, prefs, availableRoles);
});

class ActiveRoleNotifier extends StateNotifier<AppRole?> {
  final Ref ref;
  final SharedPreferences prefs;
  final List<AppRole> availableRoles;
  static const String _roleKey = 'active_app_role';

  ActiveRoleNotifier(this.ref, this.prefs, this.availableRoles) : super(null) {
    _initRole();
  }

  void _initRole() {
    // 1. 저장된 역할이 있는지 확인
    final savedRoleName = prefs.getString(_roleKey);
    if (savedRoleName != null) {
      try {
        final savedRole = AppRole.values.firstWhere((r) => r.name == savedRoleName);
        
        // 저장된 역할이 현재 가능한 역할인지 검증
        if (availableRoles.contains(savedRole)) {
          state = savedRole;
          return;
        }
      } catch (_) {}
    }

    // 2. 저장된 게 없거나 유효하지 않으면 기본 순위 적용
    _setDefaultRole();
  }

  void _setDefaultRole() {
    if (availableRoles.isEmpty) return;

    // 조장 권한이 있다면 조장 우선, 그 다음 관리자, 그 다음 회원
    if (availableRoles.contains(AppRole.leader)) {
      state = AppRole.leader;
    } else if (availableRoles.contains(AppRole.admin)) {
      state = AppRole.admin;
    } else {
      state = AppRole.member;
    }
  }

  Future<void> setRole(AppRole role) async {
    state = role;
    await prefs.setString(_roleKey, role.name);
  }

  void reset() {
    prefs.remove(_roleKey);
    _setDefaultRole();
  }
}

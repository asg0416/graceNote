import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppRole {
  admin('관리자'),
  leader('조장'),
  member('일반 회원');

  final String label;
  const AppRole(this.label);
}

/// 사용자가 소속된 모든 그룹과 역할 정보를 분석하는 프로바이더
final availableMembershipsProvider = Provider<List<UserMembership>>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final groups = ref.watch(userGroupsProvider).value ?? [];

  final List<UserMembership> memberships = [];

  // 1. 개별 그룹 소속 정보 추가
  for (final g in groups) {
    memberships.add(UserMembership.fromMap(g));
  }

  // 2. 전체 관리자 권한 (별도 항목으로 추가)
  final isGlobalAdmin = profile?.role == 'admin' || profile?.isMaster == true;
  if (isGlobalAdmin) {
    memberships.add(UserMembership(
      groupId: 'global_admin',
      groupName: '전체',
      roleInGroup: 'admin',
    ));
  }

  return memberships;
});

/// 호환성을 위해 유지: 현재 가능한 역할 종류만 반환
final availableRolesProvider = Provider<List<AppRole>>((ref) {
  final memberships = ref.watch(availableMembershipsProvider);
  final Set<AppRole> roles = {};

  for (final m in memberships) {
    if (m.roleInGroup == 'admin') roles.add(AppRole.admin);
    if (m.roleInGroup == 'leader') roles.add(AppRole.leader);
    if (m.roleInGroup == 'member') roles.add(AppRole.member);
  }

  return roles.toList()
    ..sort((a, b) => AppRole.values.indexOf(a).compareTo(AppRole.values.indexOf(b)));
});

/// 현재 활성화된 소속(그룹+역할) 정보를 관리하는 프로바이더
final activeMembershipProvider = StateNotifierProvider<ActiveMembershipNotifier, UserMembership?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final memberships = ref.watch(availableMembershipsProvider);
  return ActiveMembershipNotifier(ref, prefs, memberships);
});

class ActiveMembershipNotifier extends StateNotifier<UserMembership?> {
  final Ref ref;
  final SharedPreferences prefs;
  final List<UserMembership> availableMemberships;
  static const String _membershipGroupKey = 'active_membership_group_id';
  static const String _membershipRoleKey = 'active_membership_role';

  ActiveMembershipNotifier(this.ref, this.prefs, this.availableMemberships) : super(null) {
    _initMembership();
  }

  void _initMembership() {
    final savedGroupId = prefs.getString(_membershipGroupKey);
    final savedRole = prefs.getString(_membershipRoleKey);

    if (savedGroupId != null && savedRole != null) {
      try {
        final savedMembership = availableMemberships.firstWhere(
          (m) => m.groupId == savedGroupId && m.roleInGroup == savedRole
        );
        state = savedMembership;
        return;
      } catch (_) {}
    }

    _setDefaultMembership();
  }

  void _setDefaultMembership() {
    if (availableMemberships.isEmpty) {
      state = null;
      return;
    }

    // 우선순위: 관리자 > 조장 > 조원
    final sorted = List<UserMembership>.from(availableMemberships);
    sorted.sort((a, b) {
      int getPriority(String role) {
        if (role == 'admin') return 0;
        if (role == 'leader') return 1;
        return 2;
      }
      return getPriority(a.roleInGroup).compareTo(getPriority(b.roleInGroup));
    });

    state = sorted.first;
  }

  Future<void> setMembership(UserMembership membership) async {
    state = membership;
    await prefs.setString(_membershipGroupKey, membership.groupId);
    await prefs.setString(_membershipRoleKey, membership.roleInGroup);
  }

  void reset() {
    prefs.remove(_membershipGroupKey);
    prefs.remove(_membershipRoleKey);
    _setDefaultMembership();
  }
}

/// 현재 활성화된 역할을 관리하는 프로바이더 (activeMembershipProvider에 의존하도록 변경)
final activeRoleProvider = Provider<AppRole?>((ref) {
  final activeMembership = ref.watch(activeMembershipProvider);
  if (activeMembership == null) return null;
  
  switch (activeMembership.roleInGroup) {
    case 'admin': return AppRole.admin;
    case 'leader': return AppRole.leader;
    default: return AppRole.member;
  }
});

import 'package:supabase_flutter/supabase_flutter.dart';
import '../error/exceptions.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/utils/attendance_summary.dart';
import 'package:grace_note/core/utils/group_record_submission_status.dart';
import 'package:grace_note/core/utils/prayer_entry_draft_state.dart';
import 'package:grace_note/core/utils/record_completion_status.dart';
import 'package:flutter/foundation.dart';

class _SeasonPlanMembersResult {
  final bool applies;
  final List<Map<String, dynamic>> members;

  const _SeasonPlanMembersResult._({
    required this.applies,
    required this.members,
  });

  const _SeasonPlanMembersResult.notApplicable()
      : this._(applies: false, members: const []);

  const _SeasonPlanMembersResult.applied(List<Map<String, dynamic>> members)
      : this._(applies: true, members: members);
}

class _SeasonPlanGroupsResult {
  final bool applies;
  final List<Map<String, dynamic>> groups;

  const _SeasonPlanGroupsResult._({
    required this.applies,
    required this.groups,
  });

  const _SeasonPlanGroupsResult.notApplicable()
      : this._(applies: false, groups: const []);

  const _SeasonPlanGroupsResult.applied(List<Map<String, dynamic>> groups)
      : this._(applies: true, groups: groups);
}

class GraceNoteRepository {
  final _supabase = Supabase.instance.client;

  Future<DateTime?> _getWeekDate(String weekId) async {
    try {
      final week = await _supabase
          .from('weeks')
          .select('week_date')
          .eq('id', weekId)
          .maybeSingle();
      final rawDate = week?['week_date']?.toString();
      if (rawDate == null || rawDate.isEmpty) return null;
      return DateTime.tryParse(rawDate);
    } catch (e) {
      debugPrint('GraceNoteRepository: Failed to fetch week date: $e');
      return null;
    }
  }

  bool _groupWasInUseOnWeek(
    Map<String, dynamic> group,
    DateTime? weekDate,
  ) {
    if (weekDate == null) return group['is_active'] == true;

    final weekStart = DateTime(weekDate.year, weekDate.month, weekDate.day);
    final weekEnd = weekStart.add(const Duration(days: 1));

    // [FIX] UTC timestamp → 로컬 변환 후 비교
    DateTime? parseLocalDate(dynamic value) {
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      return parsed?.toLocal();
    }

    final activeFrom = parseLocalDate(group['active_from']) ??
        parseLocalDate(group['created_at']);
    final endedAt = parseLocalDate(group['ended_at']);

    if (activeFrom != null && !activeFrom.isBefore(weekEnd)) return false;
    if (endedAt != null && endedAt.isBefore(weekStart)) return false;
    return true;
  }

  bool _membershipWasInUseOnWeek(
    Map<String, dynamic> membership,
    DateTime? weekDate,
  ) {
    if (weekDate == null) return membership['status'] == 'active';

    final weekStart = DateTime(weekDate.year, weekDate.month, weekDate.day);
    final weekEnd = weekStart.add(const Duration(days: 1));
    final group = membership['groups'] is Map<String, dynamic>
        ? membership['groups'] as Map<String, dynamic>
        : <String, dynamic>{};

    // [FIX] UTC timestamp를 로컬 DateTime으로 변환 후 비교해야 함.
    // Dart에서 DateTime.tryParse("2026-06-13T23:59:59+00:00")는 isUtc=true를 반환하고
    // DateTime(year, month, day)는 isUtc=false(로컬)라 섞어 비교하면 잘못된 결과가 나옴.
    DateTime? parseLocalDate(dynamic value) {
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      return parsed?.toLocal();
    }

    final startsAt = parseLocalDate(membership['starts_at']) ??
        parseLocalDate(group['active_from']);
    final endsAt = parseLocalDate(membership['ends_at']);
    final groupActiveFrom = parseLocalDate(group['active_from']);
    final groupEndedAt = parseLocalDate(group['ended_at']);

    if (startsAt != null && !startsAt.isBefore(weekEnd)) return false;
    if (groupActiveFrom != null && !groupActiveFrom.isBefore(weekEnd)) {
      return false;
    }
    if (endsAt != null && endsAt.isBefore(weekStart)) return false;
    if (groupEndedAt != null && groupEndedAt.isBefore(weekStart)) return false;
    return true;
  }

  List<Map<String, dynamic>> _groupsForWeekWithLastKnownFallback(
    List<Map<String, dynamic>> allGroups,
    DateTime? weekDate, {
    Set<String> recordGroupIds = const {},
  }) {
    final groupsForWeek = allGroups
        .where((group) =>
            _groupWasInUseOnWeek(group, weekDate) ||
            recordGroupIds.contains(group['id']?.toString()))
        .toList();

    if (groupsForWeek.isNotEmpty || weekDate == null) return groupsForWeek;

    final weekEnd = DateTime(weekDate.year, weekDate.month, weekDate.day)
        .add(const Duration(days: 1));
    DateTime? latestKnownBoundary;

    for (final group in allGroups) {
      final activeFrom =
          DateTime.tryParse(group['active_from']?.toString() ?? '') ??
              DateTime.tryParse(group['created_at']?.toString() ?? '');
      if (activeFrom != null && !activeFrom.isBefore(weekEnd)) continue;

      final endedAt = DateTime.tryParse(group['ended_at']?.toString() ?? '');
      final boundary = endedAt ?? activeFrom;
      if (boundary == null) continue;

      if (latestKnownBoundary == null ||
          boundary.isAfter(latestKnownBoundary)) {
        latestKnownBoundary = boundary;
      }
    }

    if (latestKnownBoundary == null) return groupsForWeek;

    return allGroups.where((group) {
      final activeFrom =
          DateTime.tryParse(group['active_from']?.toString() ?? '') ??
              DateTime.tryParse(group['created_at']?.toString() ?? '');
      if (activeFrom != null && !activeFrom.isBefore(weekEnd)) return false;

      final endedAt = DateTime.tryParse(group['ended_at']?.toString() ?? '');
      final boundary = endedAt ?? activeFrom;
      return boundary != null &&
          boundary.year == latestKnownBoundary!.year &&
          boundary.month == latestKnownBoundary.month &&
          boundary.day == latestKnownBoundary.day;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _overlayCurrentSeasonGroupPeriods(
    String departmentId,
    DateTime? weekDate,
    List<Map<String, dynamic>> allGroups,
  ) async {
    if (weekDate == null || departmentId.isEmpty || allGroups.isEmpty) {
      return allGroups;
    }

    try {
      final weekText = _snapToSundayStr(weekDate);

      final seasons = await _supabase
          .from('regrouping_seasons')
          .select('id')
          .eq('department_id', departmentId)
          .eq('status', 'applied')
          .lte('effective_week_date', weekText)
          .or('end_week_date.is.null,end_week_date.gte.$weekText')
          .order('effective_week_date', ascending: false)
          .limit(1);

      final seasonRows = List<Map<String, dynamic>>.from(seasons);
      if (seasonRows.isEmpty) return allGroups;

      final seasonId = seasonRows.first['id']?.toString();
      if (seasonId == null || seasonId.isEmpty) return allGroups;

      final planRows = await _supabase
          .from('regrouping_plan_groups')
          .select(
              'source_group_id, name, starts_week_date, ends_week_date, plan_status')
          .eq('season_id', seasonId);

      final planBySourceGroupId = {
        for (final row in List<Map<String, dynamic>>.from(planRows))
          if (row['source_group_id'] != null)
            row['source_group_id'].toString(): row,
      };
      final newPlanByName = {
        for (final row in List<Map<String, dynamic>>.from(planRows))
          if (row['source_group_id'] == null && row['name'] != null)
            row['name'].toString(): row,
      };

      if (planBySourceGroupId.isEmpty && newPlanByName.isEmpty) {
        return allGroups;
      }

      return allGroups.map((group) {
        final groupId = group['id']?.toString();
        final groupName = group['name']?.toString();
        final plan = groupId == null
            ? null
            : planBySourceGroupId[groupId] ??
                (groupName == null ? null : newPlanByName[groupName]);
        if (plan == null) return group;

        return {
          ...group,
          'active_from':
              plan['starts_week_date']?.toString() ?? group['active_from'],
          'ended_at': plan['ends_week_date']?.toString() ?? group['ended_at'],
          // Historical week filtering below uses active_from/ended_at. Keep
          // is_active as a current-state hint only so ended groups still appear
          // on weeks inside their corrected period.
          'is_active':
              plan['plan_status'] == 'ended' ? false : group['is_active'],
        };
      }).toList();
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: Failed to overlay season group periods: $e');
      return allGroups;
    }
  }

  Future<_SeasonPlanGroupsResult> _getSeasonPlanGroupsForWeek(
    String departmentId,
    DateTime? weekDate,
    List<Map<String, dynamic>> allGroups, {
    Set<String> recordGroupIds = const {},
  }) async {
    if (weekDate == null || departmentId.isEmpty) {
      return const _SeasonPlanGroupsResult.notApplicable();
    }

    try {
      final weekText = _snapToSundayStr(weekDate);
      final snappedWeekDate = DateTime.parse(weekText);

      final seasons = await _supabase
          .from('regrouping_seasons')
          .select('id')
          .eq('department_id', departmentId)
          .eq('status', 'applied')
          .lte('effective_week_date', weekText)
          .or('end_week_date.is.null,end_week_date.gte.$weekText')
          .order('effective_week_date', ascending: false)
          .limit(1);

      final seasonRows = List<Map<String, dynamic>>.from(seasons);
      if (seasonRows.isEmpty) {
        return const _SeasonPlanGroupsResult.notApplicable();
      }

      final seasonId = seasonRows.first['id']?.toString();
      if (seasonId == null || seasonId.isEmpty) {
        return const _SeasonPlanGroupsResult.notApplicable();
      }

      final planRowsResponse = await _supabase
          .from('regrouping_plan_groups')
          .select(
              'id, source_group_id, name, color_hex, is_new_member_group, climbing_threshold, starts_week_date, ends_week_date, plan_status, sort_order')
          .eq('season_id', seasonId)
          .order('sort_order')
          .order('name');

      final liveGroupById = {
        for (final group in allGroups)
          if (group['id'] != null) group['id'].toString(): group,
      };
      final planGroups = <Map<String, dynamic>>[];
      final includedGroupIds = <String>{};

      for (final row in List<Map<String, dynamic>>.from(planRowsResponse)) {
        final sourceGroupId = row['source_group_id']?.toString();
        if (sourceGroupId == null || sourceGroupId.isEmpty) {
          // 앱 출석/기도 기록은 아직 실제 groups.id를 기준으로 저장된다.
          // 적용 시즌에 source_group_id가 없는 조는 live 반영 전 초안 성격이므로
          // 앱의 주차별 조 목록에는 포함하지 않는다.
          continue;
        }

        final planGroupForWeek = _membershipWasInUseOnWeek({
          'starts_at': row['starts_week_date'],
          'ends_at': row['ends_week_date'],
          'groups': {
            'active_from': row['starts_week_date'],
            'ended_at': row['ends_week_date'],
          },
        }, snappedWeekDate);

        if (!planGroupForWeek && !recordGroupIds.contains(sourceGroupId)) {
          continue;
        }

        final liveGroup = liveGroupById[sourceGroupId] ?? <String, dynamic>{};
        includedGroupIds.add(sourceGroupId);
        planGroups.add({
          ...liveGroup,
          'id': sourceGroupId,
          'name': row['name'] ?? liveGroup['name'],
          'color_hex': row['color_hex'] ?? liveGroup['color_hex'],
          'is_new_member_group':
              row['is_new_member_group'] ?? liveGroup['is_new_member_group'],
          'climbing_threshold':
              row['climbing_threshold'] ?? liveGroup['climbing_threshold'],
          'is_active': row['plan_status'] == 'ended' ? false : true,
          'active_from': row['starts_week_date'] ?? liveGroup['active_from'],
          'ended_at': row['ends_week_date'] ?? liveGroup['ended_at'],
          'season_plan_group_id': row['id'],
          'season_plan_source': 'regrouping_plan_groups',
        });
      }

      for (final recordGroupId in recordGroupIds) {
        if (includedGroupIds.contains(recordGroupId)) continue;
        final recordGroup = liveGroupById[recordGroupId];
        if (recordGroup != null) {
          planGroups.add(recordGroup);
        }
      }

      return _SeasonPlanGroupsResult.applied(planGroups);
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: season plan group list read failed, using live groups fallback: $e');
      return const _SeasonPlanGroupsResult.notApplicable();
    }
  }

  Future<Set<String>?> _getSeasonPlanTargetPersonKeysForWeek(
    String departmentId,
    DateTime? weekDate,
  ) async {
    if (weekDate == null || departmentId.isEmpty) return null;

    try {
      final weekText = _snapToSundayStr(weekDate);
      final snappedWeekDate = DateTime.parse(weekText);

      final seasons = await _supabase
          .from('regrouping_seasons')
          .select('id')
          .eq('department_id', departmentId)
          .eq('status', 'applied')
          .lte('effective_week_date', weekText)
          .or('end_week_date.is.null,end_week_date.gte.$weekText')
          .order('effective_week_date', ascending: false)
          .limit(1);

      final seasonRows = List<Map<String, dynamic>>.from(seasons);
      if (seasonRows.isEmpty) return null;

      final seasonId = seasonRows.first['id']?.toString();
      if (seasonId == null || seasonId.isEmpty) return null;

      final planGroupsResponse = await _supabase
          .from('regrouping_plan_groups')
          .select('id, starts_week_date, ends_week_date, plan_status')
          .eq('season_id', seasonId);

      final activePlanGroupIds = List<Map<String, dynamic>>.from(
        planGroupsResponse,
      )
          .where((row) => _membershipWasInUseOnWeek({
                'starts_at': row['starts_week_date'],
                'ends_at': row['ends_week_date'],
                'groups': {
                  'active_from': row['starts_week_date'],
                  'ended_at': row['ends_week_date'],
                },
              }, snappedWeekDate))
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      if (activePlanGroupIds.isEmpty) return <String>{};

      final assignmentsResponse = await _supabase
          .from('regrouping_plan_assignments')
          .select(
              'person_id, source_member_directory_id, starts_week_date, ends_week_date, plan_group_id')
          .eq('season_id', seasonId)
          .inFilter('plan_group_id', activePlanGroupIds);

      final keys = <String>{};
      for (final assignment
          in List<Map<String, dynamic>>.from(assignmentsResponse)) {
        final activeOnWeek = _membershipWasInUseOnWeek({
          'starts_at': assignment['starts_week_date'],
          'ends_at': assignment['ends_week_date'],
          'groups': {
            'active_from': weekText,
            'ended_at': null,
          },
        }, snappedWeekDate);
        if (!activeOnWeek) continue;

        final key = attendancePersonKey({
          'person_id': assignment['person_id'],
          'id': assignment['source_member_directory_id'],
        });
        if (key != null) keys.add(key);
      }

      return keys;
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: season plan target summary failed, using legacy fallback: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getRegroupingSeasonForWeek(
    String departmentId,
    DateTime weekDate,
  ) async {
    if (departmentId.isEmpty) return null;

    try {
      final weekText = _snapToSundayStr(weekDate);
      final seasons = await _supabase
          .from('regrouping_seasons')
          .select('id, title, effective_week_date, end_week_date, status')
          .eq('department_id', departmentId)
          .eq('status', 'applied')
          .lte('effective_week_date', weekText)
          .or('end_week_date.is.null,end_week_date.gte.$weekText')
          .order('effective_week_date', ascending: false)
          .limit(1);

      final rows = List<Map<String, dynamic>>.from(seasons);
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('GraceNoteRepository: Failed to read regrouping season: $e');
      return null;
    }
  }

  Future<Set<String>> _getRelatedDirectoryIdsByPhase2Person(
      String directoryMemberId) async {
    try {
      final profile = await _supabase
          .from('member_profiles')
          .select('person_id')
          .eq('member_directory_id', directoryMemberId)
          .maybeSingle();

      final personId = profile?['person_id']?.toString();
      if (personId == null || personId.isEmpty) return {directoryMemberId};

      final profiles = await _supabase
          .from('member_profiles')
          .select('member_directory_id')
          .eq('person_id', personId)
          .not('member_directory_id', 'is', null);

      final ids = List<Map<String, dynamic>>.from(profiles)
          .map((row) => row['member_directory_id']?.toString())
          .whereType<String>()
          .toSet();

      ids.add(directoryMemberId);
      return ids;
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: Phase 2 related directory lookup failed: $e');
      return {directoryMemberId};
    }
  }

  Future<List<Map<String, dynamic>>> _enrichPrayerRowsWithPhase2MemberInfo(
      List<Map<String, dynamic>> rows) async {
    final directoryIds = rows
        .map((row) => row['directory_member_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    final recordedGroupIds = rows
        .map((row) =>
            row['recorded_group_id']?.toString() ?? row['group_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    if (directoryIds.isEmpty && recordedGroupIds.isEmpty) return rows;

    try {
      final Map<String, Map<String, dynamic>> groupById = {};
      if (recordedGroupIds.isNotEmpty) {
        final groupsResponse = await _supabase
            .from('groups')
            .select('id, name, color_hex')
            .inFilter('id', recordedGroupIds);

        for (final group in List<Map<String, dynamic>>.from(groupsResponse)) {
          final id = group['id']?.toString();
          if (id != null) groupById[id] = group;
        }
      }

      final memberProfilesResponse = directoryIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await _supabase
              .from('member_profiles')
              .select(
                  'person_id, profile_id, member_directory_id, full_name, family_name')
              .inFilter('member_directory_id', directoryIds);

      final memberProfiles =
          List<Map<String, dynamic>>.from(memberProfilesResponse);
      final profileByDirectoryId = {
        for (final profile in memberProfiles)
          if (profile['member_directory_id'] != null)
            profile['member_directory_id'].toString(): profile
      };

      final personIds = memberProfiles
          .map((profile) => profile['person_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Map<String, Map<String, dynamic>> membershipByDirectoryId = {};
      if (personIds.isNotEmpty) {
        final membershipsResponse = await _supabase
            .from('memberships')
            .select(
                'person_id, legacy_member_directory_id, role, status, groups(name)')
            .inFilter('person_id', personIds)
            .not('legacy_member_directory_id', 'is', null);

        for (final membership
            in List<Map<String, dynamic>>.from(membershipsResponse)) {
          final directoryId =
              membership['legacy_member_directory_id']?.toString();
          if (directoryId == null) continue;
          final existing = membershipByDirectoryId[directoryId];
          if (existing == null || existing['status'] != 'active') {
            membershipByDirectoryId[directoryId] = membership;
          }
        }
      }

      return rows.map((row) {
        final directoryId = row['directory_member_id']?.toString();
        final recordedGroupId =
            row['recorded_group_id']?.toString() ?? row['group_id']?.toString();
        final recordedGroup =
            recordedGroupId == null ? null : groupById[recordedGroupId];

        if (directoryId == null) {
          return {
            ...row,
            if (recordedGroup?['name'] != null)
              'recorded_group_name': recordedGroup!['name'],
            if (recordedGroup?['color_hex'] != null)
              'recorded_group_color_hex': recordedGroup!['color_hex'],
          };
        }

        final profile = profileByDirectoryId[directoryId];
        final membership = membershipByDirectoryId[directoryId];
        if (profile == null && membership == null && recordedGroup == null) {
          return row;
        }

        final memberDirectory = Map<String, dynamic>.from(
            (row['member_directory'] as Map?) ??
                (row['member'] as Map?) ??
                <String, dynamic>{});

        final group = membership?['groups'];
        final enrichedMemberDirectory = {
          ...memberDirectory,
          'id': directoryId,
          if (profile?['person_id'] != null) 'person_id': profile!['person_id'],
          if (profile?['profile_id'] != null)
            'profile_id': profile!['profile_id'],
          if (profile?['full_name'] != null) 'full_name': profile!['full_name'],
          if (profile?['family_name'] != null)
            'family_name': profile!['family_name'],
          if (group is Map && group['name'] != null)
            'group_name': group['name'],
          if (recordedGroup?['name'] != null)
            'recorded_group_name': recordedGroup!['name'],
          if (recordedGroup?['color_hex'] != null)
            'recorded_group_color_hex': recordedGroup!['color_hex'],
          if (membership?['role'] != null) 'role_in_group': membership!['role'],
          if (membership?['status'] != null)
            'membership_status': membership!['status'],
          'phase2_member_source': 'member_profiles',
        };

        return {
          ...row,
          if (recordedGroup?['name'] != null)
            'recorded_group_name': recordedGroup!['name'],
          if (recordedGroup?['color_hex'] != null)
            'recorded_group_color_hex': recordedGroup!['color_hex'],
          'member_directory': enrichedMemberDirectory,
          // Some older app screens read the alias `member` instead of
          // `member_directory`; keep both display aliases in sync.
          'member': enrichedMemberDirectory,
        };
      }).toList();
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: Phase 2 prayer member enrichment failed: $e');
      return rows;
    }
  }

  // 특정 날짜의 Week ID 조회 또는 생성
  // 특정 날짜의 Week ID 조회 또는 생성
  Future<String?> getOrCreateWeek(String churchId, DateTime weekDate,
      {bool createIfMissing = true}) async {
    if (churchId.isEmpty) return null;
    // Snap to the preceding Sunday
    final sunday = weekDate.subtract(Duration(days: weekDate.weekday % 7));
    final dateStr = sunday.toIso8601String().split('T')[0];

    final existing = await _supabase
        .from('weeks')
        .select('id, is_active')
        .eq('church_id', churchId)
        .eq('week_date', dateStr)
        .maybeSingle();

    if (existing != null) {
      if (existing['is_active'] == false && createIfMissing) {
        await _supabase
            .from('weeks')
            .update({'is_active': true}).eq('id', existing['id']);
      }
      return existing['id'];
    }
    if (!createIfMissing) return null;

    try {
      // [FIX] RLS 권한 문제 해결을 위해 RPC 함수 사용 (Security Definer)
      final res = await _supabase.rpc('ensure_week_exists', params: {
        'p_church_id': churchId,
        'p_week_date': dateStr,
      });
      return res as String;
    } catch (e) {
      debugPrint('GraceNoteRepository: Error in getOrCreateWeek: $e');
      return null;
    }
  }

  // 특정 조원의 활성 Group Member ID 조회
  Future<String?> getActiveGroupMemberId(
      String groupId, String profileId) async {
    final res = await _supabase
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('profile_id', profileId)
        .eq('is_active', true)
        .maybeSingle();
    return res?['id'];
  }

  Future<Map<String, Map<String, dynamic>>>
      _resolvePhase3SnapshotsForDirectoryMembers({
    required Set<String> directoryMemberIds,
    required Set<String> groupIds,
  }) async {
    final result = <String, Map<String, dynamic>>{};
    final ids = directoryMemberIds.where((id) => id.isNotEmpty).toList();
    final groups = groupIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty || groups.isEmpty) return result;

    try {
      final membershipResponse = await _supabase
          .from('memberships')
          .select(
              'id, person_id, group_id, department_id, status, legacy_member_directory_id, updated_at')
          .inFilter('legacy_member_directory_id', ids)
          .inFilter('group_id', groups)
          .order('updated_at', ascending: false);

      final membershipRows =
          List<Map<String, dynamic>>.from(membershipResponse);
      for (final row in membershipRows) {
        final groupId = row['group_id']?.toString();
        final directoryId = row['legacy_member_directory_id']?.toString();
        if (groupId == null || directoryId == null) continue;

        final key = '$groupId:$directoryId';
        final existing = result[key];
        if (existing != null && existing['status'] == 'active') continue;
        if (existing != null && row['status'] != 'active') continue;

        result[key] = {
          'person_id': row['person_id'],
          'membership_id': row['id'],
          'recorded_group_id': row['group_id'] ?? groupId,
          if (row['department_id'] != null)
            'recorded_department_id': row['department_id'],
          'status': row['status'],
        };
      }

      final missingDirectoryIds = ids
          .where((directoryId) => !groups
              .any((groupId) => result.containsKey('$groupId:$directoryId')))
          .toList();
      if (missingDirectoryIds.isEmpty) return result;

      final memberProfileResponse = await _supabase
          .from('member_profiles')
          .select('member_directory_id, person_id')
          .inFilter('member_directory_id', missingDirectoryIds);
      final personByDirectoryId = {
        for (final row
            in List<Map<String, dynamic>>.from(memberProfileResponse))
          if (row['member_directory_id'] != null)
            row['member_directory_id'].toString(): row['person_id']
      };

      final groupResponse = await _supabase
          .from('groups')
          .select('id, department_id')
          .inFilter('id', groups);
      final departmentByGroupId = {
        for (final row in List<Map<String, dynamic>>.from(groupResponse))
          if (row['id'] != null) row['id'].toString(): row['department_id']
      };

      for (final directoryId in missingDirectoryIds) {
        for (final groupId in groups) {
          final key = '$groupId:$directoryId';
          result.putIfAbsent(
              key,
              () => {
                    if (personByDirectoryId[directoryId] != null)
                      'person_id': personByDirectoryId[directoryId],
                    'recorded_group_id': groupId,
                    if (departmentByGroupId[groupId] != null)
                      'recorded_department_id': departmentByGroupId[groupId],
                  });
        }
      }
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: Phase 3 bulk snapshot lookup failed: $e');
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _buildPhase3PrayerPayloads(
    List<PrayerEntryModel> prayerList, {
    Map<String, Map<String, dynamic>>? preloadedSnapshots,
  }) async {
    final payloads = <Map<String, dynamic>>[];
    final snapshots = preloadedSnapshots ??
        await _resolvePhase3SnapshotsForDirectoryMembers(
          directoryMemberIds:
              prayerList.map((prayer) => prayer.directoryMemberId).toSet(),
          groupIds: prayerList.map((prayer) => prayer.groupId).toSet(),
        );

    for (final prayer in prayerList) {
      final payload = prayer.toJson();
      final cacheKey = '${prayer.groupId}:${prayer.directoryMemberId}';
      final snapshot = snapshots[cacheKey];

      if (snapshot != null) {
        payload.addAll({
          if (payload['person_id'] == null && snapshot['person_id'] != null)
            'person_id': snapshot['person_id'],
          if (payload['membership_id'] == null &&
              snapshot['membership_id'] != null)
            'membership_id': snapshot['membership_id'],
          if (payload['recorded_group_id'] == null &&
              snapshot['recorded_group_id'] != null)
            'recorded_group_id': snapshot['recorded_group_id'],
          if (payload['recorded_department_id'] == null &&
              snapshot['recorded_department_id'] != null)
            'recorded_department_id': snapshot['recorded_department_id'],
        });
      }

      payloads.add(payload);
    }

    return payloads;
  }

  Future<List<Map<String, dynamic>>> _buildPhase3AttendancePayloads(
    List<AttendanceModel> attendanceList, {
    Map<String, Map<String, dynamic>>? preloadedSnapshots,
  }) async {
    final payloads = <Map<String, dynamic>>[];
    final attendanceWithGroup = attendanceList
        .where((attendance) =>
            attendance.groupId != null && attendance.groupId!.isNotEmpty)
        .toList();
    final snapshots = preloadedSnapshots ??
        await _resolvePhase3SnapshotsForDirectoryMembers(
          directoryMemberIds: attendanceWithGroup
              .map((attendance) => attendance.directoryMemberId)
              .toSet(),
          groupIds: attendanceWithGroup
              .map((attendance) => attendance.groupId!)
              .toSet(),
        );

    for (final attendance in attendanceList) {
      final payload = attendance.toJson();
      final groupId = attendance.groupId;

      if (groupId == null || groupId.isEmpty) {
        payloads.add(payload);
        continue;
      }

      final cacheKey = '$groupId:${attendance.directoryMemberId}';
      final snapshot = snapshots[cacheKey];

      if (snapshot != null) {
        payload.addAll({
          if (payload['person_id'] == null && snapshot['person_id'] != null)
            'person_id': snapshot['person_id'],
          if (payload['membership_id'] == null &&
              snapshot['membership_id'] != null)
            'membership_id': snapshot['membership_id'],
          if (payload['recorded_group_id'] == null &&
              snapshot['recorded_group_id'] != null)
            'recorded_group_id': snapshot['recorded_group_id'],
          if (payload['recorded_department_id'] == null &&
              snapshot['recorded_department_id'] != null)
            'recorded_department_id': snapshot['recorded_department_id'],
        });
      }

      payloads.add(payload);
    }

    return payloads;
  }

  Future<void> saveAttendanceAndPrayers({
    required List<AttendanceModel> attendanceList,
    required List<PrayerEntryModel> prayerList,
  }) async {
    final snapshotDirectoryIds = <String>{};
    final snapshotGroupIds = <String>{};

    for (final attendance in attendanceList) {
      final groupId = attendance.groupId;
      if (groupId == null || groupId.isEmpty) continue;
      snapshotDirectoryIds.add(attendance.directoryMemberId);
      snapshotGroupIds.add(groupId);
    }

    for (final prayer in prayerList) {
      if (prayer.groupId.isEmpty) continue;
      snapshotDirectoryIds.add(prayer.directoryMemberId);
      snapshotGroupIds.add(prayer.groupId);
    }

    final snapshots = await _resolvePhase3SnapshotsForDirectoryMembers(
      directoryMemberIds: snapshotDirectoryIds,
      groupIds: snapshotGroupIds,
    );

    // 1. Attendance Upsert (group-scoped for multi-membership weeks)
    if (attendanceList.isNotEmpty) {
      // 팁: attendanceList의 각 항목에는 저장 시점의 groupId가 이미 포함되어 있어야 함
      final attendancePayloads = await _buildPhase3AttendancePayloads(
        attendanceList,
        preloadedSnapshots: snapshots,
      );
      await _supabase.from('attendance').upsert(
            attendancePayloads,
            onConflict: 'week_id,directory_member_id,group_id',
          );
    }

    // 2. Prayer Entries Upsert (directory_member_id 기반)
    if (prayerList.isNotEmpty) {
      final prayerPayloads = await _buildPhase3PrayerPayloads(
        prayerList,
        preloadedSnapshots: snapshots,
      );
      final existingRowsByKey = <String, Map<String, dynamic>>{};
      final weekIds = prayerPayloads
          .map((payload) => payload['week_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final directoryMemberIds = prayerPayloads
          .map((payload) => payload['directory_member_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (weekIds.isNotEmpty && directoryMemberIds.isNotEmpty) {
        final existingRows = await _supabase
            .from('prayer_entries')
            .select('id, week_id, directory_member_id, status')
            .inFilter('week_id', weekIds)
            .inFilter('directory_member_id', directoryMemberIds);
        for (final row in List<Map<String, dynamic>>.from(existingRows)) {
          final key = '${row['week_id']}:${row['directory_member_id']}';
          existingRowsByKey[key] = row;
        }
      }

      final upsertPayloads = <Map<String, dynamic>>[];
      final draftUpdates = <Map<String, dynamic>>[];
      final draftClears = <String>[];
      final now = DateTime.now().toUtc().toIso8601String();

      for (final payload in prayerPayloads) {
        final key = '${payload['week_id']}:${payload['directory_member_id']}';
        final existing = existingRowsByKey[key];
        final requestedStatus = payload['status']?.toString() ?? 'draft';

        if (shouldWriteDraftBesidePublished(
          requestedStatus: requestedStatus,
          existingStatus: existing?['status']?.toString(),
        )) {
          draftUpdates.add({
            'id': existing!['id'],
            'draft_content': payload['content'],
            'draft_updated_at': now,
          });
          continue;
        }

        final nextPayload = Map<String, dynamic>.from(payload);
        if (requestedStatus == 'published') {
          nextPayload.remove('draft_content');
          nextPayload.remove('draft_updated_at');
          final existingId = existing?['id']?.toString();
          if (existingId != null && existingId.isNotEmpty) {
            draftClears.add(existingId);
          }
        }
        upsertPayloads.add(nextPayload);
      }

      if (upsertPayloads.isNotEmpty) {
        await _supabase.from('prayer_entries').upsert(
              upsertPayloads,
              onConflict: 'week_id,directory_member_id',
            );
      }

      for (final draftUpdate in draftUpdates) {
        final id = draftUpdate.remove('id');
        await _supabase.from('prayer_entries').update(draftUpdate).eq('id', id);
      }

      for (final id in draftClears) {
        try {
          await _supabase.from('prayer_entries').update({
            'draft_content': null,
            'draft_updated_at': null,
          }).eq('id', id);
        } catch (e) {
          debugPrint(
              'GraceNoteRepository: clearing pending prayer draft failed: $e');
        }
      }
    }
  }

  Future<void> markGroupWeekRecordSubmitted({
    required String churchId,
    required String departmentId,
    required String weekId,
    required String groupId,
    required String kind,
    String source = 'app',
  }) async {
    if (churchId.isEmpty ||
        departmentId.isEmpty ||
        weekId.isEmpty ||
        groupId.isEmpty) {
      return;
    }

    final submittedAt = DateTime.now().toUtc().toIso8601String();
    final userId = _supabase.auth.currentUser?.id;
    final payload = <String, dynamic>{
      'church_id': churchId,
      'department_id': departmentId,
      'week_id': weekId,
      'group_id': groupId,
    };

    if (kind == 'attendance') {
      payload.addAll({
        'attendance_submitted_at': submittedAt,
        'attendance_submitted_by': userId,
        'attendance_source': source,
        'attendance_submission_kind': 'records',
      });
    } else if (kind == 'prayer') {
      payload.addAll({
        'prayer_submitted_at': submittedAt,
        'prayer_submitted_by': userId,
        'prayer_source': source,
        'prayer_submission_kind': 'records',
      });
    } else {
      throw ArgumentError.value(kind, 'kind', 'Unsupported record kind');
    }

    await _supabase.from('group_week_record_submissions').upsert(
          payload,
          onConflict: 'week_id,group_id',
        );
  }

  Future<Map<String, dynamic>?> markNewMemberGroupNoMeeting({
    required String churchId,
    required String departmentId,
    required String weekId,
    required String groupId,
    String reason = '새가족 모임 없음',
  }) async {
    if (churchId.isEmpty ||
        departmentId.isEmpty ||
        weekId.isEmpty ||
        groupId.isEmpty) {
      return null;
    }

    final response = await _supabase.rpc(
      'mark_new_member_group_no_meeting',
      params: {
        'p_church_id': churchId,
        'p_department_id': departmentId,
        'p_week_id': weekId,
        'p_group_id': groupId,
        'p_reason': reason,
      },
    );

    final rows = response is List
        ? List<Map<String, dynamic>>.from(response)
        : <Map<String, dynamic>>[];
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> cancelNewMemberGroupNoMeeting({
    required String churchId,
    required String departmentId,
    required String weekId,
    required String groupId,
  }) async {
    if (churchId.isEmpty ||
        departmentId.isEmpty ||
        weekId.isEmpty ||
        groupId.isEmpty) {
      return null;
    }

    final response = await _supabase.rpc(
      'cancel_new_member_group_no_meeting',
      params: {
        'p_church_id': churchId,
        'p_department_id': departmentId,
        'p_week_id': weekId,
        'p_group_id': groupId,
      },
    );

    final rows = response is List
        ? List<Map<String, dynamic>>.from(response)
        : <Map<String, dynamic>>[];
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> getWeeklyData(
    String groupId,
    String weekId, {
    bool includeDrafts = false,
    List<Map<String, dynamic>>? preloadedMembers,
  }) async {
    // 1. 조원 명단 정보 먼저 확보
    final weekDate = await _getWeekDate(weekId);
    final members =
        preloadedMembers ?? await getGroupMembers(groupId, weekDate: weekDate);

    // 2. 출석 및 기도제목 데이터 별도 조회
    // Attendance: No Join (Safest)
    final attendanceTask = _supabase
        .from('attendance')
        .select()
        .eq('week_id', weekId)
        .eq('group_id', groupId);

    // Prayers: No Join (Safest)
    // 원래 Main 브랜치에서는 여기서 조인을 안 했음. 앱 내에서 별도로 매핑하거나 필요한 정보가 없었을 수 있음.
    // 하지만 UI에서 이름을 보여줘야 하므로, 여기서는 나중에 수동 매핑을 시도할 것임.
    var prayersQuery = _supabase
        .from('prayer_entries')
        .select()
        .eq('week_id', weekId)
        .or('group_id.eq.$groupId,recorded_group_id.eq.$groupId');
    if (!includeDrafts) {
      prayersQuery = prayersQuery.eq('status', 'published');
    }
    final prayersTask = prayersQuery.order('created_at', ascending: true);

    final results = await Future.wait([attendanceTask, prayersTask]);
    final attendanceList = List<Map<String, dynamic>>.from(results[0]);
    final prayersList = List<Map<String, dynamic>>.from(results[1]);

    // 3. 누락된 멤버 및 기도 작성자 정보 추가 조회
    // Attendance용 ID 수집
    final currentMemberIds = members.map((m) => m['id']).toSet();
    final missingMemberIds = attendanceList
        .map((a) => a['directory_member_id'] as String)
        .where((id) => !currentMemberIds.contains(id))
        .toSet();

    // Prayers용 ID 수집 (directory_member_id)
    final prayerMemberIds = prayersList
        .map((p) => p['directory_member_id'] as String?)
        .where((id) => id != null && !currentMemberIds.contains(id))
        .cast<String>()
        .toSet();

    missingMemberIds.addAll(prayerMemberIds);

    Map<String, dynamic> missingMembersMap = {};
    if (missingMemberIds.isNotEmpty) {
      try {
        // 안전한 필드만 조회
        final missingResponse = await _supabase
            .from('member_directory')
            .select(
                'id, full_name, family_name, spouse_name, group_name, profile_id, person_id')
            .inFilter('id', missingMemberIds.toList());

        for (final m in missingResponse) {
          missingMembersMap[m['id']] = m;
        }
      } catch (e) {
        debugPrint('GraceNoteRepository: Failed to fetch missing members: $e');
      }
    }

    // 4. 데이터 병합 (Attendance)
    final List<Map<String, dynamic>> attendanceWithInfo = [];

    // [FIX] 조장 화면에서도 미제출 시 빈 배열을 반환해야 "출석 등록하기" 버튼 노출 로직이 동작함
    if (attendanceList.isNotEmpty) {
      for (final att in attendanceList) {
        final dirId = att['directory_member_id'];

        // 1순위: 현재 멤버 리스트
        Map<String, dynamic>? memberInfo =
            members.cast<Map<String, dynamic>?>().firstWhere(
                  (m) => m?['id'] == dirId,
                  orElse: () => null,
                );

        // 2순위: 추가 조회된 이동/비활성 멤버 리스트
        memberInfo ??= missingMembersMap[dirId];

        attendanceWithInfo.add(<String, dynamic>{
          ...att,
          'member_directory':
              memberInfo ?? {'full_name': '이동/비활성 성도', 'id': dirId},
        });
      }
    }

    // 5. 데이터 병합 (Prayers)
    // Prayer 객체에도 member_directory 정보를 넣어줘야 UI에서 이름을 표시함
    final List<Map<String, dynamic>> prayersWithInfo = [];
    for (final prayer in prayersList) {
      final dirId = prayer['directory_member_id'];
      Map<String, dynamic>? memberInfo =
          members.cast<Map<String, dynamic>?>().firstWhere(
                (m) => m?['id'] == dirId,
                orElse: () => null,
              );
      memberInfo ??= missingMembersMap[dirId];

      prayersWithInfo.add({
        ...prayer,
        'member_directory': memberInfo ?? {'full_name': '알 수 없음', 'id': dirId},
      });
    }

    final combinedRows = <Map<String, dynamic>>[
      ...attendanceWithInfo,
      ...prayersWithInfo,
    ];
    final enrichedRows =
        await _enrichPrayerRowsWithPhase2MemberInfo(combinedRows);

    Map<String, dynamic>? submission;
    try {
      final submissionRows = await _supabase
          .from('group_week_record_submissions')
          .select(
              'attendance_submitted_at, attendance_submission_kind, prayer_submitted_at, prayer_submission_kind, submission_note')
          .eq('week_id', weekId)
          .eq('group_id', groupId)
          .limit(1);
      final rows = List<Map<String, dynamic>>.from(submissionRows);
      if (rows.isNotEmpty) submission = rows.first;
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: group week submission lookup failed: $e');
    }

    return {
      'attendance': enrichedRows.take(attendanceWithInfo.length).toList(),
      'prayers': enrichedRows.skip(attendanceWithInfo.length).toList(),
      'record_submission': submission,
    };
  }

  Future<Map<String, RecordCompletionStatus>>
      getGroupRecordCompletionStatusesInRange({
    required String groupId,
    required String churchId,
    required String departmentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (groupId.isEmpty || churchId.isEmpty) return {};

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    var cursor = DateTime(startDate.year, startDate.month, startDate.day)
        .subtract(Duration(days: startDate.weekday % 7));
    var end = DateTime(endDate.year, endDate.month, endDate.day)
        .subtract(Duration(days: endDate.weekday % 7));
    final todayWeek = todayDate.subtract(Duration(days: todayDate.weekday % 7));
    if (end.isAfter(todayWeek)) end = todayWeek;
    if (cursor.isAfter(end)) return {};

    final startStr = _snapToSundayStr(cursor);
    final endStr = _snapToSundayStr(end);

    final weeksResponse = await _supabase
        .from('weeks')
        .select('id, week_date')
        .eq('church_id', churchId)
        .eq('is_active', true)
        .gte('week_date', startStr)
        .lte('week_date', endStr);

    final weekIdByDate = <String, String>{};
    for (final week in List<Map<String, dynamic>>.from(weeksResponse)) {
      final weekDate = DateTime.tryParse(week['week_date']?.toString() ?? '');
      final weekId = week['id']?.toString();
      if (weekDate == null || weekId == null) continue;
      weekIdByDate[_snapToSundayStr(weekDate)] = weekId;
    }

    final weekIds = weekIdByDate.values.toList();
    final submittedAttendanceCountByWeekId = <String, int>{};
    final publishedPrayerCountByWeekId = <String, int>{};
    final noMeetingDates = <String>{};

    if (departmentId.isNotEmpty) {
      final noMeetingResponse = await _supabase
          .from('no_meeting_days')
          .select('week_date')
          .eq('department_id', departmentId)
          .gte('week_date', startStr)
          .lte('week_date', endStr);
      for (final row in List<Map<String, dynamic>>.from(noMeetingResponse)) {
        final weekDate = DateTime.tryParse(row['week_date']?.toString() ?? '');
        if (weekDate != null) {
          noMeetingDates.add(_snapToSundayStr(weekDate));
        }
      }
    }

    if (weekIds.isNotEmpty) {
      final submissionResponse = await _supabase
          .from('group_week_record_submissions')
          .select('week_id, attendance_submitted_at, prayer_submitted_at')
          .inFilter('week_id', weekIds)
          .eq('group_id', groupId);
      for (final row in List<Map<String, dynamic>>.from(submissionResponse)) {
        final weekId = row['week_id']?.toString();
        if (weekId == null) continue;
        final attendanceSubmittedAt =
            row['attendance_submitted_at']?.toString();
        if (attendanceSubmittedAt != null && attendanceSubmittedAt.isNotEmpty) {
          submittedAttendanceCountByWeekId[weekId] = 1;
        }
        final prayerSubmittedAt = row['prayer_submitted_at']?.toString();
        if (prayerSubmittedAt != null && prayerSubmittedAt.isNotEmpty) {
          publishedPrayerCountByWeekId[weekId] = 1;
        }
      }
    }

    final statuses = <String, RecordCompletionStatus>{};
    while (!cursor.isAfter(end)) {
      final dateKey = _snapToSundayStr(cursor);
      final weekId = weekIdByDate[dateKey];
      final status = resolveRecordCompletionStatus(
        isActiveWeek: true,
        isNoMeetingWeek: noMeetingDates.contains(dateKey),
        isFutureWeek: cursor.isAfter(todayDate),
        submittedAttendanceCount: weekId == null
            ? 0
            : (submittedAttendanceCountByWeekId[weekId] ?? 0),
        publishedPrayerCount:
            weekId == null ? 0 : (publishedPrayerCountByWeekId[weekId] ?? 0),
      );
      if (status != RecordCompletionStatus.normal) {
        statuses[dateKey] = status;
      }
      cursor = cursor.add(const Duration(days: 7));
    }
    return statuses;
  }

  // 부서 전체의 특정 주차 데이터 가져오기 (전체 탭용)
  Future<Map<String, dynamic>> getDepartmentWeeklyData(
      String departmentId, String weekId) async {
    if (departmentId.isEmpty || weekId.isEmpty) {
      return {'groups': [], 'prayers': []};
    }
    final weekDate = await _getWeekDate(weekId);

    // 1. 부서 내 조 조회: 선택 주차에 존재했거나 실제 기록이 있는 조만 포함한다.
    final groupsResponse = await _supabase
        .from('groups')
        .select(
            'id, name, color_hex, is_new_member_group, climbing_threshold, is_active, created_at, active_from, ended_at')
        .eq('department_id', departmentId);

    final allGroups = List<Map<String, dynamic>>.from(groupsResponse);
    final groupIds = allGroups.map((g) => g['id'] as String).toList();
    if (groupIds.isEmpty) return {'groups': [], 'prayers': []};

    // 2. 모든 조의 기도제목 조회
    final prayersResponse = await _supabase
        .from('prayer_entries')
        .select(
            '*, member_directory!directory_member_id(family_name, full_name, person_id, spouse_name)') // [FIX] 없는 컬럼 family_id 제거
        .eq('status', 'published')
        .eq('week_id', weekId)
        .or(
          [
            'group_id.in.(${groupIds.join(',')})',
            'recorded_group_id.in.(${groupIds.join(',')})',
          ].join(','),
        )
        .order('family_name',
            referencedTable: 'member_directory',
            ascending: true,
            nullsFirst: false)
        .order('full_name',
            referencedTable: 'member_directory', ascending: true);

    final enrichedPrayers = await _enrichPrayerRowsWithPhase2MemberInfo(
        List<Map<String, dynamic>>.from(prayersResponse));
    final prayerGroupIds = enrichedPrayers
        .map((prayer) =>
            prayer['recorded_group_id']?.toString() ??
            prayer['group_id']?.toString())
        .whereType<String>()
        .toSet();
    final seasonPlanGroups = await _getSeasonPlanGroupsForWeek(
      departmentId,
      weekDate,
      allGroups,
      recordGroupIds: prayerGroupIds,
    );
    final groups = seasonPlanGroups.applies
        ? seasonPlanGroups.groups
        : _groupsForWeekWithLastKnownFallback(
            await _overlayCurrentSeasonGroupPeriods(
              departmentId,
              weekDate,
              allGroups,
            ),
            weekDate,
            recordGroupIds: prayerGroupIds,
          );

    final groupIdsForWeek = groups
        .map((group) => group['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final submissionByGroupId = <String, Map<String, dynamic>>{};
    if (groupIdsForWeek.isNotEmpty) {
      final submissionResponse = await _supabase
          .from('group_week_record_submissions')
          .select(
              'group_id, attendance_submitted_at, attendance_submission_kind, prayer_submitted_at, prayer_submission_kind, submission_note')
          .eq('week_id', weekId)
          .inFilter('group_id', groupIdsForWeek);
      for (final row in List<Map<String, dynamic>>.from(submissionResponse)) {
        final groupId = row['group_id']?.toString();
        if (groupId != null && groupId.isNotEmpty) {
          submissionByGroupId[groupId] = row;
        }
      }
    }

    final groupsWithSubmissionState = groups.map((group) {
      final groupId = group['id']?.toString();
      final submission = groupId == null ? null : submissionByGroupId[groupId];
      return {
        ...group,
        'attendance_submitted_at': submission?['attendance_submitted_at'],
        'attendance_submission_kind':
            submission?['attendance_submission_kind'] ?? 'records',
        'prayer_submitted_at': submission?['prayer_submitted_at'],
        'prayer_submission_kind':
            submission?['prayer_submission_kind'] ?? 'records',
        'submission_note': submission?['submission_note'],
      };
    }).toList();

    return {
      'groups': groupsWithSubmissionState,
      'prayers': enrichedPrayers,
    };
  }

  // 부서 목록 가져오기
  Future<List<DepartmentModel>> getDepartments(String churchId) async {
    final response = await _supabase
        .from('departments')
        .select()
        .eq('church_id', churchId)
        .eq('is_active', true);
    return (response as List).map((e) => DepartmentModel.fromJson(e)).toList();
  }

  // 특정 부서의 모든 조 가져오기
  Future<List<Map<String, dynamic>>> getGroupsInDepartment(
      String departmentId) async {
    final response = await _supabase
        .from('groups')
        .select(
            'id, name, color_hex, is_new_member_group, climbing_threshold, is_active')
        .eq('department_id', departmentId)
        .eq('is_active', true)
        .order('name');

    return List<Map<String, dynamic>>.from(response)
        .map((e) => {
              'id': e['id'],
              'name': e['name'],
              'color_hex': e['color_hex'],
              'is_active': e['is_active'],
              'is_new_member_group': e['is_new_member_group'] ?? false,
              'climbing_threshold':
                  e['climbing_threshold'], // [REFINED] Remove default value
            })
        .toList();
  }

  // 프로필 ID, 이름, 또는 전화번호로 성도 명부 정보 가져오기 (가장 강력한 버전)
  Future<Map<String, dynamic>?> getMemberDirectoryEntry({
    required String profileId,
    required String fullName,
    String? phone,
  }) async {
    final cleanName = fullName.trim();
    final cleanPhone = phone?.trim() ?? '';

    debugPrint(
        'GraceNoteRepository: Seeking directory for [$cleanName] (ID: $profileId, Phone: $cleanPhone)');

    try {
      // 1. profile_id로 우선 조회
      final byIdRes = await _supabase
          .from('member_directory')
          .select()
          .eq('profile_id', profileId)
          .limit(1);

      final byIdList = byIdRes as List;
      if (byIdList.isNotEmpty) {
        final found = byIdList.first;
        debugPrint(
            'GraceNoteRepository: Match found by profile_id -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
        return Map<String, dynamic>.from(found);
      }

      // 2. 전화번호로 조회
      if (cleanPhone.isNotEmpty) {
        final byPhoneRes = await _supabase
            .from('member_directory')
            .select()
            .eq('phone', cleanPhone)
            .limit(1);

        final byPhoneList = byPhoneRes as List;
        if (byPhoneList.isNotEmpty) {
          final found = byPhoneList.first;
          debugPrint(
              'GraceNoteRepository: Match found by phone -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
          return Map<String, dynamic>.from(found);
        }
      }

      // 3. 이름으로 조회 (최후의 보루)
      final byNameRes = await _supabase
          .from('member_directory')
          .select()
          .eq('full_name', cleanName)
          .limit(1);

      final byNameList = byNameRes as List;
      if (byNameList.isNotEmpty) {
        final found = byNameList.first;
        debugPrint(
            'GraceNoteRepository: Match found by full_name -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
        return Map<String, dynamic>.from(found);
      }

      debugPrint(
          'GraceNoteRepository: No directory entry found for [$cleanName]');
    } catch (e) {
      debugPrint('GraceNoteRepository Error in getMemberDirectoryEntry: $e');
    }

    debugPrint(
        'GraceNoteRepository: CRITICAL - No entry found in member_directory for $cleanName');
    return null;
  }

  // 특정 조의 멤버 목록 가져오기 (성도 명부 기준 - 메모리 조인 방식)
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId,
      {DateTime? weekDate}) async {
    // 1. 조 정보 가져오기
    final groupResponse = await _supabase
        .from('groups')
        .select(
            'id, church_id, department_id, name, is_new_member_group, climbing_threshold, is_active, created_at, active_from, ended_at')
        .eq('id', groupId)
        .single();

    final groupName = groupResponse['name'];
    final churchId = groupResponse['church_id'];
    final departmentId = groupResponse['department_id'];
    final seasonAwareGroup = (await _overlayCurrentSeasonGroupPeriods(
      departmentId,
      weekDate,
      [Map<String, dynamic>.from(groupResponse)],
    ))
        .first;

    // 2. 명부 데이터 가져오기:
    // 주차가 지정된 출석/기도 작성 화면에서는 적용된 시즌 plan이 source of truth다.
    final seasonPlanMembers = weekDate == null
        ? const _SeasonPlanMembersResult.notApplicable()
        : await _getGroupMembersFromSeasonPlanAssignments(
            groupId,
            weekDate: weekDate,
            groupName: groupName?.toString(),
            churchId: churchId,
            departmentId: departmentId,
          );
    final phase2Members = seasonPlanMembers.applies
        ? seasonPlanMembers.members
        : await _getGroupMembersFromMemberships(
            groupId,
            weekDate: weekDate,
            churchId: churchId,
            departmentId: departmentId,
            groupPeriodOverride: seasonAwareGroup,
          );
    final directoryResponse = phase2Members.isNotEmpty
        ? phase2Members
        : weekDate != null
            ? <Map<String, dynamic>>[]
            : await _supabase
                .from('member_directory')
                .select()
                .eq('church_id', churchId)
                .eq('department_id', departmentId)
                .eq('group_name', groupName)
                .eq('is_active', true)
                .order('family_name', ascending: true, nullsFirst: false)
                .order('full_name', ascending: true);

    final membersList = List<Map<String, dynamic>>.from(directoryResponse);
    if (membersList.isEmpty) return [];

    // 3. Phase 2 member_profiles로 person/profile 연결을 보강한다.
    // member_directory.profile_id가 비어 있어도 같은 person 구조에서는
    // member_profiles.profile_id가 앱 계정 연결의 기준이 될 수 있다.
    final directoryIds = membersList
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toList();

    final Map<String, Map<String, dynamic>> memberProfileByDirectoryId = {};
    if (directoryIds.isNotEmpty) {
      try {
        final memberProfilesResponse = await _supabase
            .from('member_profiles')
            .select('member_directory_id, profile_id, person_id')
            .inFilter('member_directory_id', directoryIds);

        for (final profile
            in List<Map<String, dynamic>>.from(memberProfilesResponse)) {
          final directoryId = profile['member_directory_id']?.toString();
          if (directoryId != null) {
            memberProfileByDirectoryId[directoryId] = profile;
          }
        }
      } catch (e) {
        debugPrint(
            'GraceNoteRepository: member_profiles group member enrichment failed: $e');
      }
    }

    String? profileIdForMember(Map<String, dynamic> member) {
      final legacyProfileId = member['profile_id']?.toString();
      if (legacyProfileId != null && legacyProfileId.isNotEmpty) {
        return legacyProfileId;
      }

      final directoryId = member['id']?.toString();
      if (directoryId == null) return null;
      return memberProfileByDirectoryId[directoryId]?['profile_id']?.toString();
    }

    final profileIds = membersList
        .map(profileIdForMember)
        .whereType<String>()
        .toSet()
        .toList();

    // 4. 해당 프로필들의 정보와 group_members 정보 가져오기
    // profile_id가 있는 경우 해당 ID들로 조회, 없으면 이름 매칭을 위해 부서 전체(혹은 빈 리스트) 대신
    // 이름 목록으로 필터링하여 가져옴
    final List<Map<String, dynamic>> allProfiles;
    if (profileIds.isNotEmpty) {
      final profilesResponse = await _supabase
          .from('profiles')
          .select('*, group_members(*), families(name)') // [FIX] 가족 이름 추가 조회
          .inFilter('id', profileIds);
      allProfiles = List<Map<String, dynamic>>.from(profilesResponse);
    } else {
      allProfiles = [];
    }

    // 이름으로만 존재하는 (미연동) 프로필들도 추가 조회 (안전장치)
    final missingNames = membersList
        .where((m) => profileIdForMember(m) == null)
        .map((m) => m['full_name'] as String)
        .toList();

    if (missingNames.isNotEmpty) {
      final extraProfilesResponse = await _supabase
          .from('profiles')
          .select('*, group_members(*), families(name)') // [FIX] 가족 이름 추가 조회
          .eq('church_id', churchId)
          .eq('department_id', departmentId)
          .inFilter('full_name', missingNames);
      allProfiles
          .addAll(List<Map<String, dynamic>>.from(extraProfilesResponse));
    }

    // 5. 메모리에서 조인 수행
    return membersList.map<Map<String, dynamic>>((dir) {
      final pId = profileIdForMember(dir);
      final name = dir['full_name'];
      final directoryId = dir['id']?.toString();
      final phase2Profile =
          directoryId == null ? null : memberProfileByDirectoryId[directoryId];

      // 1순위: profile_id 매칭, 2순위: 이름 매칭
      Map<String, dynamic>? profile;
      if (pId != null) {
        profile = allProfiles.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p?['id'] == pId,
              orElse: () => null,
            );
      }

      if (profile == null && name != null) {
        profile = allProfiles.cast<Map<String, dynamic>?>().firstWhere(
              (p) =>
                  p?['full_name'] == name &&
                  p?['id'] != null, // 다른 사람과 겹치지 않게 조심
              orElse: () => null,
            );
      }

      String? groupMemberId;
      if (profile != null && profile['group_members'] != null) {
        final gMembers = profile['group_members'] as List;
        final match = gMembers.firstWhere((gm) => gm['group_id'] == groupId,
            orElse: () => null);
        groupMemberId = match?['id'];
      }

      return <String, dynamic>{
        ...dir,
        'profiles': profile,
        'profile_id': profile?['id'] ?? pId, // 프로필을 못 찾더라도 명부의 pId는 유지
        if (phase2Profile?['person_id'] != null)
          'person_id': phase2Profile!['person_id'],
        'group_member_id': dir['group_member_id'] ?? groupMemberId,
      };
    }).toList();
  }

  Future<_SeasonPlanMembersResult> _getGroupMembersFromSeasonPlanAssignments(
      String groupId,
      {required DateTime weekDate,
      String? groupName,
      String? churchId,
      String? departmentId}) async {
    if (departmentId == null || departmentId.isEmpty) {
      return const _SeasonPlanMembersResult.notApplicable();
    }

    try {
      final weekText = _snapToSundayStr(weekDate);
      final snappedWeekDate = DateTime.parse(weekText);

      final seasons = await _supabase
          .from('regrouping_seasons')
          .select('id')
          .eq('department_id', departmentId)
          .eq('status', 'applied')
          .lte('effective_week_date', weekText)
          .or('end_week_date.is.null,end_week_date.gte.$weekText')
          .order('effective_week_date', ascending: false)
          .limit(1);

      final seasonRows = List<Map<String, dynamic>>.from(seasons);
      if (seasonRows.isEmpty) {
        return const _SeasonPlanMembersResult.notApplicable();
      }

      final seasonId = seasonRows.first['id']?.toString();
      if (seasonId == null || seasonId.isEmpty) {
        return const _SeasonPlanMembersResult.notApplicable();
      }

      final planGroups = await _supabase
          .from('regrouping_plan_groups')
          .select(
              'id, source_group_id, name, starts_week_date, ends_week_date, plan_status')
          .eq('season_id', seasonId);

      final planGroupRows = List<Map<String, dynamic>>.from(planGroups);
      final planGroup = planGroupRows.firstWhere(
        (row) => row['source_group_id']?.toString() == groupId,
        orElse: () => groupName == null
            ? <String, dynamic>{}
            : planGroupRows.firstWhere(
                (row) =>
                    row['source_group_id'] == null &&
                    row['name']?.toString() == groupName,
                orElse: () => <String, dynamic>{},
              ),
      );

      if (planGroup.isEmpty) {
        return const _SeasonPlanMembersResult.notApplicable();
      }

      final planGroupId = planGroup['id']?.toString();
      if (planGroupId == null || planGroupId.isEmpty) {
        return const _SeasonPlanMembersResult.notApplicable();
      }

      final planGroupForWeek = _membershipWasInUseOnWeek({
        'starts_at': planGroup['starts_week_date'],
        'ends_at': planGroup['ends_week_date'],
        'groups': {
          'active_from': planGroup['starts_week_date'],
          'ended_at': planGroup['ends_week_date'],
        },
      }, snappedWeekDate);

      if (!planGroupForWeek) {
        return const _SeasonPlanMembersResult.applied([]);
      }

      final assignmentsResponse = await _supabase
          .from('regrouping_plan_assignments')
          .select(
              'id, person_id, source_member_directory_id, role_in_group, starts_week_date, ends_week_date')
          .eq('season_id', seasonId)
          .eq('plan_group_id', planGroupId)
          .lte('starts_week_date', weekText)
          .or('ends_week_date.is.null,ends_week_date.gte.$weekText')
          .order('role_in_group', ascending: true);

      final assignments = List<Map<String, dynamic>>.from(assignmentsResponse);
      if (assignments.isEmpty) {
        return const _SeasonPlanMembersResult.applied([]);
      }

      final directoryIds = assignments
          .map((row) => row['source_member_directory_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final personIds = assignments
          .map((row) => row['person_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final directoryRowsById = <String, Map<String, dynamic>>{};
      if (directoryIds.isNotEmpty) {
        final directoryResponse = await _supabase
            .from('member_directory')
            .select()
            .inFilter('id', directoryIds)
            .order('is_active', ascending: false)
            .order('family_name', ascending: true, nullsFirst: false)
            .order('full_name', ascending: true);

        for (final row in List<Map<String, dynamic>>.from(directoryResponse)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) {
            directoryRowsById[id] = row;
          }
        }
      }

      if (personIds.isNotEmpty && churchId != null) {
        final personDirectoryResponse = await _supabase
            .from('member_directory')
            .select()
            .eq('church_id', churchId)
            .eq('department_id', departmentId)
            .inFilter('person_id', personIds)
            .order('is_active', ascending: false)
            .order('family_name', ascending: true, nullsFirst: false)
            .order('full_name', ascending: true);

        for (final row
            in List<Map<String, dynamic>>.from(personDirectoryResponse)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) {
            directoryRowsById[id] = row;
          }
        }
      }

      final assignmentByDirectoryId = {
        for (final assignment in assignments)
          if (assignment['source_member_directory_id'] != null)
            assignment['source_member_directory_id'].toString(): assignment,
      };
      final assignmentByPersonId = <String, Map<String, dynamic>>{};
      for (final assignment in assignments) {
        final personId = assignment['person_id']?.toString();
        if (personId != null && personId.isNotEmpty) {
          assignmentByPersonId[personId] ??= assignment;
        }
      }

      final seenPersonIds = <String>{};
      final rows = <Map<String, dynamic>>[];
      for (final dir in directoryRowsById.values) {
        final personId = dir['person_id']?.toString();
        if (personId != null && personId.isNotEmpty) {
          if (seenPersonIds.contains(personId)) continue;
          seenPersonIds.add(personId);
        }

        final assignment = assignmentByDirectoryId[dir['id']?.toString()] ??
            (personId == null ? null : assignmentByPersonId[personId]);
        if (assignment == null) continue;

        rows.add({
          ...dir,
          if (assignment['person_id'] != null)
            'person_id': assignment['person_id'],
          'role_in_group': assignment['role_in_group'] ?? dir['role_in_group'],
          'membership_id': assignment['id'],
          'membership_starts_at': assignment['starts_week_date']?.toString(),
          'membership_ends_at': assignment['ends_week_date']?.toString(),
          'phase2_membership_source': 'regrouping_plan_assignments',
        });
      }

      rows.sort((a, b) {
        final roleA = a['role_in_group']?.toString() == 'leader' ? 0 : 1;
        final roleB = b['role_in_group']?.toString() == 'leader' ? 0 : 1;
        if (roleA != roleB) return roleA.compareTo(roleB);
        return (a['full_name']?.toString() ?? '')
            .compareTo(b['full_name']?.toString() ?? '');
      });

      return _SeasonPlanMembersResult.applied(rows);
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: season plan group member read failed, using memberships fallback: $e');
      return const _SeasonPlanMembersResult.notApplicable();
    }
  }

  Future<List<Map<String, dynamic>>> _getGroupMembersFromMemberships(
      String groupId,
      {DateTime? weekDate,
      String? churchId,
      String? departmentId,
      Map<String, dynamic>? groupPeriodOverride}) async {
    try {
      final membershipsResponse = await _supabase
          .from('memberships')
          .select(
              'id, person_id, legacy_member_directory_id, legacy_group_member_id, role, status, starts_at, ends_at, groups(active_from, ended_at)')
          .eq('group_id', groupId)
          .inFilter('status', ['active', 'ended']);

      final rawMemberships =
          List<Map<String, dynamic>>.from(membershipsResponse);
      final memberships = rawMemberships
          .map((membership) {
            if (groupPeriodOverride == null) return membership;
            final nestedGroup = membership['groups'] is Map
                ? Map<String, dynamic>.from(membership['groups'] as Map)
                : <String, dynamic>{};
            return <String, dynamic>{
              ...membership,
              'groups': {
                ...nestedGroup,
                'active_from': groupPeriodOverride['active_from'],
                'ended_at': groupPeriodOverride['ended_at'],
              },
            };
          })
          .where((membership) => _membershipWasInUseOnWeek(
                membership,
                weekDate,
              ))
          .toList();
      if (memberships.isEmpty) return [];

      final directoryIds = memberships
          .map((m) => m['legacy_member_directory_id'])
          .where((id) => id != null)
          .cast<String>()
          .toList();
      final personIds = memberships
          .map((m) => m['person_id'])
          .where((id) => id != null)
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (directoryIds.isEmpty && personIds.isEmpty) return [];

      final membershipByDirectoryId = {
        for (final membership in memberships)
          if (membership['legacy_member_directory_id'] != null)
            membership['legacy_member_directory_id'].toString(): membership
      };

      // [FIX] legacy_member_directory_id가 없는 조장 row도 person_id로 명부 row를
      // 찾아 출석/기도 작성 대상에 포함한다.
      final directoryRowsById = <String, Map<String, dynamic>>{};
      if (directoryIds.isNotEmpty) {
        final directoryResponse = await _supabase
            .from('member_directory')
            .select()
            .inFilter('id', directoryIds)
            .order('is_active', ascending: false)
            .order('family_name', ascending: true, nullsFirst: false)
            .order('full_name', ascending: true);

        for (final row in List<Map<String, dynamic>>.from(directoryResponse)) {
          final id = row['id']?.toString();
          if (id != null) directoryRowsById[id] = row;
        }
      }

      if (personIds.isNotEmpty && churchId != null && departmentId != null) {
        final personDirectoryResponse = await _supabase
            .from('member_directory')
            .select()
            .eq('church_id', churchId)
            .eq('department_id', departmentId)
            .inFilter('person_id', personIds)
            .order('is_active', ascending: false)
            .order('family_name', ascending: true, nullsFirst: false)
            .order('full_name', ascending: true);

        for (final row
            in List<Map<String, dynamic>>.from(personDirectoryResponse)) {
          final id = row['id']?.toString();
          if (id != null) directoryRowsById[id] = row;
        }
      }

      // 동일 person_id에 여러 row가 있을 때 is_active=true 우선으로 1개만 선택
      final allDirs = directoryRowsById.values.toList();
      final seenPersonIds = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final dir in allDirs) {
        final pid = dir['person_id']?.toString();
        if (pid != null && pid.isNotEmpty) {
          if (seenPersonIds.contains(pid)) continue;
          seenPersonIds.add(pid);
        }
        deduped.add(dir);
      }

      // [FIX] person_id 기준 멤버십 룩업도 추가:
      // deduped에서 is_active=true row가 선택됐지만 실제 멤버십은
      // 같은 person의 다른 directory id에 연결된 경우 폴백으로 사용
      final membershipByPersonId = <String, Map<String, dynamic>>{};
      for (final membership in memberships) {
        final pid = membership['person_id']?.toString();
        if (pid != null && pid.isNotEmpty) {
          membershipByPersonId[pid] ??= membership;
        }
      }

      return deduped.map((dir) {
        // 1순위: directory id로 직접 매핑
        Map<String, dynamic>? membership = membershipByDirectoryId[dir['id']];
        // 2순위: 같은 person_id의 다른 directory row에 연결된 멤버십
        if (membership == null) {
          final pid = dir['person_id']?.toString();
          if (pid != null && pid.isNotEmpty) {
            membership = membershipByPersonId[pid];
          }
        }
        return <String, dynamic>{
          ...dir,
          if (membership?['person_id'] != null)
            'person_id': membership!['person_id'],
          'group_member_id': membership?['legacy_group_member_id'],
          'role_in_group': membership?['role'] ?? dir['role_in_group'],
          'membership_id': membership?['id'],
          'membership_starts_at': membership?['starts_at']?.toString(),
          'membership_ends_at': membership?['ends_at']?.toString(),
          'phase2_membership_source': 'memberships',
        };
      }).toList();
    } catch (e) {
      debugPrint(
          'GraceNoteRepository: memberships group member read failed, using legacy fallback: $e');
      return [];
    }
  }

  // 부서 설정 업데이트
  Future<void> updateDepartmentSettings(
      String deptId, Map<String, dynamic> settings) async {
    await _supabase.from('departments').update(settings).eq('id', deptId);
  }

  // 온보딩 완료 (프로필 생성 및 조 가입)
  Future<void> completeOnboarding({
    required String profileId,
    required String fullName,
    String? churchId,
    String? groupId,
    String? phone,
    Map<String, dynamic>? matchedData,
  }) async {
    String? departmentId = matchedData?['department_id'];
    String? familyId;

    // 1. 만약 매칭된 데이터가 있고 가족 정보가 있다면 처리
    if (matchedData != null) {
      if (matchedData['family_name'] != null) {
        // 이미 생성된 가족이 있는지 확인 (간소화 위해 이름 기반)
        final existingFamily = (churchId != null)
            ? await _supabase
                .from('families')
                .select('id')
                .eq('church_id', churchId)
                .eq('name', matchedData['family_name'])
                .maybeSingle()
            : null;

        if (existingFamily != null) {
          familyId = existingFamily['id'];
        } else {
          final newFamily = await _supabase
              .from('families')
              .insert({
                'church_id': churchId,
                'department_id': departmentId,
                'name': matchedData['family_name'],
              })
              .select('id')
              .single();
          familyId = newFamily['id'];
        }
      }
    }

    // 2. 프로필 생성 및 업데이트
    // [FIX] For admins, preserve existing church/dept if matchedData is null
    Map<String, dynamic> updateData = {
      'id': profileId,
      'full_name': fullName,
      'phone': phone,
      'is_onboarding_complete': true,
    };

    if (churchId != null) updateData['church_id'] = churchId;
    if (departmentId != null) updateData['department_id'] = departmentId;
    if (familyId != null) updateData['family_id'] = familyId;
    if (matchedData != null && matchedData['person_id'] != null) {
      updateData['person_id'] = matchedData['person_id'];
    }

    await _supabase.from('profiles').upsert(updateData, onConflict: 'id');

    // [NOTE] 나머지 group_members 및 member_directory 연결은
    // 백엔드의 sync_profile_to_all_memberships 트리거가 person_id 할당 시 자동으로 처리합니다.
  }

  // 소셜 로그인 (Kakao, Google)
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    // Web must not fall back to the Supabase Site URL because the dev project
    // can point to admin-web. Keep app OAuth callbacks on the current app origin.
    final String redirectTo = kIsWeb
        ? '${Uri.base.origin}/login'
        : 'io.supabase.flutter://login-callback';

    // 카카오 로그인 시 비즈앱 등록 전이므로 account_email 제외
    if (provider == OAuthProvider.kakao) {
      await _supabase.auth.signInWithOAuth(
        provider,
        redirectTo: redirectTo,
        queryParams: {
          'scope': 'profile_nickname,profile_image', // 이메일 제외
        },
      );
    } else {
      await _supabase.auth.signInWithOAuth(
        provider,
        redirectTo: redirectTo,
      );
    }
  }

  String _formatPhase2SyncNames(
      List<Map<String, dynamic>> directories, Set<String> ids) {
    final names = directories
        .where((row) => ids.contains(row['id']?.toString()))
        .map((row) => row['full_name']?.toString() ?? row['id'].toString())
        .toList();

    if (names.length <= 5) return names.join(', ');
    return '${names.take(5).join(', ')} 외 ${names.length - 5}명';
  }

  Future<void> _assertPhase2MemberDirectorySync(
    List<String> memberDirectoryIds,
    String contextLabel,
  ) async {
    final ids =
        memberDirectoryIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;

    final directoryResponse = await _supabase
        .from('member_directory')
        .select('id, full_name, group_name, is_active')
        .inFilter('id', ids);
    final directories = List<Map<String, dynamic>>.from(directoryResponse);
    final existingDirectoryIds = directories
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    final missingDirectoryIds =
        ids.where((id) => !existingDirectoryIds.contains(id)).toList();

    if (missingDirectoryIds.isNotEmpty) {
      throw Exception(
          '$contextLabel 후 legacy 명부 row를 다시 확인하지 못했습니다: ${missingDirectoryIds.join(', ')}');
    }

    final profileResponse = await _supabase
        .from('member_profiles')
        .select('member_directory_id, person_id')
        .inFilter('member_directory_id', ids);
    final profileRows = List<Map<String, dynamic>>.from(profileResponse);
    final profileDirectoryIds = profileRows
        .where((row) =>
            row['member_directory_id'] != null && row['person_id'] != null)
        .map((row) => row['member_directory_id'].toString())
        .toSet();

    final missingProfileIds = directories
        .where((row) => !profileDirectoryIds.contains(row['id']?.toString()))
        .map((row) => row['id'].toString())
        .toSet();

    final membershipExpectedIds = directories
        .where((row) => row['is_active'] != false)
        .where((row) => (row['group_name']?.toString().trim() ?? '').isNotEmpty)
        .map((row) => row['id'].toString())
        .toList();

    final membershipDirectoryIds = <String>{};
    if (membershipExpectedIds.isNotEmpty) {
      final membershipResponse = await _supabase
          .from('memberships')
          .select('legacy_member_directory_id')
          .inFilter('legacy_member_directory_id', membershipExpectedIds)
          .inFilter('status', ['active', 'inactive', 'ended']);
      membershipDirectoryIds.addAll(
        List<Map<String, dynamic>>.from(membershipResponse)
            .map((row) => row['legacy_member_directory_id']?.toString())
            .whereType<String>(),
      );
    }

    final missingMembershipIds = membershipExpectedIds
        .where((id) => !membershipDirectoryIds.contains(id))
        .toSet();

    if (missingProfileIds.isEmpty && missingMembershipIds.isEmpty) return;

    final messages = [
      if (missingProfileIds.isNotEmpty)
        'member_profiles 누락: ${_formatPhase2SyncNames(directories, missingProfileIds)}',
      if (missingMembershipIds.isNotEmpty)
        'memberships 누락: ${_formatPhase2SyncNames(directories, missingMembershipIds)}',
    ];

    throw Exception(
        '$contextLabel 후 Phase 2 person 동기화가 완료되지 않았습니다. ${messages.join(' / ')}');
  }

  // 명부에 새 멤버 추가
  Future<void> addDirectoryMember(Map<String, dynamic> data) async {
    final inserted = await _upsertMemberPersonMembership(data);
    await _assertPhase2MemberDirectorySync(
      [inserted['id']?.toString() ?? ''],
      '성도 추가',
    );
  }

  // 명부 멤버 정보 수정
  Future<void> updateDirectoryMember(
      String id, Map<String, dynamic> data) async {
    final existing = await _supabase
        .from('member_directory')
        .select()
        .eq('id', id)
        .maybeSingle();
    final merged = {
      if (existing != null) ...Map<String, dynamic>.from(existing),
      ...data,
    };
    final updated = await _upsertMemberPersonMembership(
      merged,
      memberDirectoryId: id,
    );
    await _assertPhase2MemberDirectorySync(
      [updated['id']?.toString() ?? id],
      '성도 수정',
    );
  }

  Future<void> moveDirectoryMemberToGroup({
    required String memberDirectoryId,
    required String sourceGroupId,
    required String targetGroupId,
    required DateTime effectiveWeekDate,
  }) async {
    final result = await _supabase.rpc(
      'move_member_directory_to_group',
      params: {
        'p_member_directory_id': memberDirectoryId,
        'p_source_group_id': sourceGroupId,
        'p_target_group_id': targetGroupId,
        'p_effective_week_date':
            effectiveWeekDate.toIso8601String().split('T').first,
      },
    );

    final updated = result is Map
        ? Map<String, dynamic>.from(result)
        : result is List && result.isNotEmpty && result.first is Map
            ? Map<String, dynamic>.from(result.first as Map)
            : <String, dynamic>{'id': memberDirectoryId};

    await _assertPhase2MemberDirectorySync(
      [updated['id']?.toString() ?? memberDirectoryId],
      '성도 조 편성',
    );
  }

  Future<Map<String, dynamic>> _upsertMemberPersonMembership(
    Map<String, dynamic> data, {
    String? memberDirectoryId,
  }) async {
    dynamic dateParam(dynamic value) {
      if (value is DateTime) return value.toIso8601String().split('T').first;
      return value;
    }

    final result = await _supabase.rpc(
      'upsert_member_person_membership',
      params: {
        'p_member_directory_id': memberDirectoryId ?? data['id'],
        'p_church_id': data['church_id'],
        'p_department_id': data['department_id'],
        'p_full_name': data['full_name'],
        'p_phone': data['phone'],
        'p_group_name': data['group_name'],
        'p_role_in_group': data['role_in_group'] ?? 'member',
        'p_family_name': data['family_name'],
        'p_spouse_name': data['spouse_name'],
        'p_children_info': data['children_info'],
        'p_birth_date': dateParam(data['birth_date']),
        'p_wedding_anniversary': dateParam(data['wedding_anniversary']),
        'p_notes': data['notes'],
        'p_avatar_url': data['avatar_url'],
        'p_profile_id': data['profile_id'],
        'p_person_id': data['person_id'],
        'p_is_active': data['is_active'] != false,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }

    throw Exception('성도 저장 RPC가 저장된 성도 정보를 반환하지 않았습니다.');
  }

  // 명부 멤버 활성화/비활성화 토글
  Future<void> toggleMemberActivation(String id, bool isActive) async {
    final updated = await _setMemberDirectoryActiveStatus(id, isActive);
    await _assertPhase2MemberDirectorySync(
      [updated['id']?.toString() ?? id],
      isActive ? '성도 소속 활성화' : '성도 소속 비활성화',
    );
  }

  // 명부 멤버 제거
  Future<void> deleteDirectoryMember(String id) async {
    final updated = await _setMemberDirectoryActiveStatus(id, false);
    await _assertPhase2MemberDirectorySync(
      [updated['id']?.toString() ?? id],
      '성도 소속 비활성화',
    );
  }

  Future<Map<String, dynamic>> _setMemberDirectoryActiveStatus(
    String id,
    bool isActive,
  ) async {
    final result = await _supabase.rpc(
      'set_member_directory_active_status',
      params: {
        'p_member_directory_id': id,
        'p_is_active': isActive,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }

    throw Exception('성도 활성 상태 변경 RPC가 저장된 성도 정보를 반환하지 않았습니다.');
  }

  // 특정 조의 주차별 출석 히스토리 및 통계 가져오기 (년/월 필터링 추가)
  Future<List<Map<String, dynamic>>> getGroupAttendanceHistory(String groupId,
      {int? year, int? month, int limit = 6}) async {
    // 1. 조 정보 가져오기
    final group = await _supabase
        .from('groups')
        .select(
            'id, church_id, department_id, is_active, created_at, active_from, ended_at')
        .eq('id', groupId)
        .single();

    final churchId = group['church_id'];
    final departmentId = group['department_id']?.toString();

    // 2. 주차 정보 가져오기
    var query = _supabase
        .from('weeks')
        .select('id, week_date')
        .eq('church_id', churchId)
        .eq('is_active', true);

    if (year != null && month != null) {
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
      query = query
          .gte('week_date', startOfMonth.toIso8601String())
          .lte('week_date', endOfMonth.toIso8601String());
    }

    final weeksResponse =
        await query.order('week_date', ascending: false).limit(limit);

    final seasonAwareGroup = departmentId == null
        ? Map<String, dynamic>.from(group)
        : (await _overlayCurrentSeasonGroupPeriods(
            departmentId,
            year != null && month != null
                ? DateTime(year, month, 1)
                : DateTime.now(),
            [Map<String, dynamic>.from(group)],
          ))
            .first;

    final weeks = List<Map<String, dynamic>>.from(weeksResponse)
        .where((week) => _groupWasInUseOnWeek(
              seasonAwareGroup,
              DateTime.tryParse(week['week_date']?.toString() ?? ''),
            ))
        .toList();
    final weekIds = weeks.map((w) => w['id'] as String).toList();

    if (weekIds.isEmpty) return [];

    // 3. 출석 데이터 조회
    final attendanceResponse = await _supabase
        .from('attendance')
        .select('week_id, status, directory_member_id')
        .inFilter('week_id', weekIds)
        .eq('group_id', groupId);

    final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);

    // 4. 주차별로 그룹화 및 통계 계산
    return weeks.map((week) {
      final weekId = week['id'];
      final weekAttendance =
          attendanceData.where((a) => a['week_id'] == weekId).toList();

      final presentCount = weekAttendance
          .where((a) => a['status'] == 'present' || a['status'] == 'late')
          .length;
      final totalCount = weekAttendance.length;

      return {
        'week_id': weekId,
        'week_date': week['week_date'],
        'present_count': presentCount,
        'total_count': totalCount,
        'attendance_rate': totalCount > 0 ? presentCount / totalCount : 0.0,
      };
    }).toList();
  }

  // 부서 전체의 주차별 출석 히스토리 및 통계 가져오기
  Future<List<Map<String, dynamic>>> getDepartmentAttendanceHistory(
      String departmentId,
      {int? year,
      int? month,
      int limit = 6}) async {
    // 1. 부서 정보 가져오기
    final dept = await _supabase
        .from('departments')
        .select('church_id')
        .eq('id', departmentId)
        .single();

    final churchId = dept['church_id'];

    // 2. 주차 정보
    var query = _supabase
        .from('weeks')
        .select('id, week_date')
        .eq('church_id', churchId)
        .eq('is_active', true);

    if (year != null && month != null) {
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
      query = query
          .gte('week_date', startOfMonth.toIso8601String())
          .lte('week_date', endOfMonth.toIso8601String());
    }

    final weeksResponse =
        await query.order('week_date', ascending: false).limit(limit);

    final weeks = List<Map<String, dynamic>>.from(weeksResponse);
    final weekIds = weeks.map((w) => w['id'] as String).toList();

    if (weekIds.isEmpty) return [];

    // 3. 부서 내 모든 조 ID 확보
    final groupsResponse = await _supabase
        .from('groups')
        .select('id')
        .eq('department_id', departmentId);
    final groupIds =
        (groupsResponse as List).map((g) => g['id'] as String).toList();

    // 시즌 조편성 적용 이후에는 한 사람이 새가족조와 일반조에 동시에 속할 수 있다.
    // 월별 히스토리는 row 수가 아니라 사람 기준으로 dedupe해서 관리자 웹과 같은 숫자를 사용한다.
    final targetPersonKeysByWeekId = <String, Set<String>>{};
    for (final week in weeks) {
      final weekDate = DateTime.tryParse(week['week_date']?.toString() ?? '');
      final targetKeys =
          await _getSeasonPlanTargetPersonKeysForWeek(departmentId, weekDate);
      if (targetKeys != null) {
        targetPersonKeysByWeekId[week['id'] as String] = targetKeys;
      }
    }

    int fallbackTotalMembersInDept = 0;
    if (targetPersonKeysByWeekId.length < weeks.length) {
      final directoryResponse = await _supabase
          .from('member_directory')
          .select('id, person_id')
          .eq('department_id', departmentId)
          .eq('is_active', true);
      final keys = <String>{};
      for (final row in List<Map<String, dynamic>>.from(directoryResponse)) {
        final key = attendancePersonKey(row);
        if (key != null) keys.add(key);
      }
      fallbackTotalMembersInDept = keys.length;
    }

    // 4. 출석 데이터 조회
    final attendanceResponse = await _supabase
        .from('attendance')
        .select('week_id, status, person_id, directory_member_id')
        .inFilter('week_id', weekIds)
        .inFilter('group_id', groupIds);

    final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);

    return weeks.map((week) {
      final weekId = week['id'];
      final weekAttendance =
          attendanceData.where((a) => a['week_id'] == weekId).toList();

      final presentCount = weekAttendance
          .where((a) => isAttendancePresent(a['status']))
          .map(attendancePersonKey)
          .whereType<String>()
          .toSet()
          .length;
      final totalCount = targetPersonKeysByWeekId[weekId]?.length ??
          fallbackTotalMembersInDept;

      return {
        'week_id': weekId,
        'week_date': week['week_date'],
        'present_count': presentCount,
        'total_count': totalCount,
        'attendance_rate': totalCount > 0 ? presentCount / totalCount : 0.0,
      };
    }).toList();
  }

  // [NEW] 부서 전체의 특정 주차 상세 출석 현황 (명단 포함)
  Future<Map<String, dynamic>> getDepartmentWeeklyAttendanceDetails(
      String departmentId, String weekId) async {
    if (departmentId.isEmpty || weekId.isEmpty) return {'groups': []};
    final weekDate = await _getWeekDate(weekId);

    // 1. 부서 내 모든 조 조회
    final groupsResponse = await _supabase
        .from('groups')
        .select('id, name, is_active, created_at, active_from, ended_at')
        .eq('department_id', departmentId)
        .order('name');
    final allGroups = List<Map<String, dynamic>>.from(groupsResponse);

    // 2. 부서 내 모든 멤버 조회 (매칭용)
    final directoryResponse = await _supabase
        .from('member_directory')
        .select('id, person_id, full_name, group_name, profile_id, spouse_name')
        .eq('department_id', departmentId)
        .eq('is_active', true);
    final allMembers = List<Map<String, dynamic>>.from(directoryResponse);

    // 3. 해당 주차의 출석 데이터 조회
    final attendanceResponse = await _supabase
        .from('attendance')
        .select(
            'directory_member_id, person_id, status, group_id, recorded_group_id')
        .eq('week_id', weekId);
    final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);

    // 4. 누락된 멤버(조 이동/비활성 등) 추가 조회
    final currentMemberIds = allMembers.map((m) => m['id']).toSet();
    final missingMemberIds = attendanceData
        .map((a) => a['directory_member_id'] as String)
        .where((id) => !currentMemberIds.contains(id))
        .toSet()
        .toList();

    Map<String, dynamic> missingMembersMap = {};
    if (missingMemberIds.isNotEmpty) {
      try {
        final missingResponse = await _supabase
            .from('member_directory')
            .select('id, person_id, full_name, group_name')
            .inFilter('id', missingMemberIds);
        for (final m in missingResponse) {
          missingMembersMap[m['id']] = m;
        }
      } catch (e) {
        debugPrint(
            'GraceNoteRepository: Failed to fetch missing department members: $e');
      }
    }

    final attendanceGroupIds = attendanceData
        .map((row) =>
            row['recorded_group_id']?.toString() ?? row['group_id']?.toString())
        .whereType<String>()
        .toSet();
    final seasonPlanGroups = await _getSeasonPlanGroupsForWeek(
      departmentId,
      weekDate,
      allGroups,
      recordGroupIds: attendanceGroupIds,
    );
    final groups = seasonPlanGroups.applies
        ? seasonPlanGroups.groups
        : _groupsForWeekWithLastKnownFallback(
            await _overlayCurrentSeasonGroupPeriods(
              departmentId,
              weekDate,
              allGroups,
            ),
            weekDate,
            recordGroupIds: attendanceGroupIds,
          );

    final groupIdsForWeek = groups
        .map((group) => group['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final submissionByGroupId = <String, Map<String, dynamic>>{};
    if (groupIdsForWeek.isNotEmpty) {
      final submissionResponse = await _supabase
          .from('group_week_record_submissions')
          .select(
              'group_id, attendance_submitted_at, attendance_submission_kind, prayer_submitted_at, prayer_submission_kind, submission_note')
          .eq('week_id', weekId)
          .inFilter('group_id', groupIdsForWeek);
      for (final row in List<Map<String, dynamic>>.from(submissionResponse)) {
        final groupId = row['group_id']?.toString();
        if (groupId != null && groupId.isNotEmpty) {
          submissionByGroupId[groupId] = row;
        }
      }
    }

    // 5. 데이터를 조별로 가공
    final resultGroups = await Future.wait(groups.map((group) async {
      final groupName = group['name'];
      final groupId = group['id'];
      final groupSubmission =
          groupId == null ? null : submissionByGroupId[groupId.toString()];
      final isGroupNoMeeting = isRecordNoMeetingSubmission(
        groupSubmission,
        RecordSubmissionKind.attendance,
      );

      final groupAttendanceData = attendanceData.where((a) {
        final recordGroupId =
            a['recorded_group_id']?.toString() ?? a['group_id']?.toString();
        return recordGroupId == groupId;
      }).toList();

      final List<Map<String, dynamic>> membersWithStatus = [];

      // [기능 변경] 출석을 제출하지 않은 조: 가짜 현재 명단을 채워넣어 전부 '결석'처럼 보이게 하는 대신
      // 아예 미제출(is_submitted: false) 상태로 반환.
      // 단, 부서 전체 상단 통계(참석률 분모) 유지를 위해 total_count는 현재 조 인원으로 전달.
      if (groupAttendanceData.isEmpty) {
        int groupMemberCount;
        try {
          groupMemberCount =
              (await getGroupMembers(groupId, weekDate: weekDate)).length;
        } catch (e) {
          debugPrint(
              'GraceNoteRepository: Failed to count season group members: $e');
          groupMemberCount =
              allMembers.where((m) => m['group_name'] == groupName).length;
        }

        return {
          'id': groupId,
          'name': groupName,
          'is_submitted': isGroupNoMeeting,
          'is_group_no_meeting': isGroupNoMeeting,
          'submission_note': groupSubmission?['submission_note'],
          'present_count': 0,
          'total_count': groupMemberCount,
          'members': <Map<String, dynamic>>[],
        };
      }

      // 출석 제출 기록이 있는 조: 과거 제출된 기록(Snapshot) 기반으로만 명단을 구성.
      membersWithStatus.addAll(groupAttendanceData.map((a) {
        final dirId = a['directory_member_id'];
        final memberInfo = allMembers.firstWhere(
          (m) => m['id'] == dirId,
          orElse: () => missingMembersMap[dirId] ?? {},
        );

        // 정보가 삭제된 성도여도 고유 식별 명단을 위해 남겨둠
        return {
          if (memberInfo.isNotEmpty) ...memberInfo else 'id': dirId,
          'person_id': a['person_id'] ?? memberInfo['person_id'],
          'status': a['status'],
          'source': 'snapshot',
        };
      }));

      final presentCount = membersWithStatus
          .where((m) => m['status'] == 'present' || m['status'] == 'late')
          .length;

      return {
        'id': groupId,
        'name': groupName,
        'is_submitted': true,
        'is_group_no_meeting': isGroupNoMeeting,
        'submission_note': groupSubmission?['submission_note'],
        'present_count': presentCount,
        'total_count': membersWithStatus.length,
        'members': membersWithStatus,
      };
    }).toList());

    return {'groups': resultGroups};
  }

  // 기도 상호작용 (기도하기, 보관하기) 토글
  Future<void> togglePrayerInteraction({
    required String prayerId,
    required String profileId,
    required String type, // 'pray' or 'save'
  }) async {
    final existing = await _supabase
        .from('prayer_interactions')
        .select()
        .eq('prayer_id', prayerId)
        .eq('profile_id', profileId)
        .eq('interaction_type', type)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('prayer_interactions')
          .delete()
          .eq('id', existing['id']);
    } else {
      await _supabase.from('prayer_interactions').insert({
        'prayer_id': prayerId,
        'profile_id': profileId,
        'interaction_type': type,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getPrayerInteractions(
      String profileId) async {
    final response = await _supabase
        .from('prayer_interactions')
        .select('prayer_id, interaction_type')
        .eq('profile_id', profileId);
    return List<Map<String, dynamic>>.from(response);
  }

  // Directory Member ID로 단일 멤버 조회
  Future<Map<String, dynamic>?> getDirectoryMember(
      String directoryMemberId) async {
    try {
      final res = await _supabase
          .from('member_directory')
          .select()
          .eq('id', directoryMemberId)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('GraceNoteRepository: Error in getDirectoryMember: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getSavedPrayers(String profileId) async {
    final response = await _supabase.from('prayer_interactions').select('''
          interaction_type,
          prayer_entries:prayer_id (
            id,
            content,
            updated_at,
            directory_member_id,
            member_directory:directory_member_id (
              full_name,
              group_name,
              profile_id,
              person_id,
              family_name
            )
          )
        ''').eq('profile_id', profileId).order('created_at', ascending: false);

    final interactions = List<Map<String, dynamic>>.from(response);
    final prayers = interactions
        .map((interaction) => interaction['prayer_entries'])
        .whereType<Map>()
        .map((prayer) => Map<String, dynamic>.from(prayer))
        .toList();

    final enrichedPrayers =
        await _enrichPrayerRowsWithPhase2MemberInfo(prayers);
    final enrichedById = {
      for (final prayer in enrichedPrayers)
        if (prayer['id'] != null) prayer['id'].toString(): prayer
    };

    return interactions.map((interaction) {
      final prayer = interaction['prayer_entries'];
      if (prayer is! Map || prayer['id'] == null) return interaction;
      return {
        ...interaction,
        'prayer_entries': enrichedById[prayer['id'].toString()] ??
            Map<String, dynamic>.from(prayer),
      };
    }).toList();
  }

  // 특정 멤버의 전체 기도제목 히스토리 가져오기 (타임라인용)
  Future<List<Map<String, dynamic>>> getMemberPrayerHistory(
      String directoryMemberId,
      {int? page,
      int? pageSize}) async {
    debugPrint(
        'GraceNoteRepository: Fetching history for directoryMemberId: $directoryMemberId');

    // 1. Find the profile_id or identifiers for the given member
    final memberRes = await _supabase
        .from('member_directory')
        .select('profile_id, full_name, phone, church_id')
        .eq('id', directoryMemberId)
        .maybeSingle();

    if (memberRes == null) {
      debugPrint(
          'GraceNoteRepository: Member entry not found for history query: $directoryMemberId');
      return [];
    }

    final String? profileId = memberRes['profile_id'];
    final String fullName = memberRes['full_name'];
    final String? phone = memberRes['phone'];
    final String churchId = memberRes['church_id'];

    // 2. Find all directory member IDs associated with this person.
    // Phase 2 person linkage is authoritative for read expansion. Legacy
    // profile/phone matching stays as fallback for old rows not backfilled yet.
    Set<String> allIdSet =
        await _getRelatedDirectoryIdsByPhase2Person(directoryMemberId);

    if (allIdSet.length == 1) {
      var relatedQuery = _supabase.from('member_directory').select('id');

      if (profileId != null) {
        relatedQuery = relatedQuery.eq('profile_id', profileId);
      } else if (phone != null && phone.isNotEmpty) {
        relatedQuery = relatedQuery
            .eq('full_name', fullName)
            .eq('phone', phone)
            .eq('church_id', churchId);
      } else {
        relatedQuery = relatedQuery.eq('id', directoryMemberId);
      }

      final relatedMembers = await relatedQuery;
      allIdSet.addAll(
          List<String>.from(relatedMembers.map((m) => m['id'] as String)));
    }

    final List<String> allIds = allIdSet.toList();
    debugPrint(
        'GraceNoteRepository: Related directory IDs for person: $allIds');

    // 3. Fetch published prayers for those IDs (exclude drafts)
    var query = _supabase
        .from('prayer_entries')
        .select('''
          *,
          weeks(week_date),
          member:member_directory!directory_member_id(group_name)
        ''')
        .inFilter('directory_member_id', allIds)
        .eq('status', 'published')
        .order('first_published_at', ascending: false);

    if (page != null && pageSize != null) {
      final start = page * pageSize;
      final end = start + pageSize - 1;
      query = query.range(start, end);
    }

    final response = await query;

    final result = await _enrichPrayerRowsWithPhase2MemberInfo(
        List<Map<String, dynamic>>.from(response));
    debugPrint(
        'GraceNoteRepository: Found ${result.length} history entries (page $page)');
    return result;
  }

  Future<void> deleteWeek(String weekId) async {
    await _supabase.from('weeks').update({'is_active': false}).eq('id', weekId);
  }

  // 기도제목 검색 (이름 또는 내용)
  Future<List<Map<String, dynamic>>> searchPrayers({
    required String churchId,
    String? departmentId,
    String? groupId,
    DateTime? date,
    String? searchTerm,
  }) async {
    dynamic query = _supabase.from('prayer_entries').select('''
          *,
          weeks(week_date),
          member_directory!directory_member_id(full_name, family_name, spouse_name, person_id, group_name, profile_id)
        ''').eq('status', 'published');

    // 1. 날짜 필터 (선택된 경우만)
    if (date != null) {
      final dateStr = date.toIso8601String().split('T')[0];
      query = query.eq('weeks.week_date', dateStr);
    }

    // 2. 조 필터 (전체가 아닌 경우만)
    if (groupId != null && groupId != 'all') {
      query = query.eq('group_id', groupId);
    } else if (departmentId != null) {
      // 특정 조가 지정되지 않았더라도 부서 내의 조들로 제한
      final groups = await getGroupsInDepartment(departmentId);
      final groupIds = groups.map((g) => g['id'] as String).toList();
      if (groupIds.isNotEmpty) {
        query = query.inFilter('group_id', groupIds);
      }
    }

    // 3. 검색어 필터 (이름 또는 내용)
    if (searchTerm != null && searchTerm.trim().isNotEmpty) {
      final term = '%${searchTerm.trim()}%';

      // 1단계: Phase 2 person 기준으로 이름 검색 후 관련 legacy directory ID 확보.
      // 검색 자체는 여전히 prayer_entries.directory_member_id로 필터링해야 하므로
      // person_id -> member_profiles.member_directory_id로 확장한다.
      final phase2NameResponse = await _supabase
          .from('member_profiles')
          .select('person_id, member_directory_id, people!inner(church_id)')
          .eq('people.church_id', churchId)
          .ilike('full_name', term);

      final phase2Matches = List<Map<String, dynamic>>.from(phase2NameResponse);
      final matchingPersonIds = phase2Matches
          .map((profile) => profile['person_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final Set<String> matchingDirectoryIds = phase2Matches
          .map((profile) => profile['member_directory_id']?.toString())
          .whereType<String>()
          .toSet();

      if (matchingPersonIds.isNotEmpty) {
        final relatedProfiles = await _supabase
            .from('member_profiles')
            .select('member_directory_id')
            .inFilter('person_id', matchingPersonIds)
            .not('member_directory_id', 'is', null);

        matchingDirectoryIds.addAll(
            List<Map<String, dynamic>>.from(relatedProfiles)
                .map((profile) => profile['member_directory_id']?.toString())
                .whereType<String>());
      }

      if (matchingDirectoryIds.isEmpty) {
        final legacyNameSearchResponse = await _supabase
            .from('member_directory')
            .select('id')
            .eq('church_id', churchId)
            .ilike('full_name', term);

        matchingDirectoryIds.addAll((legacyNameSearchResponse as List)
            .map((m) => m['id']?.toString())
            .whereType<String>());
      }

      if (matchingDirectoryIds.isNotEmpty) {
        // 이름 매칭되는 사람이 있는 경우: (내용 검색 OR ID 목록 포함)
        final idList = matchingDirectoryIds.join(',');
        query =
            query.or('content.ilike.$term,directory_member_id.in.($idList)');
      } else {
        // 이름 매칭되는 사람이 없는 경우: 내용만 검색
        query = query.ilike('content', term);
      }
    }

    // updated_at 대신 week_date 기준으로 정렬 (주차별 정기적인 흐름 확인을 위해)
    final response = await query
        .order('week_date', referencedTable: 'weeks', ascending: false)
        .order('family_name',
            referencedTable: 'member_directory',
            ascending: true,
            nullsFirst: false)
        .order('full_name',
            referencedTable: 'member_directory', ascending: true)
        .order('id', ascending: true)
        .limit(50);
    return _enrichPrayerRowsWithPhase2MemberInfo(
        List<Map<String, dynamic>>.from(response));
  }

  // 프로필 정보 업데이트
  Future<void> updateProfile(
      String profileId, Map<String, dynamic> data) async {
    await _supabase.from('profiles').update(data).eq('id', profileId);
  }

  // 로그아웃
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // [NEW] 온보딩 미완료 유저 스스로 계정 삭제 (중복 계정 충돌 시 등)
  Future<void> cancelRegistration() async {
    try {
      await _supabase.rpc('delete_self_in_onboarding');
      await signOut(); // 삭제 후 로컬 세션도 정리
    } catch (e) {
      debugPrint('GraceNoteRepository: Error in cancelRegistration: $e');
      // 이미 삭제되었거나 권한 에러인 경우 그냥 로그아웃 시도
      await signOut();
    }
  }

  // SMS 인증 요청
  Future<void> sendVerificationSMS(String phone) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-sms',
        body: {'phone': phone},
      );

      if (response.status != 200) {
        final error =
            response.data['message'] ?? response.data['error'] ?? '인증번호 발송 실패';
        throw Exception(error);
      }
    } on FunctionException catch (e) {
      _handleFunctionException(e);
    }
  }

  // SMS 인증 확인 및 매칭 조회
  Future<Map<String, dynamic>> verifySMS(String phone, String code,
      {String? fullName}) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-sms',
        body: {
          'phone': phone,
          'code': code,
          if (fullName != null) 'fullName': fullName,
        },
      );

      if (response.status != 200) {
        final error = response.data['error'] ?? '인증 확인 실패';
        throw Exception(error);
      }

      return Map<String, dynamic>.from(response.data);
    } on FunctionException catch (e) {
      _handleFunctionException(e);
      rethrow; // Should not reach here due to helper throwing
    }
  }

  void _handleFunctionException(FunctionException e) {
    if (e.details is Map) {
      final details = e.details as Map;
      if (details['error'] == 'account_exists') {
        throw AccountExistsException(
          message: details['message'] ?? '이미 가입된 전화번호입니다.',
          maskedEmail: details['masked_email'],
          fullName: details['full_name'],
        );
      }
      final error = details['message'] ?? details['error'] ?? '서버 오류가 발생했습니다.';
      throw Exception(error);
    }
    throw Exception(e.toString());
  }

  // 성도의 등반 진행도 (출석 횟수) 조회
  Future<int> getMemberClimbingProgress(
      String directoryMemberId, String groupId) async {
    final response = await _supabase
        .from('attendance')
        .select('id')
        .eq('directory_member_id', directoryMemberId)
        .eq('group_id', groupId)
        .eq('status', 'present');

    return (response as List).length;
  }

  // 그룹 정보 업데이트 (이름, 새가족 등반 기준 등)
  Future<void> updateGroup(String groupId, Map<String, dynamic> data) async {
    await _supabase.from('groups').update(data).eq('id', groupId);
  }

  // 일요일로 스냅 (weeks 테이블과 동일 규칙)
  String _snapToSundayStr(DateTime date) {
    final sunday = date.subtract(Duration(days: date.weekday % 7));
    return '${sunday.year}-${sunday.month.toString().padLeft(2, '0')}-${sunday.day.toString().padLeft(2, '0')}';
  }

  Future<NoMeetingDayModel?> getNoMeetingDay(
      String departmentId, DateTime weekDate) async {
    if (departmentId.isEmpty) return null;
    final dateStr = _snapToSundayStr(weekDate);
    final response = await _supabase
        .from('no_meeting_days')
        .select()
        .eq('department_id', departmentId)
        .eq('week_date', dateStr)
        .maybeSingle();
    if (response == null) return null;
    return NoMeetingDayModel.fromJson(response);
  }

  Future<void> setNoMeetingDay({
    required String departmentId,
    required DateTime weekDate,
    required String reason,
    required String createdBy,
  }) async {
    final dateStr = _snapToSundayStr(weekDate);
    await _supabase.from('no_meeting_days').upsert({
      'department_id': departmentId,
      'week_date': dateStr,
      'reason': reason,
      'created_by': createdBy,
    });
  }

  Future<void> cancelNoMeetingDay(
      String departmentId, DateTime weekDate) async {
    final dateStr = _snapToSundayStr(weekDate);
    await _supabase
        .from('no_meeting_days')
        .delete()
        .eq('department_id', departmentId)
        .eq('week_date', dateStr);
  }

  Future<List<NoMeetingDayModel>> getNoMeetingDaysInMonth(
      String departmentId, int year, int month) async {
    if (departmentId.isEmpty) return [];
    final startStr = '$year-${month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final endStr =
        '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    final response = await _supabase
        .from('no_meeting_days')
        .select()
        .eq('department_id', departmentId)
        .gte('week_date', startStr)
        .lte('week_date', endStr);
    return (response as List)
        .map((e) => NoMeetingDayModel.fromJson(e))
        .toList();
  }
}

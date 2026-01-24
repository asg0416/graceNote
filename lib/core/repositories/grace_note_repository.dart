import 'package:supabase_flutter/supabase_flutter.dart';
import '../error/exceptions.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class GraceNoteRepository {
  final _supabase = Supabase.instance.client;

  // 특정 날짜의 Week ID 조회 또는 생성
  // 특정 날짜의 Week ID 조회 또는 생성
  Future<String?> getOrCreateWeek(String churchId, DateTime weekDate, {bool createIfMissing = true}) async {
    if (churchId.isEmpty) return null;
    // Snap to the preceding Sunday
    final sunday = weekDate.subtract(Duration(days: weekDate.weekday % 7));
    final dateStr = sunday.toIso8601String().split('T')[0];
    
    final existing = await _supabase
        .from('weeks')
        .select('id')
        .eq('church_id', churchId)
        .eq('week_date', dateStr)
        .maybeSingle();
    
    if (existing != null) return existing['id'];
    if (!createIfMissing) return null;

    try {
      final res = await _supabase
          .from('weeks')
          .upsert({
            'church_id': churchId,
            'week_date': dateStr,
          }, onConflict: 'church_id,week_date')
          .select('id')
          .single();
      return res['id'];
    } catch (e) {
      debugPrint('GraceNoteRepository: Error in getOrCreateWeek: $e');
      // If error (e.g., uniqueness), try one last select
      final retry = await _supabase
          .from('weeks')
          .select('id')
          .eq('church_id', churchId)
          .eq('week_date', dateStr)
          .maybeSingle();
      return retry?['id'];
    }
  }

  // 특정 조원의 활성 Group Member ID 조회
  Future<String?> getActiveGroupMemberId(String groupId, String profileId) async {
    final res = await _supabase
        .from('group_members')
        .select('id')
        .eq('group_id', groupId)
        .eq('profile_id', profileId)
        .eq('is_active', true)
        .maybeSingle();
    return res?['id'];
  }

  Future<void> saveAttendanceAndPrayers({
    required List<AttendanceModel> attendanceList,
    required List<PrayerEntryModel> prayerList,
  }) async {
    // 1. Attendance Upsert (directory_member_id 기반)
    if (attendanceList.isNotEmpty) {
      // 팁: attendanceList의 각 항목에는 저장 시점의 groupId가 이미 포함되어 있어야 함
      await _supabase.from('attendance').upsert(
        attendanceList.map((e) => e.toJson()).toList(),
        onConflict: 'week_id,directory_member_id',
      );
    }

    // 2. Prayer Entries Upsert (directory_member_id 기반)
    if (prayerList.isNotEmpty) {
      await _supabase.from('prayer_entries').upsert(
        prayerList.map((e) => e.toJson()).toList(),
        onConflict: 'week_id,directory_member_id',
      );
    }
  }

  Future<Map<String, dynamic>> getWeeklyData(String groupId, String weekId) async {
    // 1. 조원 명단 정보 먼저 확보 (조인을 피하기 위해)
    final members = await getGroupMembers(groupId);

    // 2. 출석 및 기도제목 데이터 별도 조회
    // 2. 특정 주차의 출석 및 기도제목 데이터 조회 (해당 조 소속으로 기록된 데이터만)
    final attendanceTask = _supabase
        .from('attendance')
        .select()
        .eq('week_id', weekId)
        .eq('group_id', groupId); // 현재 인원(memberIds) 기준이 아닌, 해당 주차에 이 조로 기록된 데이터 기준
    
    final prayersTask = _supabase
        .from('prayer_entries')
        .select()
        .eq('week_id', weekId)
        .eq('group_id', groupId);

    final results = await Future.wait([attendanceTask, prayersTask]);
    final attendanceList = List<Map<String, dynamic>>.from(results[0]);

    // 3. 메모리 조인: 기록된 출석 데이터에 member_directory 정보 결합
    // (이동/비활성된 사람도 attendance에 기록이 있다면 보여주기 위함)
    final List<Map<String, dynamic>> attendanceWithInfo = [];
    
    // 만약 attendance 기록이 하나도 없는 주차라면 현재 멤버 기준 빈 데이터 생성
    if (attendanceList.isEmpty) {
      for (final m in members) {
        attendanceWithInfo.add({
          'week_id': weekId,
          'group_id': groupId,
          'directory_member_id': m['id'],
          'status': 'absent',
          'member_directory': m,
        });
      }
    } else {
      for (final att in attendanceList) {
        // 우선 현재 멤버 리스트에서 찾아보고, 없으면(조이동/비활성) 별도 상세 조회 필요할 수 있지만 
        // 일단 UI 안정성을 위해 attendance 리스트 기반으로 구성
        final member = members.cast<Map<String, dynamic>?>().firstWhere(
          (m) => m?['id'] == att['directory_member_id'],
          orElse: () => null,
        );
        
        attendanceWithInfo.add(<String, dynamic>{
          ...att,
          'member_directory': member ?? { 'full_name': '이동/비활성 성도', 'id': att['directory_member_id'] },
        });
      }
    }

    return {
      'attendance': attendanceWithInfo,
      'prayers': results[1],
    };
  }

  // 부서 전체의 특정 주차 데이터 가져오기 (전체 탭용)
  Future<Map<String, dynamic>> getDepartmentWeeklyData(String departmentId, String weekId) async {
    if (departmentId.isEmpty || weekId.isEmpty) return {'groups': [], 'prayers': []};
    // 1. 부서 내 모든 조 조회
    final groupsResponse = await _supabase
        .from('groups')
        .select('id, name')
        .eq('department_id', departmentId);
    
    final groups = List<Map<String, dynamic>>.from(groupsResponse);
    final groupIds = groups.map((g) => g['id'] as String).toList();

    // 2. 모든 조의 기도제목 조회
    final prayersResponse = await _supabase
        .from('prayer_entries')
        .select()
        .eq('week_id', weekId)
        .inFilter('group_id', groupIds)
        .eq('status', 'published');

    return {
      'groups': groups,
      'prayers': prayersResponse,
    };
  }

  // 부서 목록 가져오기
  Future<List<DepartmentModel>> getDepartments(String churchId) async {
    final response = await _supabase
        .from('departments')
        .select()
        .eq('church_id', churchId);
    return (response as List).map((e) => DepartmentModel.fromJson(e)).toList();
  }

  // 특정 부서의 모든 조 가져오기
  Future<List<Map<String, dynamic>>> getGroupsInDepartment(String departmentId) async {
    final response = await _supabase
        .from('groups')
        .select('id, name')
        .eq('department_id', departmentId)
        .order('name');
        
    return (response as List).map((e) => {
      'id': e['id'],
      'name': e['name'],
    }).toList();
  }

  // 프로필 ID, 이름, 또는 전화번호로 성도 명부 정보 가져오기 (가장 강력한 버전)
  Future<Map<String, dynamic>?> getMemberDirectoryEntry({
    required String profileId, 
    required String fullName,
    String? phone,
  }) async {
    final cleanName = fullName.trim();
    final cleanPhone = phone?.trim() ?? '';
    
    debugPrint('GraceNoteRepository: Seeking directory for [$cleanName] (ID: $profileId, Phone: $cleanPhone)');
    
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
        debugPrint('GraceNoteRepository: Match found by profile_id -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
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
          debugPrint('GraceNoteRepository: Match found by phone -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
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
        debugPrint('GraceNoteRepository: Match found by full_name -> DirectoryID: ${found['id']}, Name: ${found['full_name']}');
        return Map<String, dynamic>.from(found);
      }
      
      debugPrint('GraceNoteRepository: No directory entry found for [$cleanName]');
    } catch (e) {
      debugPrint('GraceNoteRepository Error in getMemberDirectoryEntry: $e');
    }
    
    debugPrint('GraceNoteRepository: CRITICAL - No entry found in member_directory for $cleanName');
    return null;
  }

  // 특정 조의 멤버 목록 가져오기 (성도 명부 기준 - 메모리 조인 방식)
  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    // 1. 조 정보 가져오기
    final groupResponse = await _supabase
        .from('groups')
        .select('church_id, department_id, name')
        .eq('id', groupId)
        .single();
    
    final groupName = groupResponse['name'];
    final churchId = groupResponse['church_id'];
    final departmentId = groupResponse['department_id'];

    // 2. 명부 데이터 가져오기
    final directoryResponse = await _supabase
        .from('member_directory')
        .select()
        .eq('church_id', churchId)
        .eq('department_id', departmentId)
        .eq('group_name', groupName)
        .eq('is_active', true);
        
    final membersList = List<Map<String, dynamic>>.from(directoryResponse);
    if (membersList.isEmpty) return [];

    // 3. 연동된 프로필 ID 목록 확보
    final profileIds = membersList
        .map((m) => m['profile_id'])
        .where((id) => id != null)
        .cast<String>()
        .toList();

    // 4. 해당 프로필들의 정보와 group_members 정보 가져오기
    // profile_id가 있는 경우 해당 ID들로 조회, 없으면 이름 매칭을 위해 부서 전체(혹은 빈 리스트) 대신 
    // 이름 목록으로 필터링하여 가져옴
    final List<Map<String, dynamic>> allProfiles;
    if (profileIds.isNotEmpty) {
      final profilesResponse = await _supabase
          .from('profiles')
          .select('*, group_members(*)')
          .inFilter('id', profileIds);
      allProfiles = List<Map<String, dynamic>>.from(profilesResponse);
    } else {
      allProfiles = [];
    }

    // 이름으로만 존재하는 (미연동) 프로필들도 추가 조회 (안전장치)
    final missingNames = membersList
        .where((m) => m['profile_id'] == null)
        .map((m) => m['full_name'] as String)
        .toList();
    
    if (missingNames.isNotEmpty) {
      final extraProfilesResponse = await _supabase
          .from('profiles')
          .select('*, group_members(*)')
          .eq('church_id', churchId)
          .eq('department_id', departmentId)
          .inFilter('full_name', missingNames);
      allProfiles.addAll(List<Map<String, dynamic>>.from(extraProfilesResponse));
    }

    // 5. 메모리에서 조인 수행
    return membersList.map<Map<String, dynamic>>((dir) {
      final pId = dir['profile_id'];
      final name = dir['full_name'];
      
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
          (p) => p?['full_name'] == name && p?['id'] != null, // 다른 사람과 겹치지 않게 조심
          orElse: () => null,
        );
      }
      
      String? groupMemberId;
      if (profile != null && profile['group_members'] != null) {
        final gMembers = profile['group_members'] as List;
        final match = gMembers.firstWhere((gm) => gm['group_id'] == groupId, orElse: () => null);
        groupMemberId = match?['id'];
      }

      return <String, dynamic>{
        ...dir,
        'profiles': profile,
        'profile_id': profile?['id'] ?? pId, // 프로필을 못 찾더라도 명부의 pId는 유지
        'group_member_id': groupMemberId,
      };
    }).toList();
  }

  // 부서 설정 업데이트
  Future<void> updateDepartmentSettings(String deptId, Map<String, dynamic> settings) async {
    await _supabase
        .from('departments')
        .update(settings)
        .eq('id', deptId);
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
        final existingFamily = await _supabase.from('families')
            .select('id')
            .eq('church_id', churchId!)
            .eq('name', matchedData['family_name'])
            .maybeSingle();
        
        if (existingFamily != null) {
          familyId = existingFamily['id'];
        } else {
          final newFamily = await _supabase.from('families').insert({
            'church_id': churchId,
            'department_id': departmentId,
            'name': matchedData['family_name'],
          }).select('id').single();
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

    await _supabase.from('profiles').upsert(updateData, onConflict: 'id');

    // 3. 소그룹(조) 가입 (groupId가 없을 경우 matchedData에서 찾기)
    String? finalGroupId = groupId;
    if (finalGroupId == null && matchedData != null && matchedData['group_name'] != null && churchId != null && departmentId != null) {
      final existingGroup = await _supabase.from('groups')
          .select('id')
          .eq('church_id', churchId)
          .eq('department_id', departmentId)
          .eq('name', matchedData['group_name'])
          .maybeSingle();
      if (existingGroup != null) {
        finalGroupId = existingGroup['id'];
      }
    }

    if (finalGroupId != null) {
      await _supabase.from('group_members').upsert({
        'group_id': finalGroupId,
        'profile_id': profileId,
        'role_in_group': matchedData?['role_in_group'] ?? 'member',
        'is_active': true,
      }, onConflict: 'group_id,profile_id');
    }

    // 4. member_directory 레코드 완료 처리
    if (matchedData != null && matchedData['id'] != null) {
      await _supabase.from('member_directory')
          .update({
            'is_linked': true,
            'profile_id': profileId,
          })
          .eq('id', matchedData['id']);
    }
  }

  // 소셜 로그인 (Kakao, Google)
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    // [WEB FIX] Use actual location for Web, deep link for Mobile
    final String? redirectTo = kIsWeb 
        ? null // Uses Site URL configured in Supabase (e.g., localhost:8080)
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

  // 명부에 새 멤버 추가
  Future<void> addDirectoryMember(Map<String, dynamic> data) async {
    await _supabase.from('member_directory').insert(data);
  }

  // 명부 멤버 정보 수정
  Future<void> updateDirectoryMember(String id, Map<String, dynamic> data) async {
    await _supabase.from('member_directory').update(data).eq('id', id);
  }

  // 명부 멤버 활성화/비활성화 토글
  Future<void> toggleMemberActivation(String id, bool isActive) async {
    await _supabase.from('member_directory').update({'is_active': isActive}).eq('id', id);
  }

  // 명부 멤버 제거
  Future<void> deleteDirectoryMember(String id) async {
    await _supabase.from('member_directory').delete().eq('id', id);
  }

  // 특정 조의 주차별 출석 히스토리 및 통계 가져오기 (년/월 필터링 추가)
  Future<List<Map<String, dynamic>>> getGroupAttendanceHistory(String groupId, {int? year, int? month, int limit = 6}) async {
    // 1. 조 정보 가져오기
    final group = await _supabase
        .from('groups')
        .select('church_id')
        .eq('id', groupId)
        .single();
    
    final churchId = group['church_id'];

    // 2. 주차 정보 가져오기
    var query = _supabase
        .from('weeks')
        .select('id, week_date')
        .eq('church_id', churchId);
    
    if (year != null && month != null) {
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
      query = query
          .gte('week_date', startOfMonth.toIso8601String())
          .lte('week_date', endOfMonth.toIso8601String());
    }

    final weeksResponse = await query
        .order('week_date', ascending: false)
        .limit(limit);
    
    final weeks = List<Map<String, dynamic>>.from(weeksResponse);
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
      final weekAttendance = attendanceData.where((a) => a['week_id'] == weekId).toList();
      
      final presentCount = weekAttendance.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
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
  Future<List<Map<String, dynamic>>> getDepartmentAttendanceHistory(String departmentId, {int? year, int? month, int limit = 6}) async {
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
        .eq('church_id', churchId);
    
    if (year != null && month != null) {
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
      query = query
          .gte('week_date', startOfMonth.toIso8601String())
          .lte('week_date', endOfMonth.toIso8601String());
    }

    final weeksResponse = await query
        .order('week_date', ascending: false)
        .limit(limit);
    
    final weeks = List<Map<String, dynamic>>.from(weeksResponse);
    final weekIds = weeks.map((w) => w['id'] as String).toList();

    if (weekIds.isEmpty) return [];

    // 3. 부서 내 모든 조 ID 확보
    final groupsResponse = await _supabase
        .from('groups')
        .select('id')
        .eq('department_id', departmentId);
    final groupIds = (groupsResponse as List).map((g) => g['id'] as String).toList();

    // [NEW] 부서 내 전체 활성 멤버 수 조회 (안정적인 통계를 위해)
    final directoryResponse = await _supabase
        .from('member_directory')
        .select('id')
        .eq('department_id', departmentId)
        .eq('is_active', true);
    final totalMembersInDept = (directoryResponse as List).length;

    // 4. 출석 데이터 조회
    final attendanceResponse = await _supabase
        .from('attendance')
        .select('week_id, status')
        .inFilter('week_id', weekIds)
        .inFilter('group_id', groupIds);
    
    final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);

    return weeks.map((week) {
      final weekId = week['id'];
      final weekAttendance = attendanceData.where((a) => a['week_id'] == weekId).toList();
      
      final presentCount = weekAttendance.where((a) => a['status'] == 'present' || a['status'] == 'late').length;
      // 출석을 제출하지 않은 조가 있더라도 전체 인원수는 부서 총원으로 고정
      final totalCount = totalMembersInDept;
      
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
  Future<Map<String, dynamic>> getDepartmentWeeklyAttendanceDetails(String departmentId, String weekId) async {
    if (departmentId.isEmpty || weekId.isEmpty) return {'groups': []};

    // 1. 부서 내 모든 조 조회
    final groupsResponse = await _supabase
        .from('groups')
        .select('id, name')
        .eq('department_id', departmentId)
        .order('name');
    final groups = List<Map<String, dynamic>>.from(groupsResponse);

    // 2. 부서 내 모든 멤버 조회 (매칭용)
    final directoryResponse = await _supabase
        .from('member_directory')
        .select('id, full_name, group_name, profile_id')
        .eq('department_id', departmentId)
        .eq('is_active', true);
    final allMembers = List<Map<String, dynamic>>.from(directoryResponse);

    // 3. 해당 주차의 출석 데이터 조회
    final attendanceResponse = await _supabase
        .from('attendance')
        .select('directory_member_id, status')
        .eq('week_id', weekId);
    final attendanceData = List<Map<String, dynamic>>.from(attendanceResponse);

    // 4. 데이터를 조별로 가공
    final resultGroups = groups.map((group) {
      final groupName = group['name'];
      final groupId = group['id'];
      
      // 해당 조 멤버 필터링
      final groupMembers = allMembers.where((m) => m['group_name'] == groupName).toList();
      
      // 멤버별 출석 상태 매핑
      final membersWithStatus = groupMembers.map((member) {
        final attendance = attendanceData.firstWhere(
          (a) => a['directory_member_id'] == member['id'],
          orElse: () => {'status': 'absent'},
        );
        return {
          ...member,
          'status': attendance['status'],
        };
      }).toList();

      final presentCount = membersWithStatus.where((m) => m['status'] == 'present' || m['status'] == 'late').length;

      return {
        'id': groupId,
        'name': groupName,
        'present_count': presentCount,
        'total_count': membersWithStatus.length,
        'members': membersWithStatus,
      };
    }).toList();

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

  Future<List<Map<String, dynamic>>> getPrayerInteractions(String profileId) async {
    final response = await _supabase
        .from('prayer_interactions')
        .select('prayer_id, interaction_type')
        .eq('profile_id', profileId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getSavedPrayers(String profileId) async {
    final response = await _supabase
        .from('prayer_interactions')
        .select('''
          interaction_type,
          prayer_entries:prayer_id (
            id,
            content,
            updated_at,
            member_directory:directory_member_id (
              full_name
            )
          )
        ''')
        .eq('profile_id', profileId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // 특정 멤버의 전체 기도제목 히스토리 가져오기 (타임라인용)
  Future<List<Map<String, dynamic>>> getMemberPrayerHistory(String directoryMemberId) async {
    debugPrint('GraceNoteRepository: Fetching history for directoryMemberId: $directoryMemberId');
    
    // 1. Find the person_id or identifiers for the given member
    final memberRes = await _supabase
        .from('member_directory')
        .select('person_id, full_name, phone, church_id')
        .eq('id', directoryMemberId)
        .maybeSingle();

    if (memberRes == null) {
      debugPrint('GraceNoteRepository: Member entry not found for history query: $directoryMemberId');
      return [];
    }

    final String? personId = memberRes['person_id'];
    final String fullName = memberRes['full_name'];
    final String? phone = memberRes['phone'];
    final String churchId = memberRes['church_id'];

    // 2. Find all directory member IDs associated with this person
    var relatedQuery = _supabase.from('member_directory').select('id');
    
    if (personId != null) {
      relatedQuery = relatedQuery.eq('person_id', personId);
    } else if (phone != null && phone.isNotEmpty) {
      relatedQuery = relatedQuery.eq('full_name', fullName).eq('phone', phone).eq('church_id', churchId);
    } else {
      relatedQuery = relatedQuery.eq('id', directoryMemberId);
    }

    final relatedMembers = await relatedQuery;
    final List<String> allIds = List<String>.from(relatedMembers.map((m) => m['id'] as String));
    debugPrint('GraceNoteRepository: Related directory IDs for person: $allIds');

    // 3. Fetch all prayers for those IDs
    final response = await _supabase
        .from('prayer_entries')
        .select('''
          *,
          weeks(week_date),
          member:member_directory!directory_member_id(group_name)
        ''')
        .inFilter('directory_member_id', allIds)
        .order('week_date', referencedTable: 'weeks', ascending: false);
    
    final result = List<Map<String, dynamic>>.from(response);
    debugPrint('GraceNoteRepository: Found ${result.length} history entries');
    return result;
  }

  Future<void> deleteWeek(String weekId) async {
    await _supabase.from('weeks').delete().eq('id', weekId);
  }

  // 기도제목 검색 (이름 또는 내용)
  Future<List<Map<String, dynamic>>> searchPrayers({
    required String churchId,
    String? departmentId,
    String? groupId,
    DateTime? date,
    String? searchTerm,
  }) async {
    var query = _supabase
        .from('prayer_entries')
        .select('''
          *,
          weeks!inner(week_date),
          member_directory!inner(full_name, group_name)
        ''')
        .eq('status', 'published');

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
      
      // 1단계: 성도 명부에서 이름 검색하여 ID 목록 확보
      final nameSearchResponse = await _supabase
          .from('member_directory')
          .select('id')
          .eq('church_id', churchId)
          .ilike('full_name', term);
      
      final List<String> matchingDirectoryIds = (nameSearchResponse as List)
          .map((m) => m['id'].toString())
          .toList();

      if (matchingDirectoryIds.isNotEmpty) {
        // 이름 매칭되는 사람이 있는 경우: (내용 검색 OR ID 목록 포함)
        final idList = matchingDirectoryIds.join(',');
        query = query.or('content.ilike.$term,directory_member_id.in.($idList)');
      } else {
        // 이름 매칭되는 사람이 없는 경우: 내용만 검색
        query = query.ilike('content', term);
      }
    }

    // updated_at 대신 week_date 기준으로 정렬 (주차별 정기적인 흐름 확인을 위해)
    // Supabase Flutter에서 foreignTable 정렬은 아래와 같이 수행함
    final response = await query
        .order('week_date', referencedTable: 'weeks', ascending: false)
        .order('updated_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  // 프로필 정보 업데이트
  Future<void> updateProfile(String profileId, Map<String, dynamic> data) async {
    await _supabase.from('profiles').update(data).eq('id', profileId);
  }

  // 로그아웃
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // SMS 인증 요청
  Future<void> sendVerificationSMS(String phone) async {
    final response = await _supabase.functions.invoke(
      'send-sms',
      body: {'phone': phone},
    );

    if (response.status != 200) {
      if (response.data != null && response.data['error'] == 'account_exists') {
        throw AccountExistsException(
          message: response.data['message'] ?? '이미 가입된 전화번호입니다.',
          maskedEmail: response.data['masked_email'],
          fullName: response.data['full_name'],
        );
      }
      final error = response.data['message'] ?? response.data['error'] ?? '인증번호 발송 실패';
      throw Exception(error);
    }
  }

  // SMS 인증 확인 및 매칭 조회
  Future<Map<String, dynamic>> verifySMS(String phone, String code) async {
    final response = await _supabase.functions.invoke(
      'verify-sms',
      body: {'phone': phone, 'code': code},
    );

    if (response.status != 200) {
      final error = response.data['error'] ?? '인증 확인 실패';
      throw Exception(error);
    }

    return Map<String, dynamic>.from(response.data);
  }
}

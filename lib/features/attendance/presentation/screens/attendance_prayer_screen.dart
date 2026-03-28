import 'dart:math' as math;
import 'dart:async' show Timer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/widgets/app_skeleton.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/services/ai_service.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_check_screen.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:grace_note/core/widgets/ai_processing_loader.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:grace_note/core/utils/route_util.dart';
import 'prayer_share_screen.dart';

import 'package:grace_note/core/providers/user_role_provider.dart';

class AttendancePrayerScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const AttendancePrayerScreen({super.key, this.isActive = true});

  @override
  ConsumerState<AttendancePrayerScreen> createState() => _AttendancePrayerScreenState();
}
class _AttendancePrayerScreenState extends ConsumerState<AttendancePrayerScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _isRefining = false;
  bool _isLoading = false;
  bool _isFetching = false;
  bool _hasExistingData = false;
  bool _isInitialized = false;
  bool _isCheckScreenShowing = false;
  DateTime? _lastCheckedWeek; // [FIX] 주차별 팝업 트리거 방지 (동일 주차 재진입/resume 시 팝업 억제)
  DateTime? _currentDataWeek; // [FIX] 데이터 페치 시 주차가 진짜 바뀌었는지 추적하여 텍스트 덮어쓰기 여부 결정
  final List<List<Map<String, dynamic>>> _undoStack = [];

  List<Map<String, dynamic>> _members = [];
  final Map<String, TextEditingController> _controllers = {};
  final ShadPopoverController _popoverController = ShadPopoverController();
  String? _currentGroupId;
  Timer? _editingDebounceTimer;
  String? _currentChurchId;

  @override
  void dispose() {
    _editingDebounceTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.removeListener(_onTextChanged);
      controller.dispose();
    }
    _popoverController.dispose();
    // 화면을 떠날 때 editing guard 해제
    // (WidgetRef는 dispose 후 접근 불가하므로 try-catch)
    try {
      ref.read(isUserEditingProvider.notifier).state = false;
    } catch (_) {}
    super.dispose();
  }

  /// 텍스트 입력 시 editing guard 활성화 (3초간 입력 없으면 자동 해제)
  void _onTextChanged() {
    ref.read(isUserEditingProvider.notifier).state = true;
    _editingDebounceTimer?.cancel();
    _editingDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) ref.read(isUserEditingProvider.notifier).state = false;
    });
  }

  /// 새로 생성된 controller에 editing guard 리스너를 등록
  void _attachEditingGuard(TextEditingController controller) {
    controller.addListener(_onTextChanged);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(AttendancePrayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _checkAndShowAttendancePopup();
    }
  }

  void _checkAndShowAttendancePopup() {
    if (!mounted) return;
    
    // [FIX] 사용자가 기도제목을 입력 중이면 출석체크 팝업 표시(포커스 뺏김) 방지
    final isEditing = ref.read(isUserEditingProvider);
    if (isEditing) return;

    if (_members.isEmpty || _isCheckScreenShowing || _isLoading || _isFetching) return;
    
    // [FIX] 이미 팝업 처리를 한 주차이면 다시 띄우지 않음 (백그라운드 복귀나 부모 위젯 재빌드 시 무한 팝업 방지)
    final currentWeek = ref.read(attendanceSelectedWeekProvider);
    if (_lastCheckedWeek == currentWeek) return;

    final hasAnyPresence = _members.any((m) => m['isPresent'] == true);
    if (!hasAnyPresence) {
      _isCheckScreenShowing = true;
      _lastCheckedWeek = currentWeek; // 이번 주차 팝업 방어막 설정
      Future.microtask(() => _launchAttendanceCheck());
    } else {
      _lastCheckedWeek = currentWeek; // 출석이 이미 있으면 팝업 불필요
    }
  }

  Future<void> _refreshData() async {
    // [FIX] 주차 변경이나 새로고침 시 이전에 타이핑하던 상태(3초 딜레이)를 해제하여 정상적인 팝업 표시 허용
    try {
      if (mounted) {
        ref.read(isUserEditingProvider.notifier).state = false;
        _editingDebounceTimer?.cancel();
      }
    } catch (_) {}

    // [FIX] controller를 무조건 clear하지 않음 — 서버 fetch 후 동기화하여 사용자 입력 보호
    
    final groups = await ref.read(userGroupsProvider.future);
    final activeMembership = ref.read(activeMembershipProvider);

    if (activeMembership != null) {
      // 선택된 그룹이 있으면 그 그룹 사용
      _currentGroupId = activeMembership.groupId;
      _currentChurchId = activeMembership.churchId ?? groups.firstWhere((g) => g['group_id'] == activeMembership.groupId, orElse: () => {})['church_id'];
    } else if (groups.isNotEmpty) {
      // 선택된 그룹이 없으면 첫 번째 그룹 사용
      _currentGroupId = groups.first['group_id'];
      _currentChurchId = groups.first['church_id'];
    }

    if (_currentGroupId != null && _currentChurchId != null) {
      await _fetchInitialData(_currentChurchId!, _currentGroupId!);
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchInitialData(String churchId, String groupId) async {
    if (_isFetching) return;
    _isFetching = true;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final selectedDate = ref.read(attendanceSelectedWeekProvider);
      final weekIdResult = await repo.getOrCreateWeek(churchId, selectedDate, createIfMissing: true);
      
      final bool isWeekChanged = _currentDataWeek != selectedDate;
      _currentDataWeek = selectedDate;
      final weekId = weekIdResult;
      
      // [FIX] weekId가 없더라도 멤버 목록은 항상 가져옴 (빈 화면 방지)
      final membersData = await repo.getGroupMembers(groupId);
      
      final List<Map<String, dynamic>> existingAttendance;
      final List<Map<String, dynamic>> existingPrayers;
      
      if (weekId != null) {
        final weeklyData = await repo.getWeeklyData(groupId, weekId);
        existingAttendance = List<Map<String, dynamic>>.from(weeklyData['attendance']);
        existingPrayers = List<Map<String, dynamic>>.from(weeklyData['prayers']);
      } else {
        existingAttendance = [];
        existingPrayers = [];
        debugPrint('AttendancePrayerScreen: weekId is null, showing default members list.');
      }

      setState(() {
        final Map<String, Map<String, dynamic>> combinedMembers = {};
        
        // 1. 명단 기본 구조 생성 (member_directory 기준)
        for (final m in membersData) {
          final directoryId = m['id'];
          combinedMembers[directoryId] = {
            'id': m['profiles']?['id'], 
            'directoryMemberId': directoryId,
            'name': m['full_name'],
            'isPresent': false,
            'prayerNote': '',
            'prayerStatus': 'initial',
            'familyId': _generateFamilyId(m['full_name'], m['spouse_name'], m['family_id'], directoryId),
            'source': 'current',
            'role_in_group': m['role_in_group'],
          };
        }

        // 2. 기록된 데이터가 있다면 덮어쓰기
        if (weekId != null) {
          for (final att in existingAttendance) {
            final directoryId = att['directory_member_id'];
            if (directoryId == null || !combinedMembers.containsKey(directoryId)) continue;
            
            final prayer = (existingPrayers as List).firstWhere(
              (p) => p['directory_member_id'] == directoryId, 
              orElse: () => <String, dynamic>{'content': '', 'status': 'initial'}
            );
            
            combinedMembers[directoryId]!['isPresent'] = att['status'] == 'present' || att['status'] == 'late';
            combinedMembers[directoryId]!['prayerNote'] = prayer['content'] ?? '';
            combinedMembers[directoryId]!['prayerStatus'] = prayer['status'] ?? 'initial';
            combinedMembers[directoryId]!['source'] = 'snapshot';
          }
        }
        
        _members = combinedMembers.values.toList();
        _hasExistingData = existingAttendance.isNotEmpty;

        for (final m in _members) {
          final directoryId = m['directoryMemberId'];
          final serverNote = m['prayerNote'] ?? '';
          if (!_controllers.containsKey(directoryId)) {
            final ctrl = TextEditingController(text: serverNote);
            _attachEditingGuard(ctrl);
            _controllers[directoryId] = ctrl;
          } else {
            // [FIX] 주차가 실제로 변경된 경우 무조건 덮어쓰기 (새 주차 데이터를 표시)
            if (isWeekChanged) {
               _controllers[directoryId]!.text = serverNote;
            } else {
              // 주차가 동일한데 새로고침/백그라운드 복귀된 경우:
              // 현재 사용자가 수정 중인 상태라면 덮어쓰지 않고 보호
              final currentText = _controllers[directoryId]!.text;
              if (currentText.isEmpty || currentText == m['prayerNote']) {
                _controllers[directoryId]!.text = serverNote;
              }
            }
          }
        }
        _sortMembers();
        _isLoading = false;
        _isFetching = false;
        if (widget.isActive) _checkAndShowAttendancePopup();
        
        // [NEW] 대시보드에서 넘어온 경우 자동 출석체크 열기
        if (ref.read(shouldAutoOpenAttendanceCheckProvider)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ref.read(shouldAutoOpenAttendanceCheckProvider)) {
              ref.read(shouldAutoOpenAttendanceCheckProvider.notifier).state = false;
              _launchAttendanceCheck();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('AttendancePrayerScreen: Error fetching data: $e');
      if (mounted) SnackBarUtil.showSnackBar(context, message: '데이터를 불러오지 못했습니다.', isError: true);
    } finally {
      if (mounted) setState(() { _isLoading = false; _isFetching = false; });
    }
  }

  void _sortMembers() {
    setState(() {
      _members.sort((a, b) {
        if (a['isPresent'] != b['isPresent']) return a['isPresent'] ? -1 : 1;
        if (a['familyId'] != b['familyId']) return (a['familyId'] ?? '').compareTo(b['familyId'] ?? '');
        return (a['name'] as String).compareTo(b['name'] as String);
      });
    });
  }

  String _generateFamilyId(String fullName, String? spouseName, dynamic familyId, String directoryId) {
    if (familyId != null) return familyId.toString();
    if (spouseName != null && spouseName.trim().isNotEmpty) {
      final names = [fullName, spouseName];
      names.sort();
      return 'couple_${names.join('_')}';
    }
    return 'single_$directoryId';
  }

  Future<void> _launchAttendanceCheck() async {
    final selectedDate = ref.read(attendanceSelectedWeekProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 선택된 날짜와 오늘 날짜를 비교하여 과거 주차 여부 확인 (일요일 기준이므로 < 오늘)
    final bool isPastWeek = selectedDate.isBefore(today);

    // [NEW] 새가족 그룹 여부 확인
    bool isNewFamilyGroup = false;
    final groups = ref.read(userGroupsProvider).value ?? [];
    if (_currentGroupId != null && groups.isNotEmpty) {
      final currentGroup = groups.firstWhere(
        (g) => g['group_id'] == _currentGroupId,
        orElse: () => {},
      );
      // userGroupsProvider의 데이터 구조에 따라 is_new_member_group 필드가 있을지 확인 필요
      // 만약 없다면 departmentGroupsProvider 등을 통해 확인해야 함.
      // 하지만 userGroupsProvider는 보통 join된 뷰나 rpc 결과를 가져오므로 
      // is_new_member_group 필드가 포함되어 있어야 함. 
      // (GraceNoteRepository.getUserGroups 참고)
      isNewFamilyGroup = currentGroup['is_new_member_group'] ?? false;
    }

    final result = await Navigator.of(context).push(
      SharedAxisPageRoute(
        page: AttendanceCheckScreen(
          initialMembers: _members,
          isPastWeek: isPastWeek,
          groupId: _currentGroupId,
          isNewFamilyGroup: isNewFamilyGroup,
          hasExistingData: _hasExistingData,
        ),
      ),
    );

    if (result != null && result is List<Map<String, dynamic>>) {
      final updated = result;
      setState(() {
        // 업데이트된 명단에는 있고 이전 명단에는 없는 dirId 확인 (거의 없을 테지만 방어적)
        // 업데이트된 명단에 없는 dirId는 제외된 성도이므로 컨트롤러 등에서도 삭제
        final updatedIds = updated.map((m) => m['directoryMemberId']).toSet();
        _controllers.removeWhere((id, _) => !updatedIds.contains(id));
        
        _members = updated;
        for (final m in _members) {
          final dirId = m['directoryMemberId'];
          if (_controllers.containsKey(dirId)) {
            _controllers[dirId]!.text = m['prayerNote'] ?? '';
          } else {
            final ctrl = TextEditingController(text: m['prayerNote'] ?? '');
            _attachEditingGuard(ctrl);
            _controllers[dirId] = ctrl;
          }
        }
        _sortMembers();
        _isCheckScreenShowing = false;
      });
      await _saveData(status: 'draft');
    } else {
      // 취소되거나 완료 없이 닫힌 경우
      if (mounted) setState(() => _isCheckScreenShowing = false);
    }
  }

  void _saveToHistory() {
    final snapshot = _members.map((m) => { ...m }).toList();
    _undoStack.add(snapshot);
    if (_undoStack.length > 10) _undoStack.removeAt(0);
  }

  void _undoRefinement() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        _members = _undoStack.removeLast();
        for (final m in _members) {
          final dirId = m['directoryMemberId'];
          if (_controllers.containsKey(dirId)) _controllers[dirId]!.text = m['prayerNote'] ?? '';
        }
      });
      if (mounted) SnackBarUtil.showSnackBar(context, message: '이전 상태로 되돌렸습니다.');
    }
  }

  Future<void> _refineAllPrayers() async {
    final hasAttendance = _members.any((m) => m['isPresent'] == true) || _members.any((m) => m['source'] == 'snapshot');
    if (!hasAttendance) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('출석체크 미완료'),
          content: const Text('출석체크를 먼저 진행하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('출석체크 하기')),
          ],
        ),
      );
      if (confirm == true) _launchAttendanceCheck();
      return;
    }
    setState(() => _isRefining = true);
    try {
      List<String> rawNotes = [];
      List<int> targetIndices = [];
      for (int i = 0; i < _members.length; i++) {
        final m = _members[i];
        if (m['isPresent'] && (m['prayerNote'] as String).trim().isNotEmpty) {
          rawNotes.add(m['prayerNote']);
          targetIndices.add(i);
        }
      }
      if (rawNotes.isEmpty) {
        SnackBarUtil.showSnackBar(context, message: '정리할 기도제목이 없습니다.', isError: true);
        return;
      }
      final refined = await AIService().refinePrayers(rawNotes, settings: ref.read(aiSettingsProvider));
      _saveToHistory();
      setState(() {
        for (int i = 0; i < targetIndices.length; i++) {
          if (i < refined.length) {
            final idx = targetIndices[i];
            final refinedText = refined[i];
            _members[idx]['prayerNote'] = refinedText;
            final dirId = _members[idx]['directoryMemberId'];
            if (_controllers.containsKey(dirId)) _controllers[dirId]!.text = refinedText;
          }
        }
      });
      if (mounted) SnackBarUtil.showSnackBar(context, message: 'AI가 내용을 정돈했습니다.');
    } finally {
      setState(() => _isRefining = false);
    }
  }

  Future<void> _saveData({required String status}) async {
    if (_currentChurchId == null || _currentGroupId == null) {
      SnackBarUtil.showSnackBar(context, message: '정보를 찾을 수 없습니다.', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final selectedDate = ref.read(attendanceSelectedWeekProvider);
      final weekIdResult = await repo.getOrCreateWeek(_currentChurchId!, selectedDate, createIfMissing: true);
    if (weekIdResult == null) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) SnackBarUtil.showSnackBar(context, message: '주차 정보를 확인하지 못했습니다.', isError: true);
      return;
    }
      final weekId = weekIdResult;
      final List<AttendanceModel> attendance = [];
      final List<PrayerEntryModel> prayers = [];
      for (final m in _members) {
        final dirId = m['directoryMemberId'];
        final memberId = m['id'];
        attendance.add(AttendanceModel(
          weekId: weekId,
          groupId: _currentGroupId,
          groupMemberId: m['groupMemberId'],
          directoryMemberId: dirId,
          status: m['isPresent'] ? 'present' : 'absent',
        ));
        final note = (m['prayerNote'] as String).trim();
      if (note.isNotEmpty) {
        // [FIX] 사용자가 '임시 저장'을 명시적으로 눌렀다면, 기존 상태가 published라도 draft로 변경(Unpublish)해야 함.
        // Sticky Logic 제거: final newStatus = (status == 'draft' && m['prayerStatus'] == 'published') ? 'published' : status;
        final newStatus = status; 
              
        prayers.add(PrayerEntryModel(
          weekId: weekId,
          groupId: _currentGroupId!,
          memberId: memberId,
          directoryMemberId: dirId,
          content: note,
          status: newStatus,
        ));
        
        // [UI UPDATE] 저장 후 즉시 배지를 업데이트하기 위해 로컬 상태 변경
        m['prayerStatus'] = newStatus;
      }
    }
    await repo.saveAttendanceAndPrayers(attendanceList: attendance, prayerList: prayers);
      ref.invalidate(weeklyDataProvider);
      ref.invalidate(departmentWeeklyDataProvider);
      ref.invalidate(attendanceHistoryProvider);
      
      if (mounted) setState(() => _isLoading = false);
    if (mounted) SnackBarUtil.showSnackBar(context, message: status == 'published' ? '등록되었습니다.' : '저장되었습니다.');
  } catch (e) {
    if (mounted) setState(() => _isLoading = false);
    debugPrint('Save Error: $e');
    if (mounted) SnackBarUtil.showSnackBar(context, message: '저장 중 오류가 발생했습니다.', isError: true);
  }
}

  String _formatPrayersForSharing() {
    final settings = ref.read(aiSettingsProvider);
    final selectedDate = ref.read(attendanceSelectedWeekProvider);
    final groups = ref.read(userGroupsProvider).value ?? [];
    final groupName = groups.isNotEmpty ? groups.first['group_name'] : '우리 조';
    final StringBuffer buffer = StringBuffer();
    if (settings.showDateInShare) buffer.write('${DateFormat('M/d').format(selectedDate)} ');
    final formattedGroupName = groupName.trim().endsWith('조') ? groupName : '$groupName조';
    buffer.writeln('$formattedGroupName \n');
    final icon = settings.shareHeaderIcon;

    final List<Map<String, dynamic>> processedMembers = List.from(_members);
    int i = 0;
    while (i < processedMembers.length) {
      final m = processedMembers[i];
      final note = (m['prayerNote'] as String).trim();
      if (note.isEmpty) {
        i++;
        continue;
      }

      final currentFamilyId = m['familyId'];
      List<Map<String, dynamic>> familyGroup = [m];
      int j = i + 1;

      // 부부/가족 그룹화 로직
      if (currentFamilyId != null && currentFamilyId.toString().startsWith('couple_')) {
        while (j < processedMembers.length) {
          final nextM = processedMembers[j];
          final nextNote = (nextM['prayerNote'] as String).trim();
          if (nextM['familyId'] == currentFamilyId && nextNote.isNotEmpty) {
            familyGroup.add(nextM);
            j++;
          } else {
            break;
          }
        }
      }

      final bool isIdentical = familyGroup.length > 1 && 
          familyGroup.every((fm) => (fm['prayerNote'] as String).trim() == (familyGroup[0]['prayerNote'] as String).trim());

      final bool shouldGroup = settings.alwaysGroupFamily || isIdentical;

      if (shouldGroup && familyGroup.length > 1) {
        // 이름 합치기
        final combinedNames = familyGroup.map((fm) => fm['name']).join(', ');
        buffer.writeln('$icon$combinedNames$icon');

        if (isIdentical) {
          // 동일한 경우 본문 한 번만 출력
          final entryLines = note.split('\n').where((l) => l.trim().isNotEmpty).toList();
          for (int lineIdx = 0; lineIdx < entryLines.length; lineIdx++) {
            final line = entryLines[lineIdx].trim();
            final cleanLine = line.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*', unicode: true), '');
            buffer.writeln('${lineIdx + 1}. $cleanLine');
          }
        } else {
          // 다른 경우에도 기도제목들을 합치되, 중복되는 라인은 제거하여 출력
          final Set<String> uniqueLines = {};
          for (final fm in familyGroup) {
            final fNote = (fm['prayerNote'] as String).trim();
            final entryLines = fNote.split('\n').where((l) => l.trim().isNotEmpty).toList();
            for (final line in entryLines) {
              final cleanLine = line.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*', unicode: true), '');
              uniqueLines.add(cleanLine);
            }
          }
          
          int totalLineCount = 1;
          for (final line in uniqueLines) {
            buffer.writeln('$totalLineCount. $line');
            totalLineCount++;
          }
        }
        buffer.writeln();
        i = j;
      } else {
        // 단독 출력 또는 개별 출력
        buffer.writeln('$icon${m['name']}$icon');
        final entryLines = note.split('\n').where((l) => l.trim().isNotEmpty).toList();
        for (int lineIdx = 0; lineIdx < entryLines.length; lineIdx++) {
          final line = entryLines[lineIdx].trim();
          final cleanLine = line.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*', unicode: true), '');
          buffer.writeln('${lineIdx + 1}. $cleanLine');
        }
        buffer.writeln();
        i++;
      }
    }

    return buffer.toString().trim();
  }


  @override
  Widget build(BuildContext context) {
    super.build(context); // [FIX] AutomaticKeepAliveClientMixin 요구사항
    final groupsAsync = ref.watch(userGroupsProvider);
    final activeMembership = ref.watch(activeMembershipProvider);

    ref.listen(attendanceSelectedWeekProvider, (previous, next) { if (previous != next) _refreshData(); });
    ref.listen(userGroupsProvider, (previous, next) {
       if (next.hasValue) {
         final oldId = previous?.value?.isNotEmpty == true ? previous!.value!.first['group_id'] : null;
         final newId = next.value?.isNotEmpty == true ? next.value!.first['group_id'] : null;
         // 실제 그룹 변경 시에만 리프레시 (invalidate 후 재로딩은 무시)
         if (oldId != null && newId != null && oldId != newId) _refreshData();
       }
    });

    // [FIX] 활성 멤버십(선택된 조) 변경 감지
    // previous가 null인 경우는 StateNotifier 재생성(background resume)이므로 무시
    ref.listen(activeMembershipProvider, (previous, next) {
      if (previous != null && next != null && previous.groupId != next.groupId) {
        _refreshData();
      }
    });

    ref.listen(attendanceActionProvider, (previous, next) {
      if (next != null) {
        if (next == AttendanceAction.share) {
          // [FIX] 수동 호출 시에도 일관된 애니메이션 제공을 고려할 수 있으나,
          // 여기서는 아이콘 클릭이 주 용도이므로 간단히 기존 함수를 호출하거나 직접 내비게이션 가능
          final shareText = _formatPrayersForSharing();
          if (shareText.isNotEmpty) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => PrayerShareScreen(shareText: shareText))
            );
          }
        } else if (next == AttendanceAction.addMember) {
          _launchAttendanceCheck();
        }
        Future.microtask(() => ref.read(attendanceActionProvider.notifier).state = null);
      }
    });
    if (groupsAsync.hasValue && !_isInitialized) { _isInitialized = true; Future.microtask(() => _refreshData()); }

    // [FIX] 타이틀도 선택된 그룹명으로 표시
    String groupName = '우리 조';
    if (activeMembership != null) {
      groupName = activeMembership.groupName;
    } else if (groupsAsync.value?.isNotEmpty == true) {
      groupName = groupsAsync.value!.first['group_name'] ?? '우리 조';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('${groupName.replaceAll('조', '')}조 기록', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMain, fontSize: 18)),
        leading: IconButton(
        icon: const Icon(lucide.LucideIcons.share, color: AppTheme.primaryViolet, size: 20),
        onPressed: () {
          final shareText = _formatPrayersForSharing();
          if (shareText.isEmpty) {
            SnackBarUtil.showSnackBar(context, message: '공유할 내용이 없습니다.', isError: true);
            return;
          }
          Navigator.of(context).push(
            SharedAxisPageRoute(
              page: PrayerShareScreen(shareText: shareText),
            ),
          );
        },
      ),
        actions: [
          IconButton(
            icon: const Icon(lucide.LucideIcons.userCheck, color: AppTheme.primaryViolet, size: 22), // v4 사람+체크 아이콘으로 최종 변경
            onPressed: _launchAttendanceCheck,
            tooltip: '출석 체크',
          ),
          const SizedBox(width: 8),
        ],
      ),
      // [FIX] 로컬 상태 기반 렌더링 — provider AsyncLoading 전환 시 위젯 트리 교체 방지
      body: _buildBody(),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildBody() {
    if (!_isInitialized || (_members.isEmpty && (_isLoading || _isFetching))) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: _RecordSkeleton(),
        ),
      );
    }

    if (_members.isEmpty && !_isLoading) {
      return const Center(child: Text('배정된 조가 없습니다.'));
    }

    return Stack(
      children: [
        Column(
          children: [
            _buildAIHeader(),
            if (_isRefining) const LinearProgressIndicator(backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet), minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                color: AppTheme.primaryViolet,
                child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(lerpDouble(0, 0.1, animation.value) ?? 0),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              )
                            ],
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                  );
                },
                buildDefaultDragHandles: false,
                itemCount: _members.length,
                onReorder: (oldIndex, newIndex) { setState(() { if (newIndex > oldIndex) newIndex -= 1; final item = _members.removeAt(oldIndex); _members.insert(newIndex, item); }); },
                itemBuilder: (context, index) {
                  return Container(
                    key: ValueKey(_members[index]['directoryMemberId']),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: _buildMemberCard(_members[index], index),
                  );
                },
              ),
              ),
            ),
          ],
        ),
        if (_isLoading || _isFetching) 
          Container(
            color: Colors.white.withOpacity(0.7), 
            child: const Center(child: CircularProgressIndicator())
          ),
        if (_isRefining) 
          Container(
            color: Colors.white.withOpacity(0.3), 
            child: const Center(child: AIProcessingLoader(size: 100, message: '기도제목을 정돈하고 있습니다'))
          ),
      ],
    );
  }

  Widget _buildWeekSelector() {
    final selectedDate = ref.watch(attendanceSelectedWeekProvider);
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 340,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('주차 선택 (일요일)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMain, fontFamily: 'Pretendard')),
                    ),
                    const Divider(height: 24),
                    ShadCalendar(
                      selected: selectedDate,
                      weekStartsOn: 7, // [FIX] 일요일이 가장 왼쪽에 오도록 설정
                      selectableDayPredicate: (date) {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        return date.weekday == DateTime.sunday && !date.isAfter(today);
                      },
                      onChanged: (date) {
                        if (date != null) {
                          ref.read(attendanceSelectedWeekProvider.notifier).state = date;
                          _refreshData();
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('yyyy.MM.dd').format(selectedDate),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1A1A1A), fontFamily: 'Pretendard', letterSpacing: -0.5),
          ),
          const SizedBox(width: 4),
          const Icon(lucide.LucideIcons.chevronDown, size: 20, color: AppTheme.textSub),
          const SizedBox(width: 8),
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    if (_members.isEmpty) return const SizedBox.shrink();
    
    final bool hasPublished = _members.any((m) => m['prayerStatus'] == 'published');
    final bool hasSavedDraft = _members.any((m) => m['prayerStatus'] == 'draft');

    String label = '작성 전';
    Color bgColor = const Color(0xFFF1F5F9);
    Color textColor = const Color(0xFF64748B);

    if (hasPublished) {
      label = '등록 완료';
      bgColor = const Color(0xFFECFDF5);
      textColor = const Color(0xFF10B981);
    } else if (hasSavedDraft) {
      label = '임시저장 중';
      bgColor = const Color(0xFFFFF7ED);
      textColor = const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bgColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildWeekSelector(),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControlBtn(icon: lucide.LucideIcons.rotateCcw, isActive: _undoStack.isNotEmpty, onTap: _undoRefinement, isPrimary: false), // [FIX] 라벨 제거
              const SizedBox(width: 8),
              _buildControlBtn(icon: lucide.LucideIcons.sparkles, label: _isRefining ? '정리중' : 'AI 정리', isActive: !_isRefining, onTap: _refineAllPrayers, isPrimary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlBtn({required IconData icon, String? label, required bool isActive, required VoidCallback onTap, bool isPrimary = false}) {
    final color = isPrimary ? AppTheme.primaryViolet : AppTheme.textSub;
    final bgColor = isPrimary ? AppTheme.accentViolet : const Color(0xFFF8FAFC);
    final borderColor = isPrimary ? Colors.transparent : AppTheme.border.withOpacity(0.5);
    return InkWell(
      onTap: isActive ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: isActive ? bgColor : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isActive ? borderColor : Colors.grey[100]!)),
        child: Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Icon(icon, size: 16, color: isActive ? color : Colors.grey[300]), 
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(width: 4), 
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? color : Colors.grey[300], fontFamily: 'Pretendard', letterSpacing: -0.26))
            ]
          ]
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, int index) {
    bool isPresent = member['isPresent'];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            leading: Container(
              width: 40, 
              height: 40, 
              decoration: BoxDecoration(
                color: isPresent ? AppTheme.accentViolet : const Color(0xFFF1F5F9), // v1 미참석 시 회색
                shape: BoxShape.circle
              ), 
              alignment: Alignment.center, 
              child: Text(
                member['name'][0], 
                style: TextStyle(
                  color: isPresent ? AppTheme.primaryViolet : const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600, 
                  fontSize: 14
                )
              )
            ),
            title: Row(
              children: [
                Text(member['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A), letterSpacing: -0.5, fontFamily: 'Pretendard')),
                if (member['source'] == 'current' && _hasExistingData && (ref.read(attendanceSelectedWeekProvider).isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))))
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('신규/이동', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                ShadBadge(
                  backgroundColor: isPresent ? AppTheme.accentViolet : const Color(0xFFF1F5F9),
                  foregroundColor: isPresent ? AppTheme.primaryViolet : const Color(0xFF1A1A1A), // v1 미참석 시 검은색 글씨
                  hoverBackgroundColor: isPresent ? AppTheme.accentViolet : const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(isPresent ? '참석' : '미참석', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                ),
                ],
              ),
            ),
            trailing: ReorderableDragStartListener(index: index, child: const Icon(lucide.LucideIcons.gripVertical, size: 20, color: Color(0xFF94A3B8))),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controllers[member['directoryMemberId']],
                  onChanged: (val) => member['prayerNote'] = val,
                  maxLines: null,
                  minLines: 2,
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF475569), fontFamily: 'Pretendard', letterSpacing: -0.5),
                  decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF8FAFC), hintText: isPresent ? '기도제목 입력' : '미참석자 기도제목', hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Pretendard'), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                ),
                _buildDynamicSpouseButton(member),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicSpouseButton(Map<String, dynamic> currentMember) {
    if (currentMember['familyId'] == null) return const SizedBox.shrink();
    final String familyId = currentMember['familyId'];
    if (!familyId.startsWith('couple_')) return const SizedBox.shrink();

    final spouse = _members.firstWhere(
      (m) => m['familyId'] == familyId && m['directoryMemberId'] != currentMember['directoryMemberId'],
      orElse: () => {},
    );

    if (spouse.isEmpty) return const SizedBox.shrink();

    final spouseController = _controllers[spouse['directoryMemberId']];
    if (spouseController == null) return const SizedBox.shrink();

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: spouseController,
      builder: (context, value, child) {
        final text = value.text.trim();
        if (text.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            onTap: () {
              final currentController = _controllers[currentMember['directoryMemberId']];
              if (currentController != null) {
                final currentText = currentController.text;
                if (currentText.isEmpty) {
                  currentController.text = text;
                } else {
                  currentController.text = "$currentText\n$text";
                }
                currentMember['prayerNote'] = currentController.text;
                setState(() {}); // 모델 업데이트 반영을 위해
                SnackBarUtil.showSnackBar(context, message: '${spouse['name']}님의 기도제목을 추가했습니다.');
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              painter: _DashedBorderPainter(color: AppTheme.primaryViolet.withOpacity(0.5), strokeWidth: 1, gap: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.primaryViolet.withOpacity(0.03),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(lucide.LucideIcons.plus, size: 14, color: AppTheme.primaryViolet),
                    const SizedBox(width: 4),
                    Text(
                      '${spouse['name']}님 기도제목 가져오기',
                      style: TextStyle(fontSize: 13, color: AppTheme.primaryViolet, fontWeight: FontWeight.w600, fontFamily: 'Pretendard'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // [기존 _buildCopySpouseButton 삭제됨]
  Widget _buildBottomActions() {
    
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + math.max(12, MediaQuery.of(context).padding.bottom)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFF1F5F9))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(child: OutlinedButton(onPressed: () => _saveData(status: 'draft'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), side: const BorderSide(color: Color(0xFFE2E8F0)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('임시 저장', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Pretendard')))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: SizedBox(height: 50, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ShadButton(onPressed: () => _saveData(status: 'published'), backgroundColor: const Color(0xFF8B5CF6), size: ShadButtonSize.lg, child: const Text('최종 등록하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')))))),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  _DashedBorderPainter({required this.color, this.strokeWidth = 1.0, this.gap = 5.0});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(8)));

    final PathMetrics pathMetrics = path.computeMetrics();
    for (PathMetric pathMetric in pathMetrics) {
      double distance = 0.0;
      while (distance < pathMetric.length) {
        final double length = gap;
        final double nextDistance = distance + length;
        canvas.drawPath(pathMetric.extractPath(distance, nextDistance), paint);
        distance = nextDistance + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth || gap != oldDelegate.gap;
  }
}

// [FIX] 출석/기록 메뉴 전용 커스텀 스켈레톤 (기도소식과 모양 차별화)
class _RecordSkeleton extends StatelessWidget {
  const _RecordSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 60, height: 16, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 6),
                      Container(width: 40, height: 12, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(width: double.infinity, height: 80, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12))),
            ],
          ),
        );
      },
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/services/ai_service.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/attendance/presentation/screens/attendance_check_screen.dart';
import 'package:grace_note/core/providers/settings_provider.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:grace_note/core/widgets/ai_processing_loader.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:animations/animations.dart';
import 'package:grace_note/core/utils/route_util.dart';
import 'prayer_share_screen.dart';

class AttendancePrayerScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const AttendancePrayerScreen({super.key, this.isActive = true});

  @override
  ConsumerState<AttendancePrayerScreen> createState() => _AttendancePrayerScreenState();
}

class _AttendancePrayerScreenState extends ConsumerState<AttendancePrayerScreen> {
  bool _isRefining = false;
  bool _isLoading = false;
  bool _isFetching = false;
  bool _isInitialized = false;
  bool _isCheckScreenShowing = false;
  final List<List<Map<String, dynamic>>> _undoStack = [];

  List<Map<String, dynamic>> _members = [];
  final Map<String, TextEditingController> _controllers = {};
  final ShadPopoverController _popoverController = ShadPopoverController();
  String? _currentGroupId;
  String? _currentChurchId;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _popoverController.dispose();
    super.dispose();
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
    if (_members.isEmpty || _isCheckScreenShowing || _isLoading || _isFetching) return;
    final hasAnyPresence = _members.any((m) => m['isPresent'] == true);
    if (!hasAnyPresence) {
      _isCheckScreenShowing = true;
      Future.microtask(() => _launchAttendanceCheck());
    }
  }

  Future<void> _refreshData() async {
    final groups = await ref.read(userGroupsProvider.future);
    if (groups.isNotEmpty) {
      _currentGroupId = groups.first['group_id'];
      _currentChurchId = groups.first['church_id'];
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
      final weekIdResult = await ref.read(weekIdProvider(churchId).future);
      if (weekIdResult == null) {
        setState(() {
          _isLoading = false;
          _isFetching = false;
        });
        return;
      }
      final weekId = weekIdResult;
      final membersData = await repo.getGroupMembers(groupId);
      final weeklyData = await repo.getWeeklyData(groupId, weekId);
      final existingAttendance = List<Map<String, dynamic>>.from(weeklyData['attendance']);
      final existingPrayers = List<Map<String, dynamic>>.from(weeklyData['prayers']);

      setState(() {
        final Map<String, Map<String, dynamic>> combinedMembers = {};
        for (final att in existingAttendance) {
          final directoryId = att['directory_member_id'];
          final member = att['member_directory'];
          if (directoryId == null || member == null) continue;
          final prayer = (existingPrayers as List).firstWhere(
            (p) => p['directory_member_id'] == directoryId, 
            orElse: () => <String, dynamic>{'content': ''}
          );
          combinedMembers[directoryId] = {
            'id': member['profile_id'], 
            'directoryMemberId': directoryId,
            'name': member['full_name'],
            'isPresent': att['status'] == 'present' || att['status'] == 'late',
            'prayerNote': prayer['content'] ?? '',
            'familyId': _generateFamilyId(member['full_name'], member['spouse_name'], member['family_id'], directoryId),
            'source': 'snapshot',
          };
        }
        for (final m in membersData) {
          final directoryId = m['id'];
          if (combinedMembers.containsKey(directoryId)) continue;
          combinedMembers[directoryId] = {
            'id': m['profiles']?['id'], 
            'directoryMemberId': directoryId,
            'name': m['full_name'],
            'isPresent': false,
            'prayerNote': '',
            'familyId': _generateFamilyId(m['full_name'], m['spouse_name'], m['family_id'], directoryId),
            'source': 'current',
          };
        }
        _members = combinedMembers.values.toList();
        for (final m in _members) {
          final directoryId = m['directoryMemberId'];
          final note = m['prayerNote'] ?? '';
          if (!_controllers.containsKey(directoryId)) {
            _controllers[directoryId] = TextEditingController(text: note);
          } else {
            _controllers[directoryId]!.text = note;
          }
        }
        _sortMembers();
        _isLoading = false;
        _isFetching = false;
        if (widget.isActive) _checkAndShowAttendancePopup();
      });
    } catch (e) {
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

  void _launchAttendanceCheck() {
    Navigator.of(context).push(
      SharedAxisPageRoute(
        page: AttendanceCheckScreen(
          initialMembers: _members,
          onComplete: (updated) async {
            setState(() {
              _members = updated;
              for (final m in _members) {
                final dirId = m['directoryMemberId'];
                if (_controllers.containsKey(dirId)) {
                  _controllers[dirId]!.text = m['prayerNote'] ?? '';
                } else {
                  _controllers[dirId] = TextEditingController(text: m['prayerNote'] ?? '');
                }
              }
              _sortMembers();
              _isCheckScreenShowing = false;
            });
            await _saveData(status: 'draft');
          },
        ),
      ),
    ).then((_) { if (mounted) setState(() => _isCheckScreenShowing = false); });
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
      SnackBarUtil.showSnackBar(context, message: 'AI가 내용을 정돈했습니다.');
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
      final weekIdResult = await ref.read(weekIdProvider(_currentChurchId!).future);
      if (weekIdResult == null) {
        if (mounted) Navigator.pop(context);
        throw Exception('주차 정보를 생성할 수 없습니다.');
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
          prayers.add(PrayerEntryModel(
            weekId: weekId,
            groupId: _currentGroupId!,
            memberId: memberId,
            directoryMemberId: dirId,
            content: note,
            status: status,
          ));
        }
      }
      await repo.saveAttendanceAndPrayers(attendanceList: attendance, prayerList: prayers);
      ref.invalidate(weeklyDataProvider);
      ref.invalidate(departmentWeeklyDataProvider);
      ref.invalidate(attendanceHistoryProvider);
      
      if (mounted) setState(() => _isLoading = false);
      if (mounted) SnackBarUtil.showSnackBar(context, message: status == 'published' ? '등록되었습니다.' : '저장되었습니다.');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) SnackBarUtil.showSnackBar(context, message: '저장 실패', isError: true);
    }
  }

  String _formatPrayersForSharing() {
    final settings = ref.read(aiSettingsProvider);
    final selectedDate = ref.read(selectedWeekDateProvider);
    final groups = ref.read(userGroupsProvider).value ?? [];
    final groupName = groups.isNotEmpty ? groups.first['group_name'] : '우리 조';
    final StringBuffer buffer = StringBuffer();
    if (settings.showDateInShare) buffer.write('${DateFormat('M/d').format(selectedDate)} ');
    final formattedGroupName = groupName.trim().endsWith('조') ? groupName : '$groupName조';
    buffer.writeln('$formattedGroupName \n');
    final icon = settings.shareHeaderIcon;
    for (final m in _members) {
      if (!m['isPresent']) continue;
      final note = (m['prayerNote'] as String).trim();
      if (note.isEmpty) continue;
      buffer.writeln('$icon${m['name']}$icon');
      final lines = note.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        final cleanLine = line.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*', unicode: true), '');
        buffer.writeln('${i + 1}. $cleanLine');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }


  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);
    ref.listen(selectedWeekDateProvider, (previous, next) { if (previous != next) _refreshData(); });
    ref.listen(userGroupsProvider, (previous, next) {
       if (next.hasValue) {
         final oldId = previous?.value?.isNotEmpty == true ? previous!.value!.first['group_id'] : null;
         final newId = next.value?.isNotEmpty == true ? next.value!.first['group_id'] : null;
         if (oldId != newId) _refreshData();
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

    final groupName = groupsAsync.value?.isNotEmpty == true ? groupsAsync.value!.first['group_name'] : '우리 조';

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
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) return const Center(child: Text('배정된 조가 없습니다.'));
          
          return Stack(
            children: [
              Column(
                children: [
                  _buildAIHeader(),
                  if (_isRefining) const LinearProgressIndicator(backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet), minHeight: 2),
                  Expanded(
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
        },
        loading: () {
          if (_members.isNotEmpty) {
            return Stack(
              children: [
                Column(
                  children: [
                    _buildAIHeader(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                        itemCount: _members.length,
                        itemBuilder: (context, index) => Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: _buildMemberCard(_members[index], index),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  color: Colors.white.withOpacity(0.7), 
                  child: const Center(child: CircularProgressIndicator())
                ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (e, s) => Center(child: Text('에러: $e')),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildWeekSelector() {
    final selectedDate = ref.watch(selectedWeekDateProvider);
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
                      selectableDayPredicate: (date) => date.weekday == DateTime.sunday,
                      onChanged: (date) {
                        if (date != null) {
                          ref.read(selectedWeekDateProvider.notifier).state = date;
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
              _buildControlBtn(icon: lucide.LucideIcons.rotateCcw, label: '되돌리기', isActive: _undoStack.isNotEmpty, onTap: _undoRefinement, isPrimary: false),
              const SizedBox(width: 8),
              _buildControlBtn(icon: lucide.LucideIcons.sparkles, label: _isRefining ? '정리중' : 'AI 정리', isActive: !_isRefining, onTap: _refineAllPrayers, isPrimary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlBtn({required IconData icon, required String label, required bool isActive, required VoidCallback onTap, bool isPrimary = false}) {
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: isActive ? color : Colors.grey[300]), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? color : Colors.grey[300], fontFamily: 'Pretendard', letterSpacing: -0.26))]),
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
                  color: isPresent ? AppTheme.primaryViolet : const Color(0xFF94A3B8), // v1 미참석 시 회색 글씨
                  fontWeight: FontWeight.w600, 
                  fontSize: 14
                )
              )
            ),
            title: Text(member['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A), letterSpacing: -0.5, fontFamily: 'Pretendard')),
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
            child: TextField(
              controller: _controllers[member['directoryMemberId']],
              onChanged: (val) => member['prayerNote'] = val,
              maxLines: null,
              minLines: 2,
              style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF475569), fontFamily: 'Pretendard', letterSpacing: -0.5),
              decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF8FAFC), hintText: isPresent ? '기도제목 입력' : '미참석자 기도제목', hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Pretendard'), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
            ),
          ),
        ],
      ),
    );
  }

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

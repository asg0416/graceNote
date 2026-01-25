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
import 'package:grace_note/core/widgets/droplet_loader.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/snack_bar_util.dart';

class AttendancePrayerScreen extends ConsumerStatefulWidget {
  const AttendancePrayerScreen({super.key});

  @override
  ConsumerState<AttendancePrayerScreen> createState() => _AttendancePrayerScreenState();
}

class _AttendancePrayerScreenState extends ConsumerState<AttendancePrayerScreen> {
  bool _isRefining = false;
  bool _isLoading = false;
  bool _isFetching = false; // Added to prevent concurrent fetches
  bool _isInitialized = false;
  bool _isCheckScreenShowing = false; // Added to prevent double-pop
  final List<List<Map<String, dynamic>>> _undoStack = [];

  List<Map<String, dynamic>> _members = [];
  final Map<String, TextEditingController> _controllers = {};
  String? _currentGroupId;
  String? _currentChurchId;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Initial fetch handled by build/watch
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
    if (_isFetching) return; // Prevent concurrent calls
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

        // 1. [Snapshot First] 해당 주차에 이미 기록된 사람들을 먼저 채움
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
            'source': 'snapshot', // 출처 표시
          };
        }

        // 2. [Current Directory] 스냅샷에 없지만 현재 이 조 소속인 사람들을 추가함
        // (조원이 새로 들어왔거나, 실수로 누락된 경우를 대비)
        for (final m in membersData) {
          final directoryId = m['id'];
          if (combinedMembers.containsKey(directoryId)) continue;

          combinedMembers[directoryId] = {
            'id': m['profiles']?['id'], 
            'directoryMemberId': directoryId,
            'name': m['full_name'],
            'isPresent': false, // 새로 추가된 사람은 기본적으로 결석 상태
            'prayerNote': '',
            'familyId': _generateFamilyId(m['full_name'], m['spouse_name'], m['family_id'], directoryId),
            'source': 'current',
          };
        }

        _members = combinedMembers.values.toList();
        
        // 컨트롤러 초기화
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

        // 출석 기록이 전혀 없거나, 참석 인원이 0명인 경우 출석체크 화면 강제 유도
        final hasAnyPresence = _members.any((m) => m['isPresent'] == true);
        if ((existingAttendance.isEmpty || !hasAnyPresence) && _members.isNotEmpty && !_isCheckScreenShowing) {
           _isCheckScreenShowing = true;
           Future.microtask(() => _launchAttendanceCheck());
        }
      });
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '데이터를 불러오지 못했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetching = false;
        });
      }
    }
  }

  void _sortMembers() {
    setState(() {
      _members.sort((a, b) {
        if (a['isPresent'] != b['isPresent']) {
          return a['isPresent'] ? -1 : 1;
        }
        if (a['familyId'] != b['familyId']) {
          return (a['familyId'] ?? '').compareTo(b['familyId'] ?? '');
        }
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceCheckScreen(
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
            // 출석체크 완료 즉시 임시 저장하여 새로고침 시 팝업 재발생 방지
            await _saveData(status: 'draft');
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isCheckScreenShowing = false);
      }
    });
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
        // Sync controllers after undo
        for (final m in _members) {
          final dirId = m['directoryMemberId'];
          if (_controllers.containsKey(dirId)) {
            _controllers[dirId]!.text = m['prayerNote'] ?? '';
          }
        }
      });
      if (mounted) SnackBarUtil.showSnackBar(context, message: '이전 상태로 되돌렸습니다. (남은 단계: ${_undoStack.length})');
    }
  }

  Future<void> _refineAllPrayers() async {
    // 0. 출석체크 여부 확인
    final hasAttendance = _members.any((m) => m['isPresent'] == true) || 
                         _members.any((m) => m['source'] == 'snapshot');
    
    if (!hasAttendance) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('출석체크 미완료'),
          content: const Text('출석체크가 되지 않았습니다. 출석체크를 먼저 진행하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('출석체크 하기', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
      );

      if (confirm == true) {
        _launchAttendanceCheck();
      }
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
        final hasAnyPresence = _members.any((m) => m['isPresent'] == true);
        if (!hasAnyPresence) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('출석체크 미완료'),
              content: const Text('현재 참석으로 표시된 조원이 없습니다. 출석체크를 먼저 진행하시겠습니까?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                TextButton(
                  onPressed: () => Navigator.pop(context, true), 
                  child: const Text('출석체크 하기', style: TextStyle(fontWeight: FontWeight.bold))
                ),
              ],
            ),
          );

          if (confirm == true) {
            _launchAttendanceCheck();
          }
        } else {
          SnackBarUtil.showSnackBar(context, message: '정리할 기도제목이 없습니다.', isError: true);
        }
        return;
      }

      final refined = await AIService().refinePrayers(
        rawNotes, 
        settings: ref.read(aiSettingsProvider)
      );

      _saveToHistory();
      setState(() {
        for (int i = 0; i < targetIndices.length; i++) {
          if (i < refined.length) {
            final idx = targetIndices[i];
            final refinedText = refined[i];
            _members[idx]['prayerNote'] = refinedText;
            
            final dirId = _members[idx]['directoryMemberId'];
            if (_controllers.containsKey(dirId)) {
              _controllers[dirId]!.text = refinedText;
            }
          }
        }
      });
      SnackBarUtil.showSnackBar(context, message: 'AI가 내용을 정돈하고 번호를 매겼습니다.');
    } finally {
      setState(() => _isRefining = false);
    }
  }

  Future<void> _saveData({required String status}) async {
    print('저장 시작: status=$status, church=$_currentChurchId, group=$_currentGroupId');
    
    if (_currentChurchId == null || _currentGroupId == null) {
      SnackBarUtil.showSnackBar(context, message: '교회 또는 그룹 정보를 찾을 수 없습니다.', isError: true);
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(repositoryProvider);
      final weekIdResult = await ref.read(weekIdProvider(_currentChurchId!).future);
      
      if (weekIdResult == null) {
        if (mounted) Navigator.pop(context); // Close loading
        throw Exception('이번 주 기록 정보를 생성할 수 없습니다. (관리자 문의)');
      }
      final weekId = weekIdResult;
      
      final List<AttendanceModel> attendance = [];
      final List<PrayerEntryModel> prayers = [];
      
      for (final m in _members) {
        final dirId = m['directoryMemberId'];
        final memberId = m['id']; // profile_id

        attendance.add(AttendanceModel(
          weekId: weekId,
          groupId: _currentGroupId, // 추가된 부분: 저장 시점의 조 ID 기록
          groupMemberId: m['groupMemberId'],
          directoryMemberId: dirId,
          status: m['isPresent'] ? 'present' : 'absent',
        ));
        
        final note = (m['prayerNote'] as String).trim();
        if (note.isNotEmpty) {
          prayers.add(PrayerEntryModel(
            weekId: weekId,
            groupId: _currentGroupId!,
            memberId: memberId, // Can be null for unlinked members
            directoryMemberId: dirId,
            content: note,
            status: status,
          ));
        }
      }
      
      print('저장 진행: 출석 ${attendance.length}건, 기도제목 ${prayers.length}건');
      
      await repo.saveAttendanceAndPrayers(
        attendanceList: attendance,
        prayerList: prayers,
      );

      // Invalidate providers to reflect changes immediately
      ref.invalidate(weeklyDataProvider);
      ref.invalidate(departmentWeeklyDataProvider);
      ref.invalidate(attendanceHistoryProvider);

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: status == 'published' ? '최종 등록되었습니다.' : '임시 저장되었습니다.');
      }
    } catch (e) {
      print('저장 에러: $e');
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '저장에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    }
  }

  String _formatPrayersForSharing() {
    final settings = ref.read(aiSettingsProvider);
    final selectedDate = ref.read(selectedWeekDateProvider);
    final groups = ref.read(userGroupsProvider).value ?? [];
    final groupName = groups.isNotEmpty ? groups.first['group_name'] : '우리 조';
    
    final StringBuffer buffer = StringBuffer();
    
    // Header: 1/18 효석 해비 조
    if (settings.showDateInShare) {
      buffer.write('${DateFormat('M/d').format(selectedDate)} ');
    }
    
    final formattedGroupName = groupName.trim().endsWith('조') ? groupName : '$groupName조';
    buffer.writeln('$formattedGroupName \n');
    
    final icon = settings.shareHeaderIcon;
    
    for (final m in _members) {
      if (!m['isPresent']) continue;
      final note = (m['prayerNote'] as String).trim();
      if (note.isEmpty) continue;
      
      // Member Header: 💙정원나영💙
      buffer.writeln('$icon${m['name']}$icon');
      
      // Fixed: Numbered list for prayer points when sharing
      final lines = note.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // Remove existing numbers and leading emojis to avoid "1. 😍 ..."
        final cleanLine = line
          .replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '')
          .replaceFirst(RegExp(r'^[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*', unicode: true), '');
        buffer.writeln('${i + 1}. $cleanLine');
      }
      buffer.writeln(); // Spacing between members
    }
    
    return buffer.toString().trim();
  }

  void _showShareMenu() {
    final shareText = _formatPrayersForSharing();
    if (shareText.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '공유할 기도제목이 없습니다.', isError: true);
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                // Top area for Preview Card (takes remaining space)
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {}, // Prevent closure when tapping inside card
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.85,
                          margin: const EdgeInsets.symmetric(vertical: 40),
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  '기도제목 미리보기',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textMain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Flexible(
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      shareText,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.textSub,
                                        height: 1.6,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom Actions (always at bottom)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 32 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildShareOption(
                        icon: Icons.copy_rounded,
                        label: '텍스트 복사하기',
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: shareText));
                          if (mounted) {
                            Navigator.pop(context);
                            SnackBarUtil.showSnackBar(context, message: '클립보드에 복사되었습니다.');
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildShareOption(
                        icon: Icons.share_rounded,
                        label: '카카오톡 및 시스템 공유',
                        onTap: () {
                          Share.share(shareText);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildShareOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.divider.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMain),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.divider, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Initial trigger & Date change trigger
    final groupsAsync = ref.watch(userGroupsProvider);

    // Listen for changes and refresh data
    ref.listen(selectedWeekDateProvider, (previous, next) {
      if (previous != next) {
        _refreshData();
      }
    });

    if (groupsAsync.hasValue && !_isInitialized) {
      _isInitialized = true;
      Future.microtask(() => _refreshData());
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.ios_share_rounded, color: AppTheme.primaryIndigo),
          onPressed: _showShareMenu,
          tooltip: '공유하기',
        ),
        title: Text(
          groupsAsync.value?.isNotEmpty == true 
            ? '${groupsAsync.value!.first['group_name']} 기록'
            : '기록',
          style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMain, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.how_to_reg_rounded, color: AppTheme.primaryIndigo),
            onPressed: () => _launchAttendanceCheck(),
            tooltip: '출석 체크',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) return const Center(child: Text('배정된 조가 없습니다.'));
          if (_isLoading) return const Center(child: DropletLoader(size: 80));
          
          return Stack(
            children: [
              Column(
                children: [
                  _buildAIHeader(),
                  if (_isRefining)
                    const LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryIndigo),
                      minHeight: 2,
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      buildDefaultDragHandles: false,
                      itemCount: _members.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = _members.removeAt(oldIndex);
                          _members.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            key: const ValueKey('top_margin'),
                            children: [
                              const SizedBox(height: 16),
                              _buildMemberCard(_members[index], index),
                            ],
                          );
                        }
                        return _buildMemberCard(_members[index], index);
                      },
                    ),
                  ),
                ],
              ),
              if (_isRefining)
                Container(
                  color: Colors.white.withOpacity(0.3),
                  child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const DropletLoader(size: 80),
                          const SizedBox(height: 24),
                          const Text(
                            '기도제목을 정돈하고 있습니다',
                            style: TextStyle(
                              color: AppTheme.textMain,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('데이터를 불러올 수 없습니다: $e')),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildWeekSelector() {
    final selectedDate = ref.watch(selectedWeekDateProvider);
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context, 
          initialDate: selectedDate, 
          firstDate: DateTime(2023), 
          lastDate: DateTime.now(),
          selectableDayPredicate: (day) => day.weekday == DateTime.sunday,
        );
        if (date != null) {
          ref.read(selectedWeekDateProvider.notifier).state = date;
          _refreshData();
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('yyyy.MM.dd').format(selectedDate),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    );
  }

  Widget _buildAIHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildWeekSelector(),
          Row(
            children: [
              _buildControlBtn(
                icon: Icons.undo_rounded, 
                label: '되돌리기', 
                isActive: _undoStack.isNotEmpty, 
                onTap: _undoRefinement
              ),
              const SizedBox(width: 8),
              _buildControlBtn(
                icon: Icons.auto_awesome_rounded, 
                label: _isRefining ? '정리중' : 'AI 정리', 
                isActive: !_isRefining, 
                onTap: _refineAllPrayers,
                isPrimary: true
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon, 
    required String label, 
    required bool isActive, 
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final color = isPrimary ? AppTheme.primaryIndigo : AppTheme.textSub;
    return InkWell(
      onTap: isActive ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.primaryIndigo.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? color.withOpacity(0.2) : Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? color : Colors.grey[300]),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isActive ? color : Colors.grey[300])),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, int index) {
    bool isPresent = member['isPresent'];
    return Container(
      key: ValueKey(member['directoryMemberId']),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: isPresent ? AppTheme.primaryIndigo.withOpacity(0.1) : Colors.grey[100],
              child: Text(
                member['name'][0], 
                style: TextStyle(color: isPresent ? AppTheme.primaryIndigo : Colors.grey[400], fontWeight: FontWeight.bold)
              ),
            ),
            title: Row(
              children: [
                Text(member['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (member['source'] == 'current') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: const Text(
                      '신규',
                      style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(isPresent ? '참석' : '미참석', style: TextStyle(fontSize: 12, color: isPresent ? AppTheme.primaryIndigo : Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (member['source'] == 'current')
                  IconButton(
                    icon: const Icon(Icons.person_remove_rounded, size: 20, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        final dirId = member['directoryMemberId'];
                        _members.removeAt(index);
                        _controllers.remove(dirId);
                      });
                      SnackBarUtil.showSnackBar(context, message: '${member['name']} 성도를 임시 명단에서 제외했습니다.');
                    },
                    tooltip: '명단에서 제외',
                  ),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_indicator_rounded, color: Colors.grey[200]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _controllers[member['directoryMemberId']],
              onChanged: (val) => member['prayerNote'] = val,
              maxLines: null,
              style: const TextStyle(fontSize: 15, height: 1.6),
              decoration: InputDecoration(
                hintText: isPresent ? '기도제목을 입력하세요 (AI가 자동 정리해줍니다)' : '미참석자 기도제목을 대신 입력할 수 있습니다',
                fillColor: isPresent ? AppTheme.background.withOpacity(0.5) : Colors.grey[50],
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _saveData(status: 'draft'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 56),
                side: BorderSide(color: AppTheme.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('임시 저장', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => _saveData(status: 'published'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 56),
              ),
              child: const Text('최종 등록하기'),
            ),
          ),
        ],
      ),
    );
  }
}

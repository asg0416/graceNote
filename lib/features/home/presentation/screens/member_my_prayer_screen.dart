import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class MemberMyPrayerScreen extends ConsumerStatefulWidget {
  const MemberMyPrayerScreen({super.key});

  @override
  ConsumerState<MemberMyPrayerScreen> createState() => _MemberMyPrayerScreenState();
}

class _MemberMyPrayerScreenState extends ConsumerState<MemberMyPrayerScreen> {
  bool _isLoading = true;
  String? _weekId;
  String? _groupId;
  String? _churchId;
  String? _directoryMemberId;
  
  bool _isPresent = false;
  String _prayerNote = '';
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    debugPrint('MemberMyPrayerScreen: _refreshData() START');
    setState(() {
      _isLoading = true;
      _directoryMemberId = null; // 초기화
      _groupId = null;
    });
    
    try {
      final groups = await ref.read(userGroupsProvider.future);
      debugPrint('MemberMyPrayerScreen: UserGroups fetched. Count: ${groups.length}');
      
      if (groups.isEmpty) {
        debugPrint('MemberMyPrayerScreen: No groups found for user.');
        setState(() => _isLoading = false);
        return;
      }

      final profileAsync = ref.read(userProfileProvider);
      final profile = profileAsync.value;
      
      if (profile == null) {
        debugPrint('MemberMyPrayerScreen: Profile is NULL in userProfileProvider. Waiting...');
        setState(() => _isLoading = false);
        return;
      }
      debugPrint('MemberMyPrayerScreen: Profile Verified -> Name: ${profile.fullName}, ID: ${profile.id}, Phone: ${profile.phone}');

      final repo = ref.read(repositoryProvider);
      
      // 1. 성도 명부에서의 본인 정보를 최우선으로 확보
      final directoryMember = await repo.getMemberDirectoryEntry(
        profileId: profile.id, 
        fullName: profile.fullName,
        phone: profile.phone,
      );
      
      if (directoryMember != null) {
        debugPrint('MemberMyPrayerScreen: Linkage SUCCESS -> DirectoryID: ${directoryMember['id']}');
        
        // 해당 멤버의 명부상 조 정보가 groups 리스트에 있는지 확인 (UI 컨텍스트 유지용)
        final dirGroupName = directoryMember['group_name'];
        final matchedGroup = groups.firstWhere(
          (g) => g['group_name'] == dirGroupName,
          orElse: () => groups.first,
        );

        if (mounted) {
          setState(() {
            _directoryMemberId = directoryMember['id'];
            _groupId = matchedGroup['group_id'];
            _churchId = matchedGroup['church_id'];
          });
        }
        debugPrint('MemberMyPrayerScreen: State Updated -> Group: ${_groupId}, DirectoryMember: $_directoryMemberId');
      } else {
        // 끝내 못 찾았다면 첫 번째 소속 그룹이라도 기본값으로 사용
        if (mounted) {
          setState(() {
            _groupId = groups.first['group_id'];
            _churchId = groups.first['church_id'];
            _directoryMemberId = null;
          });
        }
        debugPrint('MemberMyPrayerScreen: FAILED to find any directoryMember entry.');
      }

      // 2. 주차 정보 조회 (내부 상태 유지를 위해 최소한으로 수행)
      final weekId = await repo.getOrCreateWeek(_churchId!, ref.read(selectedWeekDateProvider), createIfMissing: false);
      _weekId = weekId;

      if (_weekId != null && _directoryMemberId != null) {
        try {
          final weeklyData = await repo.getWeeklyData(_groupId!, _weekId!);
          final myPrayer = (weeklyData['prayers'] as List?)?.firstWhere(
            (p) => p['directory_member_id'] == _directoryMemberId,
            orElse: () => null,
          );
          if (mounted) {
            setState(() {
              _prayerNote = myPrayer != null ? (myPrayer['content'] ?? '') : '';
              _noteController.text = _prayerNote;
            });
          }
        } catch (e) {
          debugPrint('MemberMyPrayerScreen: Silent fail for weekly data: $e');
        }
      }
    } catch (e, stack) {
      debugPrint('MemberMyPrayerScreen Error: $e\n$stack');
      // 연동 자체의 실패 등 치명적 에러만 표시
      if (mounted && _directoryMemberId == null) {
        SnackBarUtil.showSnackBar(
          context,
          message: '사용자 정보를 불러오는 중 문제가 발생했습니다.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_directoryMemberId != null) {
          ref.invalidate(memberPrayerHistoryProvider(_directoryMemberId!));
        }
      }
    }
  }

  Future<void> _handleSave() async {
    await _savePrayer();
  }

  Future<void> _savePrayer() async {
    if (_weekId == null || _groupId == null || _directoryMemberId == null) {
      SnackBarUtil.showSnackBar(context, message: '아직 이번 주 기록이 시작되지 않았습니다.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      final profile = await ref.read(userProfileProvider.future);
      
      await repo.saveAttendanceAndPrayers(
        attendanceList: [], // Attendance is managed by leader
        prayerList: [
          PrayerEntryModel(
            weekId: _weekId!,
            groupId: _groupId!,
            memberId: profile!.id,
            directoryMemberId: _directoryMemberId!,
            content: _noteController.text.trim(),
            status: 'published',
          ),
        ],
      );
      
      SnackBarUtil.showSnackBar(context, message: '기도제목이 저장되었습니다.');
      _refreshData();
    } catch (e) {
      SnackBarUtil.showSnackBar(
        context,
        message: '저장에 실패했습니다.',
        isError: true,
        technicalDetails: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // [CRITICAL] Watch profile ID to trigger refresh on account switch
    final profileId = ref.watch(userProfileProvider.select((p) => p.value?.id));
    
    // Listen for profile changes to force refresh
    ref.listen(userProfileProvider, (previous, next) {
      final oldId = previous?.value?.id;
      final newId = next.value?.id;
      if (newId != null && oldId != newId) {
        debugPrint('MemberMyPrayerScreen: Detected user change ($oldId -> $newId). Resetting state and refreshing...');
        setState(() {
          _directoryMemberId = null;
          _groupId = null;
          _isLoading = true;
        });
        _refreshData();
      }
    });

    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_groupId == null && _isLoading) {
        debugPrint('MemberMyPrayerScreen: Initial fetch for profileId: $profileId');
        _refreshData();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('나의 기도 타임라인', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppTheme.textMain)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? Center(child: ShadcnSpinner())
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '기도의 여정',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textMain),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '조장이 기록해 준 소중한 기도제목들입니다.',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSub),
                  ),
                  const SizedBox(height: 32),
                  _buildTimelineSection(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildTimelineSection() {
    if (_directoryMemberId == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 48, color: AppTheme.textSub.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              '조 명부에 등록되지 않아\n히스토리를 불러올 수 없습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onLongPress: () {
                final profile = ref.read(userProfileProvider).value;
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('디버그 정보'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Profile Name: ${profile?.fullName ?? "N/A"}'),
                        Text('Profile ID: ${profile?.id ?? "N/A"}'),
                        Text('Profile Phone: ${profile?.phone ?? "N/A"}'),
                        const Divider(),
                        Text('Directory ID: $_directoryMemberId'),
                        Text('Group ID: $_groupId'),
                        Text('Church ID: $_churchId'),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
                    ],
                  ),
                );
              },
              child: const Text(
                '조장님께 명부 등록을 요청하시면\n이곳에서 나의 기도 여정을 확인할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
              ),
            ),
          ],
        ),
      ));
    }

    final historyAsync = ref.watch(memberPrayerHistoryProvider(_directoryMemberId!));

    return historyAsync.when(
      data: (history) {
        if (history.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('아직 기록된 기도제목이 없습니다.', style: TextStyle(color: AppTheme.textSub)),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: history.length,
          itemBuilder: (context, index) {
            final item = history[index];
            final weekInfo = item['weeks'] as Map<String, dynamic>?;
            if (weekInfo == null) return const SizedBox.shrink();
            
            final date = DateTime.parse(weekInfo['week_date']);
            final content = (item['content'] ?? '').toString();
            final isLast = index == history.length - 1;

            return Stack(
              children: [
                // Timeline line (Vertical line connecting items)
                if (!isLast)
                  Positioned(
                    left: 9, // dot width(12)/2 + 3 (approx center)
                    top: 24,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: AppTheme.divider.withOpacity(0.5),
                    ),
                  ),
                // Item Content
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Dot
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4, left: 4),
                        decoration: BoxDecoration(
                          color: index == 0 ? AppTheme.primaryViolet : AppTheme.divider,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: index == 0 ? [
                            BoxShadow(color: AppTheme.primaryViolet.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)
                          ] : null,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Text Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  DateFormat('yyyy년 M월 d일 주차').format(date),
                                  style: TextStyle(
                                    fontSize: 14, 
                                    fontWeight: FontWeight.w800, 
                                    color: index == 0 ? AppTheme.primaryViolet : AppTheme.textSub
                                  ),
                                ),
                                if (item['member'] != null && item['member']['group_name'] != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryViolet.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppTheme.primaryViolet.withOpacity(0.2)),
                                    ),
                                    child: Text(
                                      '${item['member']['group_name']} 조',
                                      style: const TextStyle(
                                        color: AppTheme.primaryViolet,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.divider.withOpacity(0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                content,
                                style: const TextStyle(
                                  fontSize: 15, 
                                  height: 1.5, // Reduced slightly for web stability
                                  color: AppTheme.textMain,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
      loading: () => Center(child: ShadcnSpinner()),
      error: (e, s) => Center(child: Text('히스토리 로딩 실패: $e')),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AttendanceCheckNoMeetingResult {
  final bool isActive;
  const AttendanceCheckNoMeetingResult({required this.isActive});
}

class AttendanceCheckScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> initialMembers;
  final bool isPastWeek;
  final String? groupId;
  final bool isNewFamilyGroup;
  final bool hasExistingData;
  final bool isNewMemberNoMeetingSubmitted;
  final Future<Map<String, dynamic>?> Function()? onSubmitNewMemberNoMeeting;
  final Future<Map<String, dynamic>?> Function()? onCancelNewMemberNoMeeting;

  const AttendanceCheckScreen({
    super.key,
    required this.initialMembers,
    this.isPastWeek = false,
    this.groupId,
    this.isNewFamilyGroup = false,
    this.hasExistingData = false,
    this.isNewMemberNoMeetingSubmitted = false,
    this.onSubmitNewMemberNoMeeting,
    this.onCancelNewMemberNoMeeting,
  });

  @override
  ConsumerState<AttendanceCheckScreen> createState() =>
      _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends ConsumerState<AttendanceCheckScreen> {
  late List<Map<String, dynamic>> _tempMembers;
  late bool _isNewMemberNoMeetingSubmitted;
  bool _isNoMeetingMutationLoading = false;

  @override
  void initState() {
    super.initState();
    _tempMembers =
        widget.initialMembers.map((m) => Map<String, dynamic>.from(m)).toList();
    _isNewMemberNoMeetingSubmitted = widget.isNewMemberNoMeetingSubmitted;
  }

  Future<void> _submitNewMemberNoMeeting() async {
    if (widget.onSubmitNewMemberNoMeeting == null ||
        _isNoMeetingMutationLoading) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새가족 모임이 없어요'),
        content: const Text('이번 주 새가족 조모임 없음으로 제출할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('제출'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isNoMeetingMutationLoading = true);
    final result = await widget.onSubmitNewMemberNoMeeting!();
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _isNewMemberNoMeetingSubmitted = true;
        for (final member in _tempMembers) {
          if (member['role_in_group'] == 'leader') continue;
          member['isPresent'] = false;
        }
      });
      final absentCount = result['absent_member_count'];
      SnackBarUtil.showSnackBar(
        context,
        message: absentCount is int
            ? '새가족 모임 없음으로 제출했습니다. ($absentCount명 결석)'
            : '새가족 모임 없음으로 제출했습니다.',
      );
    }
    if (mounted) setState(() => _isNoMeetingMutationLoading = false);
  }

  Future<void> _cancelNewMemberNoMeeting() async {
    if (widget.onCancelNewMemberNoMeeting == null ||
        _isNoMeetingMutationLoading) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('모임 없음 처리 취소'),
        content: const Text('이번 주 새가족 모임 없음 처리를 취소할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isNoMeetingMutationLoading = true);
    final result = await widget.onCancelNewMemberNoMeeting!();
    if (!mounted) return;
    if (result != null) {
      setState(() {
        _isNewMemberNoMeetingSubmitted = false;
        for (final member in _tempMembers) {
          member['isPresent'] = false;
        }
      });
      SnackBarUtil.showSnackBar(context, message: '새가족 모임 없음 처리를 취소했습니다.');
    }
    if (mounted) setState(() => _isNoMeetingMutationLoading = false);
  }

  Widget _buildNewMemberNoMeetingAction() {
    final isSubmitted = _isNewMemberNoMeetingSubmitted;
    final Color surface =
        isSubmitted ? AppTheme.accentViolet : AppTheme.secondaryBackground;
    final Color accent = AppTheme.primaryViolet;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSubmitted || _isNoMeetingMutationLoading
            ? null
            : _submitNewMemberNoMeeting,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withOpacity(isSubmitted ? 0.22 : 0.16),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.12)),
                ),
                child: Icon(
                  isSubmitted ? LucideIcons.circleCheck : LucideIcons.calendarX,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSubmitted ? '새가족 모임 없음으로 제출됨' : '새가족 모임이 없어요',
                      style: const TextStyle(
                        color: AppTheme.textMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Pretendard',
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isSubmitted
                          ? '출석과 기도제목 제출이 완료 처리됐어요.'
                          : '새가족이 없어 모임을 진행하지 않는 주라면 바로 처리하세요.',
                      style: const TextStyle(
                        color: AppTheme.textSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Pretendard',
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (_isNoMeetingMutationLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              else if (isSubmitted)
                TextButton(
                  onPressed: _cancelNewMemberNoMeeting,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    minimumSize: const Size(52, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  child: const Text('취소'),
                )
              else
                Icon(LucideIcons.chevronRight, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeRoleProvider, (previous, next) {
      if (previous == null || next == null || next == AppRole.leader) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    });

    ref.listen(activeMembershipProvider, (previous, next) {
      final currentGroupId = widget.groupId;
      if (currentGroupId == null || currentGroupId.isEmpty) return;
      if (next != null && next.groupId == currentGroupId) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('출석 체크',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
                fontSize: 17)),
        leading: ShadButton.ghost(
          onPressed: () => Navigator.pop(context),
          child: const Icon(LucideIcons.x, size: 20, color: AppTheme.textSub),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        '오늘 모임에\n누가 오셨나요? 👋',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textMain,
                          height: 1.2,
                          letterSpacing: -0.8,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (context) {
                        final bool isAllSelected = _tempMembers.isNotEmpty &&
                            _tempMembers.every((m) => m['isPresent'] == true);
                        final bool isSelectionDisabled =
                            _isNewMemberNoMeetingSubmitted;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: isSelectionDisabled
                                  ? null
                                  : () {
                                      setState(() {
                                        for (var m in _tempMembers) {
                                          m['isPresent'] = !isAllSelected;
                                        }
                                      });
                                    },
                              icon: Icon(
                                isAllSelected
                                    ? LucideIcons.userMinus
                                    : LucideIcons.userPlus,
                                size: 22,
                                color: isSelectionDisabled || isAllSelected
                                    ? AppTheme.textSub
                                    : AppTheme.primaryViolet,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: isAllSelected
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFFF3F0FF),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.all(10),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAllSelected ? '전체 해제' : '전체 선택',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isAllSelected || isSelectionDisabled
                                    ? AppTheme.textSub
                                    : AppTheme.primaryViolet,
                                fontFamily: 'Pretendard',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                if (widget.isNewFamilyGroup &&
                    widget.onSubmitNewMemberNoMeeting != null) ...[
                  const SizedBox(height: 16),
                  _buildNewMemberNoMeetingAction(),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(
            child: _tempMembers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.users,
                            size: 48, color: AppTheme.textSub.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text('등록된 조원이 없습니다.',
                            style: TextStyle(color: AppTheme.textSub)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        24, 0, 24, 100), // Bottom padding for button area
                    itemCount:
                        _tempMembers.length + 1, // +1 for the info container
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      // Last item: Warning/Info Container
                      if (index == _tempMembers.length) {
                        return Container(
                          margin: const EdgeInsets.only(
                              top: 24), // Added margin for spacing
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED), // Light Orange
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFFFED7AA)), // Orange Border
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(LucideIcons.info,
                                        size: 16,
                                        color: Color(0xFFEA580C)), // Orange-600
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      '출석 체크/수정 후 기도제목 변경이 없더라도 기록 페이지 하단의 [최종 등록하기] 버튼을 꼭 눌러야 저장됩니다.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(
                                            0xFF9A3412), // Orange-900 (Darker text)
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Pretendard',
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(LucideIcons.info,
                                        size: 15, color: Color(0xFFEA580C)),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      "과거 주차 기록에 없는 성도가 현재 명단에 포함된 경우 이름 옆에 'X' 버튼이 표시됩니다. 이 버튼을 누르면 해당 성도를 이 주차 명단에서 제외할 수 있습니다.",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF9A3412),
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Pretendard',
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      final member = _tempMembers[index];
                      final bool isSelected = member['isPresent'] ?? false;
                      final String source = member['source'] ?? 'snapshot';
                      // [FIX] 과거 주차이면서 현재 명단에만 있는 경우라도, 해당 주차에 데이터가 하나도 없으면(미제출) 신규로 표시하지 않음
                      final bool isNewInHistory = widget.isPastWeek &&
                          source == 'current' &&
                          widget.hasExistingData;

                      return GestureDetector(
                        onTap: _isNewMemberNoMeetingSubmitted
                            ? null
                            : () => setState(
                                () => member['isPresent'] = !isSelected),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryViolet.withOpacity(0.04)
                                : AppTheme.secondaryBackground,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryViolet
                                  : AppTheme.border.withOpacity(0.3),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? AppTheme.primaryViolet
                                      : AppTheme.border.withOpacity(0.2),
                                ),
                                child: Center(
                                  child: isSelected
                                      ? const Icon(LucideIcons.check,
                                          color: Colors.white, size: 18)
                                      : Text(
                                          member['name'].toString().isNotEmpty
                                              ? member['name'][0]
                                              : '?',
                                          style: const TextStyle(
                                              color: AppTheme.textSub,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  member['name'],
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? AppTheme.primaryViolet
                                        : AppTheme.textMain,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              if (widget.isNewFamilyGroup &&
                                  widget.groupId != null &&
                                  member['role_in_group'] != 'leader') ...[
                                const SizedBox(width: 12),
                                Consumer(builder: (context, ref, _) {
                                  final memberId =
                                      member['directoryMemberId'] ??
                                          member['id'];
                                  final progressAsync = ref.watch(
                                      memberClimbingProgressProvider(
                                          '$memberId:${widget.groupId}'));

                                  return progressAsync.when(
                                    data: (count) {
                                      final isComplete = count >= 4;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isComplete
                                              ? const Color(0xFF22C55E)
                                                  .withOpacity(0.1)
                                              : const Color(0xFFF472B6)
                                                  .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isComplete
                                                ? const Color(0xFF22C55E)
                                                    .withOpacity(0.5)
                                                : const Color(0xFFF472B6)
                                                    .withOpacity(0.5),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isComplete)
                                              const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 10,
                                                  color: Color(0xFF16A34A))
                                            else
                                              Text('등반중',
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: const Color(
                                                          0xFFEC4899))),
                                            const SizedBox(width: 3),
                                            Text('$count/4',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: isComplete
                                                        ? const Color(
                                                            0xFF16A34A)
                                                        : const Color(
                                                            0xFFEC4899))),
                                          ],
                                        ),
                                      );
                                    },
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, __) => const SizedBox.shrink(),
                                  );
                                }),
                                const SizedBox(width: 6),
                              ],
                              if (isNewInHistory) ...[
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(LucideIcons.x,
                                      size: 18, color: Colors.red),
                                  tooltip: '이 주차의 출석체크에서 제외',
                                  onPressed: () {
                                    setState(() {
                                      _tempMembers.removeAt(index);
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '${member['name']} 성도를 이 주차에서 제외했습니다.'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                              ],
                              ShadCheckbox(
                                value: isSelected,
                                onChanged: _isNewMemberNoMeetingSubmitted
                                    ? null
                                    : (val) => setState(
                                        () => member['isPresent'] = val),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ShadButton(
            onPressed: () {
              if (_isNewMemberNoMeetingSubmitted) {
                Navigator.pop(
                  context,
                  const AttendanceCheckNoMeetingResult(isActive: true),
                );
                return;
              }
              Navigator.pop(context, _tempMembers);
            },
            backgroundColor: const Color(0xFF8B5CF6),
            child: Text(
                _isNewMemberNoMeetingSubmitted ? '기록 화면으로 돌아가기' : '출석체크 완료',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    fontFamily: 'Pretendard',
                    letterSpacing: -0.5)),
          ),
        ),
      ),
    );
  }
}

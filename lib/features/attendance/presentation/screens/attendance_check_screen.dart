import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AttendanceCheckScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> initialMembers;
  final bool isPastWeek;
  final String? groupId;
  final bool isNewFamilyGroup;
  final bool hasExistingData;

  const AttendanceCheckScreen({
    super.key, 
    required this.initialMembers, 
    this.isPastWeek = false,
    this.groupId,
    this.isNewFamilyGroup = false,
    this.hasExistingData = false,
  });

  @override
  ConsumerState<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends ConsumerState<AttendanceCheckScreen> {
  late List<Map<String, dynamic>> _tempMembers;

  @override
  void initState() {
    super.initState();
    _tempMembers = widget.initialMembers.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('출석 체크', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17)),
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
                        final bool isAllSelected = _tempMembers.isNotEmpty && _tempMembers.every((m) => m['isPresent'] == true);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  for (var m in _tempMembers) {
                                    m['isPresent'] = !isAllSelected;
                                  }
                                });
                              },
                              icon: Icon(
                                isAllSelected ? LucideIcons.userMinus : LucideIcons.userPlus,
                                size: 22, 
                                color: isAllSelected ? AppTheme.textSub : AppTheme.primaryViolet,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: isAllSelected ? const Color(0xFFF1F5F9) : const Color(0xFFF3F0FF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.all(10),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAllSelected ? '전체 해제' : '전체 선택',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isAllSelected ? AppTheme.textSub : AppTheme.primaryViolet,
                                fontFamily: 'Pretendard',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
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
                      Icon(LucideIcons.users, size: 48, color: AppTheme.textSub.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text('등록된 조원이 없습니다.', style: TextStyle(color: AppTheme.textSub)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 100), // Bottom padding for button area
                  itemCount: _tempMembers.length + 1, // +1 for the info container
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    // Last item: Warning/Info Container
                    if (index == _tempMembers.length) {
                      return Container(
                        margin: const EdgeInsets.only(top: 24), // Added margin for spacing
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED), // Light Orange
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFED7AA)), // Orange Border
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
                                  child: Icon(LucideIcons.info, size: 16, color: Color(0xFFEA580C)), // Orange-600
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    '출석 체크/수정 후 기도제목 변경이 없더라도 기록 페이지 하단의 [최종 등록하기] 버튼을 꼭 눌러야 저장됩니다.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF9A3412), // Orange-900 (Darker text)
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
                                    child: Icon(LucideIcons.info, size: 15, color: Color(0xFFEA580C)),
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
                    final bool isNewInHistory = widget.isPastWeek && source == 'current' && widget.hasExistingData;

                    return GestureDetector(
                      onTap: () => setState(() => member['isPresent'] = !isSelected),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryViolet.withOpacity(0.04) : AppTheme.secondaryBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryViolet : AppTheme.border.withOpacity(0.3),
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
                                color: isSelected ? AppTheme.primaryViolet : AppTheme.border.withOpacity(0.2),
                              ),
                              child: Center(
                                child: isSelected 
                                  ? const Icon(LucideIcons.check, color: Colors.white, size: 18)
                                  : Text(
                                      member['name'].toString().isNotEmpty ? member['name'][0] : '?', 
                                      style: const TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.w800, fontSize: 13)
                                    ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                member['name'],
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? AppTheme.primaryViolet : AppTheme.textMain,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            if (widget.isNewFamilyGroup && widget.groupId != null && member['role_in_group'] != 'leader') ...[
                              const SizedBox(width: 12),
                              Consumer(
                                builder: (context, ref, _) {
                                  final memberId = member['directoryMemberId'] ?? member['id'];
                                  final progressAsync = ref.watch(memberClimbingProgressProvider('$memberId:${widget.groupId}'));
                                  
                                  return progressAsync.when(
                                    data: (count) {
                                      final isComplete = count >= 4; 
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isComplete ? const Color(0xFF22C55E).withOpacity(0.1) : const Color(0xFFF472B6).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isComplete ? const Color(0xFF22C55E).withOpacity(0.5) : const Color(0xFFF472B6).withOpacity(0.5),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isComplete) 
                                              const Icon(Icons.check_circle_rounded, size: 10, color: Color(0xFF16A34A))
                                            else
                                              Text('등반중', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFEC4899))),
                                            const SizedBox(width: 3),
                                            Text('$count/4', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isComplete ? const Color(0xFF16A34A) : const Color(0xFFEC4899))),
                                          ],
                                        ),
                                      );
                                    },
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, __) => const SizedBox.shrink(),
                                  );
                                }
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (isNewInHistory) ...[
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(LucideIcons.x, size: 18, color: Colors.red),
                                tooltip: '이 주차의 출석체크에서 제외',
                                onPressed: () {
                                  setState(() {
                                    _tempMembers.removeAt(index);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${member['name']} 성도를 이 주차에서 제외했습니다.'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                            ],
                            ShadCheckbox(
                              value: isSelected,
                              onChanged: (val) => setState(() => member['isPresent'] = val),
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
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ShadButton(
            onPressed: () {
              Navigator.pop(context, _tempMembers);
            },
            backgroundColor: const Color(0xFF8B5CF6),
            child: const Text('출석체크 완료', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Pretendard', letterSpacing: -0.5)),
          ),
        ),
      ),
    );
  }
}

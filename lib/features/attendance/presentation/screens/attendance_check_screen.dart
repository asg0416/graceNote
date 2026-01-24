import 'package:flutter/material.dart';
import 'package:grace_note/core/theme/app_theme.dart';

class AttendanceCheckScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialMembers;
  final Function(List<Map<String, dynamic>>) onComplete;

  const AttendanceCheckScreen({
    super.key, 
    required this.initialMembers, 
    required this.onComplete
  });

  @override
  State<AttendanceCheckScreen> createState() => _AttendanceCheckScreenState();
}

class _AttendanceCheckScreenState extends State<AttendanceCheckScreen> {
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 모임에\n누가 오셨나요? 👋',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textMain,
                      height: 1.3,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '참석한 조원들을 체크해 주세요.\n체크된 분들에게만 기도제목 입력창이 제공됩니다.\n\n명단에 없는 성도는 "개별 성도 추가"를 통해 임시로 추가할 수 있습니다.',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSub,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var m in _tempMembers) {
                              m['isPresent'] = true;
                            }
                          });
                        },
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('전체 선택'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryIndigo,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                        ),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            for (var m in _tempMembers) {
                              m['isPresent'] = false;
                            }
                          });
                        },
                        icon: const Icon(Icons.remove_done_rounded, size: 18),
                        label: const Text('전체 해제'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSub,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                itemCount: _tempMembers.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final member = _tempMembers[index];
                  final bool isSelected = member['isPresent'];

                  return InkWell(
                    onTap: () => setState(() => member['isPresent'] = !member['isPresent']),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryIndigo.withOpacity(0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppTheme.primaryIndigo : AppTheme.divider,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isSelected ? AppTheme.primaryIndigo : Colors.grey[100],
                            child: isSelected 
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                              : Text(
                                  member['name'][0], 
                                  style: const TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)
                                ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            member['name'],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected ? AppTheme.primaryIndigo : AppTheme.textMain,
                            ),
                          ),
                          const Spacer(),
                          if (member['source'] == 'current')
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _tempMembers.removeAt(index);
                                });
                              },
                              icon: const Icon(Icons.close_rounded, size: 20, color: Colors.red),
                              tooltip: '명단에서 제외',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          const SizedBox(width: 8),
                          Checkbox(
                            value: isSelected,
                            activeColor: AppTheme.primaryIndigo,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) => setState(() => member['isPresent'] = val!),
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
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))
          ],
        ),
        child: ElevatedButton(
          onPressed: () {
            widget.onComplete(_tempMembers);
            Navigator.pop(context);
          },
          child: const Text('출석체크 완료'),
        ),
      ),
    );
  }
}

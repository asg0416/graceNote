import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/admin/presentation/screens/admin_member_detail_screen.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DepartmentMemberDirectoryScreen extends ConsumerWidget {
  final String departmentId;
  final String departmentName;

  const DepartmentMemberDirectoryScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(departmentGroupsProvider(departmentId));
    final departmentNameAsync = ref.watch(departmentNameProvider(departmentId));
    final resolvedName = departmentNameAsync.value ?? departmentName;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          '$resolvedName 구성원',
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(child: Text('등록된 조가 없습니다.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(departmentGroupsProvider(departmentId));
              await ref.read(departmentGroupsProvider(departmentId).future);
            },
            color: AppTheme.primaryViolet,
            child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _GroupMemberAccordion(
                groupId: group['id'] as String,
                groupName: group['name'] as String,
                isNewMemberGroup: group['is_new_member_group'] ?? false,
                climbingThreshold: group['climbing_threshold'] ?? 4,
              );
            },
          ),
          );
        },
        loading: () => Center(child: ShadcnSpinner()),
        error: (e, s) => Center(child: Text('데이터 로딩 실패: $e')),
      ),
    );
  }
}

class _GroupMemberAccordion extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;
  final bool isNewMemberGroup;
  final int climbingThreshold;

  const _GroupMemberAccordion({
    required this.groupId,
    required this.groupName,
    required this.isNewMemberGroup,
    required this.climbingThreshold,
  });

  @override
  ConsumerState<_GroupMemberAccordion> createState() => _GroupMemberAccordionState();
}

class _GroupMemberAccordionState extends ConsumerState<_GroupMemberAccordion> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            title: Row(
              children: [
                Text(
                  widget.groupName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (widget.isNewMemberGroup)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryViolet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '새가족',
                      style: TextStyle(
                        color: AppTheme.primaryViolet,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isNewMemberGroup)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20, color: AppTheme.textSub),
                    tooltip: '등반 기준 설정',
                    onPressed: () => _showClimbingSettingsDialog(context),
                  ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: AppTheme.textSub,
                ),
              ],
            ),
          ),
          if (_isExpanded)
            ref.watch(groupMembersProvider(widget.groupId)).when(
              data: (members) {
                if (members.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text('조원이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
                  );
                }
                // [SORT] 이름순(부부순) 정렬 (Marriage Key Sort)
                // final sortedMembers = List<Map<String, dynamic>>.from(members); // This creates a copy, but 'members' is likely immutable.
                final sortedMembers = [...members];
                
                sortedMembers.sort((a, b) {
                  String getMarriageKey(Map<String, dynamic> m) {
                    final name = (m['full_name'] as String?)?.trim() ?? '';
                    final spouse = (m['spouse_name'] as String?)?.trim() ?? '';
                    if (spouse.isEmpty) return name;
                    final list = [name, spouse];
                    list.sort(); 
                    return list.join('_');
                  }
                  
                  final k1 = getMarriageKey(a);
                  final k2 = getMarriageKey(b);
                  
                  if (k1 != k2) return k1.compareTo(k2);
                  
                  final n1 = (a['full_name'] as String?)?.trim() ?? '';
                  final n2 = (b['full_name'] as String?)?.trim() ?? '';
                  return n1.compareTo(n2); 
                });

                return Column(
                  children: [
                    const Divider(height: 1),
                    ...sortedMembers.map((member) => _buildMemberItem(context, member)), // Use sortedMembers
                    const SizedBox(height: 8),
                  ],
                );
              },
              loading: () => Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: SizedBox(width: 20, height: 20, child: ShadcnSpinner())),
              ),
              error: (e, s) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('로딩 실패: $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberItem(BuildContext context, Map<String, dynamic> member) {
    final fullName = member['full_name'] as String;
    final roleInGroup = member['role_in_group'] ?? 'member';
    final directoryMemberId = member['id'] as String;
    
    // Check if user has a profile (linked)
    final profile = member['profiles'];
    final isLinked = profile != null;

    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminMemberDetailScreen(
              directoryMemberId: directoryMemberId,
              fullName: fullName,
              groupName: widget.groupName,
              groupId: widget.groupId,
              departmentId: ref.read(userProfileProvider).value!.departmentId!,
            ),
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isLinked ? AppTheme.primaryViolet.withOpacity(0.1) : AppTheme.divider.withOpacity(0.3),
        child: Text(
          fullName.substring(fullName.length - 2),
          style: TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold,
            color: isLinked ? AppTheme.primaryViolet : AppTheme.textSub,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (roleInGroup == 'leader')
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('조장', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(
            isLinked ? '앱 가입 완료' : '미가입',
            style: TextStyle(fontSize: 12, color: isLinked ? Colors.green : AppTheme.textSub),
          ),
          if (widget.isNewMemberGroup && roleInGroup != 'leader') ...[
            const SizedBox(width: 8),
            Container(width: 1, height: 10, color: AppTheme.divider),
            const SizedBox(width: 8),
            ref.watch(memberClimbingProgressProvider('${member['id']}:${widget.groupId}')).when(
              data: (count) {
                final isComplete = count >= widget.climbingThreshold;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isComplete ? const Color(0xFF22C55E).withOpacity(0.1) : const Color(0xFFF472B6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isComplete ? const Color(0xFF22C55E).withOpacity(0.3) : const Color(0xFFF472B6).withOpacity(0.5),
                      width: 0.5
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isComplete ? Icons.check_circle_rounded : Icons.trending_up_rounded,
                        size: 10,
                        color: isComplete ? const Color(0xFF16A34A) : const Color(0xFFEC4899),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isComplete ? '등반 완료' : '등반 $count/${widget.climbingThreshold}',
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.w700, 
                          color: isComplete ? const Color(0xFF16A34A) : const Color(0xFFEC4899)
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox(width: 10, height: 10, child: ShadcnSpinner()),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 20, color: AppTheme.divider),
    );
  }

  void _showClimbingSettingsDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.climbingThreshold.toString());

    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('새가족 등반 기준 설정', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        description: const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 20),
          child: Text(
            '등반에 필요한 출석 횟수를 입력하세요.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.5, fontFamily: 'Pretendard'),
          ),
        ),
        actionsAxis: Axis.horizontal,
        expandActionsWhenTiny: false,
        removeBorderRadiusWhenTiny: false,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 320,
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('출석 주차 수', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      placeholder: const Text('4'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('주', style: TextStyle(color: AppTheme.textSub)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
          ),
          ShadButton(
            onPressed: () async {
              final val = int.tryParse(controller.text);
              if (val == null || val < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('유효한 숫자를 입력해주세요.')),
                );
                return;
              }

              try {
                await ref.read(repositoryProvider).updateGroup(
                  widget.groupId, 
                  {'climbing_threshold': val},
                );
                
                // Refresh
                ref.invalidate(departmentGroupsProvider);
                if (mounted) Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('등반 기준이 변경되었습니다.')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('오류 발생: $e')),
                );
              }
            },
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }
}

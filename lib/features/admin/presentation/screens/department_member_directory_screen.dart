import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/admin/presentation/screens/admin_member_detail_screen.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

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
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return _GroupMemberAccordion(
                groupId: group['id'] as String,
                groupName: group['name'] as String,
              );
            },
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

  const _GroupMemberAccordion({
    required this.groupId,
    required this.groupName,
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
            title: Text(
              widget.groupName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            trailing: Icon(
              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppTheme.textSub,
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
                return Column(
                  children: [
                    const Divider(height: 1),
                    ...members.map((member) => _buildMemberItem(context, member)),
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
      subtitle: Text(
        isLinked ? '앱 가입 완료' : '미가입',
        style: TextStyle(fontSize: 12, color: isLinked ? Colors.green : AppTheme.textSub),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 20, color: AppTheme.divider),
    );
  }
}

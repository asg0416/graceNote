import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/group_management/presentation/screens/member_edit_screen.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class GroupLeaderAdminScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupLeaderAdminScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupLeaderAdminScreen> createState() => _GroupLeaderAdminScreenState();
}

class _GroupLeaderAdminScreenState extends ConsumerState<GroupLeaderAdminScreen> {
  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('우리 조원 관리', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: membersAsync.when(
        data: (members) {
          if (members.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.people_outline_rounded, size: 60, color: AppTheme.divider),
                   const SizedBox(height: 16),
                   const Text('등록된 조원이 없습니다.', style: TextStyle(color: AppTheme.textSub)),
                   const SizedBox(height: 24),
                   ElevatedButton.icon(
                     onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MemberEditScreen(groupId: widget.groupId, groupName: widget.groupName))),
                     icon: const Icon(Icons.add_rounded),
                     label: const Text('첫 조원 추가하기'),
                   ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _buildHeader(members),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    return _buildMemberTile(context, ref, member);
                  },
                ),
              ),
            ],
          );
        },
        loading: () => Center(child: ShadcnSpinner()),
        error: (e, s) => Center(child: Text('데이터 로딩 실패: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MemberEditScreen(groupId: widget.groupId, groupName: widget.groupName))),
        backgroundColor: AppTheme.primaryViolet,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('조원 추가', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeader(List<Map<String, dynamic>> members) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8B5CF6),
            Color(0xFF6366F1),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border.withOpacity(0.5), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.groupName, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
                  const SizedBox(height: 4),
                  const Text('조원 명단 관리', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'Pretendard', letterSpacing: -0.5)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildSimpleStat('총원', '${members.length}명'),
                      const SizedBox(width: 12),
                      _buildSimpleStat('앱 연결', '${members.where((m) => m['profile_id'] != null).length}명'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Pretendard')),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'Pretendard')),
        ],
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, WidgetRef ref, Map<String, dynamic> member) {
    final bool isLinked = member['profile_id'] != null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryViolet.withOpacity(0.1),
          child: Text(member['full_name'][0], style: const TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Text(member['full_name'], style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (isLinked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('연결됨', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Text(member['phone'] ?? '연락처 없음', style: const TextStyle(fontSize: 12, color: AppTheme.textSub)),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.textSub),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MemberEditScreen(groupId: widget.groupId, groupName: widget.groupName, member: member))),
        ),
        onLongPress: () => _confirmDelete(context, ref, member),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('조원 삭제'),
        content: Text('${member['full_name']}님을 우리 조 명단에서 삭제하시겠습니까? (기존 기록은 보존됩니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('삭제', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(repositoryProvider).deleteDirectoryMember(member['id']);
        ref.invalidate(groupMembersProvider(widget.groupId));
        if (context.mounted) SnackBarUtil.showSnackBar(context, message: '삭제되었습니다.');
      } catch (e) {
        if (context.mounted) {
          SnackBarUtil.showSnackBar(
            context,
            message: '삭제에 실패했습니다.',
            isError: true,
            technicalDetails: e.toString(),
          );
        }
      }
    }
  }
}

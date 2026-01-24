import 'package:flutter/material.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/group_selection_screen.dart';
import 'package:grace_note/features/home/presentation/screens/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  final String churchId;
  final String churchName;
  final String? prefilledPhone;

  const ProfileSetupScreen({
    super.key,
    required this.churchId,
    required this.churchName,
    this.prefilledPhone,
  });

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  late final TextEditingController _phoneController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.prefilledPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '이름을 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // member_directory에서 이름이 일치하는 모든 성도 조회
      final response = await Supabase.instance.client
          .from('member_directory')
          .select('*, departments(name)')
          .eq('church_id', widget.churchId)
          .eq('full_name', name);

      final List<dynamic> matches = List.from(response);

      if (mounted) {
        if (matches.isEmpty) {
          // 1. 매칭된 데이터가 아예 없는 경우
          _navigateToGroupSelection(null);
        } else if (matches.length == 1) {
          // 2. 한 명만 매칭된 경우
          final match = Map<String, dynamic>.from(matches.first);
          if (match['departments'] != null) {
            match['department_name'] = match['departments']['name'];
          }
          
          // 연락처가 DB에 있다면 비교 (선택 사항)
          if (match['phone'] != null && match['phone'].toString().isNotEmpty && phone.isNotEmpty) {
             // 번호까지 일치하거나, 번호가 달라도 일단 확인 다이얼로그 보여줌
             // (사용자가 번호를 바꿨을 수도 있으므로)
             _showMatchSuccessDialog(match);
          } else {
             // DB에 번호가 없거나 한 명뿐인 경우 즉시 확인 다이얼로그
             _showMatchSuccessDialog(match);
          }
        } else {
          // 3. 동일한 이름을 가진 성도가 여러 명인 경우 (예: '이수진'이 여러 명)
          _showMultipleMatchesDialog(matches);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '확인 중 오류가 발생했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMultipleMatchesDialog(List<dynamic> matches) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('동일한 이름이 여러 명 있습니다', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('본인의 소속 부서와 조를 선택해 주세요:'),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              width: double.maxFinite,
              child: ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final m = Map<String, dynamic>.from(matches[index]);
                  final deptName = m['departments']?['name'] ?? '부서 미정';
                  final groupName = m['group_name'] ?? '조 미정';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$deptName $groupName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(m['full_name'], style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      if (m['departments'] != null) {
                        m['department_name'] = m['departments']['name'];
                      }
                      _showMatchSuccessDialog(m);
                    },
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToGroupSelection(null);
            },
            child: const Text('여기에 없어요 (직접 등록)'),
          ),
        ],
      ),
    );
  }

  void _showMatchSuccessDialog(Map<String, dynamic> match) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('등록 정보 확인', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${match['full_name']}님, 반갑습니다!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('관리자에 의해 아래와 같이 배정되어 있습니다:'),
            const SizedBox(height: 16),
            _buildInfoRow('소속 부서', match['department_name'] ?? '정보 없음'),
            _buildInfoRow('배정된 조', match['group_name'] ?? '미정'),
            if (match['family_name'] != null) _buildInfoRow('가족 정보', match['family_name']),
            const SizedBox(height: 12),
            const Text('위 정보로 프로필을 생성할까요?', style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToGroupSelection(null); // 무시하고 수동 선택
            },
            child: const Text('수동으로 선택할게요', style: TextStyle(color: AppTheme.textLight)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _completeOnboardingDirectly(match); // 즉시 완료
            },
            child: const Text('네, 맞아요!'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeOnboardingDirectly(Map<String, dynamic> match) async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('로그인 세션이 만료되었습니다.');

      // groups 테이블에서 해당 group_name에 맞는 ID 찾기
      final groups = await ref.read(churchGroupsProvider(widget.churchId).future);
      String? matchedGroupId;
      if (match['group_name'] != null) {
        final matchedGroup = groups.firstWhere(
          (g) => g['name'] == match['group_name'],
          orElse: () => <String, dynamic>{},
        );
        matchedGroupId = matchedGroup['id'];
      }

      final repo = ref.read(repositoryProvider);
      await repo.completeOnboarding(
        profileId: user.id,
        fullName: _nameController.text.trim(),
        churchId: widget.churchId,
        groupId: matchedGroupId,
        phone: _phoneController.text.trim(),
        matchedData: match,
      );

      // Refresh providers
      ref.invalidate(userProfileProvider);
      ref.invalidate(userGroupsProvider);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '저장 중 오류가 발생했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Text(value, style: const TextStyle(color: AppTheme.primaryIndigo, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _navigateToGroupSelection(Map<String, dynamic>? match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupSelectionScreen(
          churchId: widget.churchId,
          churchName: widget.churchName,
          prefilledName: _nameController.text.trim(),
          prefilledPhone: _phoneController.text.trim(),
          matchedData: match,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('프로필 설정'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '성함과 연락처를\n입력해주세요',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.3),
            ),
            const SizedBox(height: 8),
            const Text('관리자가 미리 등록한 조편성 정보를 찾기 위해 필요합니다.', style: TextStyle(color: AppTheme.textSub)),
            const SizedBox(height: 40),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '이름',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: '연락처 (선택)',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleNext,
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }
}

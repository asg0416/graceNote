import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/home/presentation/screens/home_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class GroupSelectionScreen extends ConsumerStatefulWidget {
  final String churchId;
  final String churchName;

  final String? prefilledName;
  final String? prefilledPhone;
  final Map<String, dynamic>? matchedData;

  const GroupSelectionScreen({
    super.key,
    required this.churchId,
    required this.churchName,
    this.prefilledName,
    this.prefilledPhone,
    this.matchedData,
  });

  @override
  ConsumerState<GroupSelectionScreen> createState() => _GroupSelectionScreenState();
}

class _GroupSelectionScreenState extends ConsumerState<GroupSelectionScreen> {
  late final TextEditingController _nameController;
  String? _selectedGroupId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prefilledName);
    debugPrint('GroupSelectionScreen: churchId=${widget.churchId}, matchedData=${widget.matchedData}');
  }

  Future<void> _completeOnboarding() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '이름을 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('로그인 세션이 만료되었습니다.');

      final repo = ref.read(repositoryProvider);
      await repo.completeOnboarding(
        profileId: user.id,
        fullName: name,
        churchId: widget.churchId,
        groupId: _selectedGroupId,
        phone: widget.prefilledPhone,
        matchedData: widget.matchedData,
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
          message: '저장에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(churchGroupsProvider(widget.churchId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('프로필 초기화', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                '거의 다 왔어요!\n어떻게 불러드릴까요?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '성함 (실명 권장)',
                  hintText: '예: 홍길동',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '소속된 소그룹(조)을 선택해주세요',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain),
              ),
              const SizedBox(height: 12),
              groupsAsync.when(
                data: (groups) {
                  // 매칭된 그룹명이 있을 경우 자동 선택 시도
                  if (_selectedGroupId == null && widget.matchedData != null) {
                    final matchedGroupName = widget.matchedData!['group_name'];
                    if (matchedGroupName != null) {
                      final matchedGroup = groups.firstWhere(
                        (g) => g['name'] == matchedGroupName,
                        orElse: () => <String, dynamic>{},
                      );
                      if (matchedGroup.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _selectedGroupId = matchedGroup['id']);
                        });
                      }
                    }
                  }

                  return Column(
                    children: [
                      if (groups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('해당 교회에 등록된 그룹이 없습니다.'),
                        ),
                      ...groups.map((group) {
                        final isSelected = _selectedGroupId == group['id'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () => setState(() => _selectedGroupId = group['id']),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryViolet.withOpacity(0.05) : Colors.white,
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryViolet : AppTheme.divider,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.groups, color: isSelected ? AppTheme.primaryViolet : Colors.grey[400]),
                                  const SizedBox(width: 16),
                                  Expanded(child: Text(group['name'], style: const TextStyle(fontWeight: FontWeight.bold))),
                                  if (isSelected) const Icon(Icons.check_circle, color: AppTheme.primaryViolet),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
                loading: () => Center(child: ShadcnSpinner()),
                error: (e, _) => Text('그룹 로드 오류: $e'),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _completeOnboarding,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: _isLoading ? ShadcnSpinner(color: Colors.white) : const Text('성도 정보 입력 완료'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

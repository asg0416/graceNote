import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/group_selection_screen.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class ChurchSelectionScreen extends ConsumerStatefulWidget {
  final String? prefilledPhone;

  const ChurchSelectionScreen({
    super.key,
    this.prefilledPhone,
  });

  @override
  ConsumerState<ChurchSelectionScreen> createState() => _ChurchSelectionScreenState();
}

class _ChurchSelectionScreenState extends ConsumerState<ChurchSelectionScreen> {
  String? _selectedChurchId;
  String? _selectedChurchName;

  @override
  Widget build(BuildContext context) {
    final churchesAsync = ref.watch(allChurchesProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('교회 선택', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('로그인 취소'),
                content: const Text('교회 선택을 취소하고 로그아웃하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('아니오'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            
            if (shouldLogout == true && mounted) {
              // 로그아웃만 호출 - AuthGate가 자동으로 LoginScreen으로 전환
              await ref.read(repositoryProvider).signOut();
            }
          },
        ),
      ),
      body: churchesAsync.when(
        data: (churches) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '섬기시는 교회를\n선택해주세요',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMain,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '소속된 교회의 정보를 불러오기 위해 필요합니다.',
                    style: TextStyle(color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: churches.isEmpty 
                ? const Center(child: Text('등록된 교회가 없습니다.'))
                : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: churches.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final church = churches[index];
                    final isSelected = _selectedChurchId == church['id'];
                    
                    return InkWell(
                      onTap: () => setState(() {
                        _selectedChurchId = church['id'];
                        _selectedChurchName = church['name'];
                      }),
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryViolet : Colors.grey[100],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.church,
                                color: isSelected ? Colors.white : Colors.grey[400],
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    church['name']!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? AppTheme.textMain : AppTheme.textSub,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    church['address'] ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: AppTheme.primaryViolet),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ),
            
            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
              child: ElevatedButton(
                onPressed: _selectedChurchId != null
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileSetupScreen(
                            churchId: _selectedChurchId!,
                            churchName: _selectedChurchName!,
                            prefilledPhone: widget.prefilledPhone,
                          ),
                        ),
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedChurchId != null ? AppTheme.primaryViolet : Colors.grey[300],
                ),
                child: const Text('다음'),
              ),
            ),
          ],
        ),
        loading: () => Center(child: ShadcnSpinner()),
        error: (e, _) => Center(child: Text('교회 목록 로딩 오류: $e')),
      ),
    );
  }
}

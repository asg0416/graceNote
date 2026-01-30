import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class SavedPrayersScreen extends ConsumerWidget {
  const SavedPrayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('저장된 기도제목', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textMain),
      ),
      body: ref.watch(savedPrayersProvider(profile.id)).when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.bookmark_border_rounded, size: 60, color: AppTheme.divider),
                   const SizedBox(height: 16),
                   const Text('저장하거나 기도한 소식이 아직 없습니다.', style: TextStyle(color: AppTheme.textSub)),
                ],
              ),
            );
          }

          // 중복 기도제목 처리 (하나의 기도제목에 대해 pray와 save가 모두 있을 수 있음)
          // 하지만 여기선 각각의 interaction을 독립적으로 보여주거나, 합쳐서 보여줄 수 있음.
          // 사용자는 "내가 반응한 기도제목"을 보고 싶은 것이므로 interaction_type별로 그룹화하되 섹션을 명확히 함.
          
          final savedItems = items.where((i) => i['interaction_type'] == 'save').toList();
          final prayItems = items.where((i) => i['interaction_type'] == 'pray').toList();

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              if (savedItems.isNotEmpty) ...[
                _buildSectionHeader('내가 보관한 소식', isHighlight: true),
                _buildSavedList(savedItems),
              ],
              if (prayItems.isNotEmpty) ...[
                _buildSectionHeader('함께 기도한 소식', isHighlight: false),
                _buildSavedList(prayItems, isPraying: true),
              ],
            ],
          );
        },
        loading: () => Center(child: ShadcnSpinner()),
        error: (e, s) => Center(child: Text('데이터 로딩 실패: $e')),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: isHighlight ? AppTheme.primaryViolet : AppTheme.textSub,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: isHighlight ? AppTheme.textMain : AppTheme.textSub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedList(List<Map<String, dynamic>> items, {bool isPraying = false}) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final interaction = items[index];
        final prayer = interaction['prayer_entries'] as Map<String, dynamic>?;
        if (prayer == null) return const SizedBox.shrink();

        final member = prayer['member_directory'] as Map<String, dynamic>?;
        final name = member?['full_name'] ?? '알 수 없음';
        final content = prayer['content'] ?? '';
        final date = prayer['updated_at'] != null 
            ? DateFormat('yyyy.MM.dd').format(DateTime.parse(prayer['updated_at']))
            : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.divider),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text(date, style: const TextStyle(color: AppTheme.textSub, fontSize: 12)),
                    ],
                  ),
                  Icon(
                    isPraying ? Icons.volunteer_activism_rounded : Icons.bookmark_rounded, 
                    color: AppTheme.primaryViolet, 
                    size: 20
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(fontSize: 14, color: AppTheme.textMain, height: 1.6),
              ),
            ],
          ),
        );
      },
    );
  }
}

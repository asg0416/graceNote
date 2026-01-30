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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('저장된 기도제목', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: const TabBar(
            labelColor: AppTheme.primaryViolet,
            unselectedLabelColor: AppTheme.textSub,
            indicatorColor: AppTheme.primaryViolet,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, fontFamily: 'Pretendard'),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Pretendard'),
            tabs: [
              Tab(text: '내가 보관한 소식'),
              Tab(text: '중보기도 소식'),
            ],
          ),
        ),
        body: ref.watch(savedPrayersProvider(profile.id)).when(
          data: (items) {
            final savedItems = items.where((i) => i['interaction_type'] == 'save').toList();
            final prayItems = items.where((i) => i['interaction_type'] == 'pray').toList();

            return TabBarView(
              children: [
                _buildTabContent(savedItems, '보관한 소식이 아직 없습니다.'),
                _buildTabContent(prayItems, '중보기도한 소식이 아직 없습니다.', isPraying: true),
              ],
            );
          },
          loading: () => Center(child: ShadcnSpinner()),
          error: (e, s) => Center(child: Text('데이터 로딩 실패: $e')),
        ),
      ),
    );
  }

  Widget _buildTabContent(List<Map<String, dynamic>> items, String emptyMessage, {bool isPraying = false}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(isPraying ? Icons.volunteer_activism_rounded : Icons.bookmark_border_rounded, size: 60, color: AppTheme.divider),
             const SizedBox(height: 16),
             Text(emptyMessage, style: const TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildSavedItem(items[index], isPraying: isPraying);
      },
    );
  }

  Widget _buildSavedItem(Map<String, dynamic> interaction, {bool isPraying = false}) {
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
        border: Border.all(color: AppTheme.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFamily: 'Pretendard')),
                  const SizedBox(width: 8),
                  Text(date, style: const TextStyle(color: AppTheme.textSub, fontSize: 12, fontFamily: 'Pretendard')),
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
            style: const TextStyle(fontSize: 14, color: AppTheme.textMain, height: 1.6, fontFamily: 'Pretendard'),
          ),
        ],
      ),
    );
  }
}

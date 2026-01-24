import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';

class AdminMemberDetailScreen extends ConsumerWidget {
  final String directoryMemberId;
  final String fullName;
  final String groupName;

  const AdminMemberDetailScreen({
    super.key,
    required this.directoryMemberId,
    required this.fullName,
    required this.groupName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerHistoryAsync = ref.watch(memberPrayerHistoryProvider(directoryMemberId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('구성원 상세 정보', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileCard(),
            const Divider(height: 40, thickness: 8, color: AppTheme.background),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('기도제목 히스토리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
            ),
            const SizedBox(height: 16),
            prayerHistoryAsync.when(
              data: (history) {
                if (history.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('등록된 기도제목이 없습니다.', style: TextStyle(color: AppTheme.textSub)),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final prayer = history[index];
                    return _buildPrayerTimelineItem(prayer, index == history.length - 1);
                  },
                );
              },
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              error: (e, s) => Center(child: Text('로딩 실패: $e')),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppTheme.primaryIndigo.withOpacity(0.1),
            child: Text(
              fullName.length >= 2 ? fullName.substring(fullName.length - 2) : fullName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(groupName, style: const TextStyle(fontSize: 16, color: AppTheme.primaryIndigo, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.phone_iphone, size: 14, color: AppTheme.textSub),
                    SizedBox(width: 4),
                    Text('번호 비공개', style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerTimelineItem(Map<String, dynamic> prayer, bool isLast) {
    final title = (prayer['title'] ?? '') as String;
    final content = (prayer['content'] ?? '') as String;
    
    // 주차 정보 처리 (이름이 없으면 날짜로 대체)
    String weekName = '알 수 없는 주차';
    final weeksData = prayer['weeks'];
    if (weeksData != null) {
      if (weeksData['name'] != null) {
        weekName = weeksData['name'];
      } else if (weeksData['week_date'] != null) {
        final date = DateTime.parse(weeksData['week_date']);
        weekName = '${DateFormat('M/d').format(date)} 주차';
      }
    }

    final createdAtStr = prayer['created_at'];
    final createdAt = createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 6),
              decoration: const BoxDecoration(
                color: AppTheme.primaryIndigo,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 100, // Fixed height for timeline line
                color: AppTheme.divider,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(weekName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryIndigo, fontSize: 13)),
                    Text(DateFormat('MM/dd').format(createdAt), style: const TextStyle(color: AppTheme.textSub, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textMain)),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(color: AppTheme.textSub, fontSize: 14, height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

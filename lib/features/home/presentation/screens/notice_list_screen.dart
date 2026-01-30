import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class NoticeListScreen extends ConsumerStatefulWidget {
  const NoticeListScreen({super.key});

  @override
  ConsumerState<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends ConsumerState<NoticeListScreen> {
  // Removed automatic mark-all-read on entry to satisfy user's request
  // for per-notice read persistence.

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final readIdsAsync = ref.watch(userReadNoticeIdsProvider);
    final noticesAsync = ref.watch(allNoticesProvider);

    // 데이터가 하나라도 있는 경우 기존 UI를 유지하도록 처리 (깜빡임 방지)
    final hasData = profileAsync.hasValue && readIdsAsync.hasValue && noticesAsync.hasValue;
    final hasError = profileAsync.hasError || readIdsAsync.hasError || noticesAsync.hasError;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('공지사항', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppTheme.border, height: 1.0),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: () {
        if (hasData) {
          final profile = profileAsync.value;
          final readIds = readIdsAsync.value ?? {};
          final notices = noticesAsync.value ?? [];

          if (profile == null) return const Center(child: Text('로그인 정보가 없습니다.'));
          
          if (notices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_rounded, size: 64, color: AppTheme.divider),
                  const SizedBox(height: 16),
                  const Text('등록된 공지사항이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: notices.length,
            itemBuilder: (context, index) {
              final notice = notices[index];
              final isUnread = !readIds.contains(notice['id']);
              return _buildNoticeCard(context, notice, isUnread);
            },
          );
        }

        if (hasError) {
          return Center(child: Text('데이터 로드 오류가 발생했습니다.', style: TextStyle(color: AppTheme.textSub)));
        }

        return Center(child: ShadcnSpinner());
      }(),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchNotices(dynamic profile) async {
    final response = await Supabase.instance.client
        .from('notices')
        .select('*, profiles!created_by(full_name)')
        .order('created_at', ascending: false);
    
    // RLS already filters most of it, but we can ensure client-side if needed.
    return List<Map<String, dynamic>>.from(response);
  }

  Widget _buildNoticeCard(BuildContext context, Map<String, dynamic> notice, bool isNew) {
    final dateStr = DateFormat('yyyy.MM.dd').format(DateTime.parse(notice['created_at']));
    final isUrgent = notice['category'] == 'urgent';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isNew ? AppTheme.primaryViolet.withOpacity(0.3) : AppTheme.divider.withOpacity(0.3), width: isNew ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () => _showNoticeDetail(context, notice),
            borderRadius: BorderRadius.circular(32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isUrgent ? Colors.red.withOpacity(0.1) : AppTheme.primaryViolet.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isUrgent ? '긴급' : (notice['category'] == 'event' ? '행사' : '공지'),
                          style: TextStyle(
                            color: isUrgent ? Colors.red : AppTheme.primaryViolet,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(dateStr, style: const TextStyle(fontSize: 11, color: AppTheme.textSub, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    notice['title'],
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textMain, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    notice['content'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          if (isNew)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showNoticeDetail(BuildContext context, Map<String, dynamic> notice) {
    // Mark as read in the database
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Supabase.instance.client.from('notice_reads').upsert({
        'notice_id': notice['id'],
        'user_id': user.id,
      }).then((_) {
        // No explicit setState needed as readIdsAsync will trigger a rebuild naturally
      }).catchError((e) {
        debugPrint('Error marking notice as read: $e');
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 32),
            Text(
              notice['title'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textMain, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('yyyy년 MM월 dd일 HH:mm').format(DateTime.parse(notice['created_at'])),
              style: const TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 24),
            const Divider(color: AppTheme.divider),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  notice['content'],
                  style: const TextStyle(fontSize: 16, color: AppTheme.textMain, height: 1.6, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryViolet,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

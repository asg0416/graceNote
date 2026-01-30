import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:lucide_icons/lucide_icons.dart';

class NoticeListScreen extends ConsumerStatefulWidget {
  const NoticeListScreen({super.key});

  @override
  ConsumerState<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends ConsumerState<NoticeListScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final readIdsAsync = ref.watch(userReadNoticeIdsProvider);
    final noticesAsync = ref.watch(allNoticesProvider);

    final hasData = profileAsync.hasValue && readIdsAsync.hasValue && noticesAsync.hasValue;
    final hasError = profileAsync.hasError || readIdsAsync.hasError || noticesAsync.hasError;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('공지사항', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: () {
        if (hasData) {
          final notices = noticesAsync.value ?? [];
          final readIds = readIdsAsync.value ?? {};

          if (notices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_rounded, size: 64, color: AppTheme.divider),
                  SizedBox(height: 16),
                  Text('등록된 공지사항이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            itemCount: notices.length,
            itemBuilder: (context, index) {
              final notice = notices[index];
              final isUnread = !readIds.contains(notice['id']);
              return NoticeAccordionCard(
                notice: notice,
                isUnread: isUnread,
                onRead: () => _markAsRead(notice['id']),
              );
            },
          );
        }

        if (hasError) {
          return const Center(child: Text('데이터 로드 오류가 발생했습니다.', style: TextStyle(color: AppTheme.textSub)));
        }

        return Center(child: ShadcnSpinner());
      }(),
    );
  }

  void _markAsRead(String noticeId) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Supabase.instance.client.from('notice_reads').upsert({
        'notice_id': noticeId,
        'user_id': user.id,
      }).then((_) {
        // Provider will auto-refresh via stream
      }).catchError((e) {
        debugPrint('Error marking notice as read: $e');
      });
    }
  }
}

class NoticeAccordionCard extends StatefulWidget {
  final Map<String, dynamic> notice;
  final bool isUnread;
  final VoidCallback onRead;

  const NoticeAccordionCard({
    super.key,
    required this.notice,
    required this.isUnread,
    required this.onRead,
  });

  @override
  State<NoticeAccordionCard> createState() => _NoticeAccordionCardState();
}

class _NoticeAccordionCardState extends State<NoticeAccordionCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Pinned notices start collapsed as requested
    _isExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final isPinned = notice['is_pinned'] == true;
    final dateStr = DateFormat('yyyy.MM.dd').format(DateTime.parse(notice['created_at']));
    final publisher = notice['departments']?['name'] ?? '전체';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPinned ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
              if (_isExpanded && widget.isUnread) {
                widget.onRead();
              }
            },
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Top Row: Badges (Wrap)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Scope Badge
                      if (notice['is_global'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF43F5E), // Rose-500
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.globe, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              const Text(
                                '전체',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Pretendard',
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (notice['department_id'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981), // Emerald-500
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.layers, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                notice['departments']?['name'] ?? '부서',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Pretendard',
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1), // Indigo-500
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.church, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              const Text(
                                '장전제일교회',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Pretendard',
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Category Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9), // Slate-100
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          notice['category'] == 'event' ? '행사' : 
                          notice['category'] == 'urgent' ? '긴급' : '일반',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B), // Slate-500
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ),

                      // Pinned Badge
                      if (isPinned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B), // Amber-500
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.pin, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              const Text(
                                '상단 고정',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Pretendard',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 2. Title & Unread Indicator
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notice['title'],
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: isPinned ? FontWeight.w800 : FontWeight.w700,
                            color: const Color(0xFF1E293B),
                            height: 1.4,
                            fontFamily: 'Pretendard',
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (widget.isUnread && !isPinned)
                        Container(
                          margin: const EdgeInsets.only(left: 8, top: 6),
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444), // Red-500
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 3. Footer: Author | Date | Chevron
                  Row(
                    children: [
                      const Icon(LucideIcons.user, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        (notice['is_global'] == true) ? 'GraceNote 관리자' : (notice['profiles']?['full_name'] ?? 'GraceNote 관리자'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8), // Slate-400
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 1,
                        height: 10,
                        color: const Color(0xFFE2E8F0), // Slate-200
                      ),
                      const Icon(LucideIcons.clock, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8), // Slate-400
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        size: 20,
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  notice['content'],
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF475569),
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/repositories/grace_note_repository.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;
import 'package:supabase_flutter/supabase_flutter.dart';

class PrayerCard extends ConsumerStatefulWidget {
  final String prayerId;
  final String groupName;
  final String name;
  final String profileId; // Author profile ID
  final String content;
  final bool isDraft;
  final int togetherCount;
  final String? date;
  final Function(String type, bool isPositive)? onInteractionToggle;
  final Color? groupColor; // [NEW] 조 색상

  const PrayerCard({
    super.key,
    required this.prayerId,
    required this.groupName,
    required this.name,
    required this.profileId,
    required this.content,
    this.isDraft = false,
    this.togetherCount = 0,
    this.date,
    this.onInteractionToggle,
    this.groupColor,
  });

  @override
  ConsumerState<PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends ConsumerState<PrayerCard> {
  // ... (existing state variables)
  bool _isExpanded = false;
  bool _isToggling = false;

  bool _optimisticPraying = false;
  bool _optimisticSaved = false;
  int _optimisticCount = 0;

  // ... (existing _toggleInteraction)
  Future<void> _toggleInteraction(String type) async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;

    final interactions = ref.read(prayerInteractionsProvider(profile.id)).valueOrNull ?? [];
    final bool currentPraying = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'pray');
    final bool currentSaved = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'save');

    if (mounted) {
      setState(() {
        _isToggling = true;
        if (type == 'pray') {
          _optimisticPraying = !currentPraying;
          _optimisticSaved = currentSaved;
          _optimisticCount = widget.togetherCount + (_optimisticPraying ? 1 : -1);
        } else {
          _optimisticSaved = !currentSaved;
          _optimisticPraying = currentPraying;
          _optimisticCount = widget.togetherCount;
        }
      });
    }

    try {
      await ref.read(repositoryProvider).togglePrayerInteraction(
        prayerId: widget.prayerId,
        profileId: profile.id,
        type: type,
      );

      ref.invalidate(prayerInteractionsProvider(profile.id));
      await ref.read(prayerInteractionsProvider(profile.id).future);
      ref.invalidate(savedPrayersProvider(profile.id));

      if (type == 'pray') {
        ref.invalidate(weeklyDataProvider);
        ref.invalidate(departmentWeeklyDataProvider);
      }

      if (widget.onInteractionToggle != null) {
        widget.onInteractionToggle!(type, _optimisticPraying);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '동작에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      // 갱신된 데이터가 위젯의 widget.togetherCount 등으로 들어올 때까지 
      // 약간의 지연을 주어 숫자가 튀는 현상(1->0->1)을 방지
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _isToggling = false);
    }
  }


  Color _getGroupColor(String groupName) {
    // [FIX] Admin에서 설정한 색상이 있으면 우선 적용
    if (widget.groupColor != null) return widget.groupColor!;
    
    // Fallback logic
    if (groupName.contains('효석') || groupName.contains('해비')) return const Color(0xFFEF4444); // Red
    if (groupName.contains('인철') || groupName.contains('호산나')) return const Color(0xFFF59E0B); // Orange
    if (groupName.contains('Re-born') || groupName.contains('새가족')) return const Color(0xFF14B8A6); // Teal/Mint
    return AppTheme.primaryViolet; // Default
  }

  Future<void> _showEditBottomSheet() async {
    final controller = TextEditingController(text: widget.content);
    final newContent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('기도제목 수정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSub),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(fontSize: 16, height: 1.6),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.background,
                hintText: '내용을 입력해주세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: AppTheme.primaryViolet,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('저장하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (newContent != null && newContent.trim() != widget.content.trim()) {
      try {
        await Supabase.instance.client
            .from('prayer_entries')
            .update({'content': newContent.trim()})
            .eq('id', widget.prayerId);

        if (!mounted) return;
        SnackBarUtil.showSnackBar(context, message: '수정되었습니다.');
        ref.invalidate(weeklyDataProvider);
        ref.invalidate(departmentWeeklyDataProvider);
      } catch (e) {
        if (!mounted) return;
        SnackBarUtil.showSnackBar(
          context,
          message: '수정에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final interactionsAsync = profile != null 
        ? ref.watch(prayerInteractionsProvider(profile.id))
        : const AsyncValue<List<Map<String, dynamic>>>.data([]);
    
    final interactions = interactionsAsync.valueOrNull ?? [];
    final bool actualPraying = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'pray');
    final bool actualSaved = interactions.any((i) => i['prayer_id'] == widget.prayerId && i['interaction_type'] == 'save');
    
    final bool displayPraying = _isToggling ? _optimisticPraying : actualPraying;
    final bool displaySaved = _isToggling ? _optimisticSaved : actualSaved;
    
    // widget.togetherCount가 stale해지더라도 _isToggling 동안은 낙관적 값을 우선함
    final int displayCount = _isToggling ? _optimisticCount : widget.togetherCount;

    final String content = widget.content;
    final bool isLong = content.length > 80;
    final bool isOwner = profile?.id == widget.profileId;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryViolet.withOpacity(0.1),
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0] : '?', 
                    style: const TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, fontFamily: 'Pretendard')),
                          const SizedBox(width: 8),
                          if (widget.date != null)
                            Text(
                              widget.date!, 
                              style: const TextStyle(color: AppTheme.textSub, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Pretendard')
                            ),
                          if (widget.isDraft) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange.withOpacity(0.2)),
                              ),
                              child: const Text(
                                '작성 중',
                                style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (widget.groupName.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getGroupColor(widget.groupName).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _getGroupColor(widget.groupName).withOpacity(0.1)),
                          ),
                          child: Text(
                            widget.groupName, 
                            style: TextStyle(
                              color: _getGroupColor(widget.groupName), 
                              fontSize: 10, 
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Pretendard',
                            )
                          ),
                        ),
                    ],
                  ),
                ),
                if (isOwner)
                  IconButton(
                    onPressed: _showEditBottomSheet,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(lucide.LucideIcons.moreHorizontal, size: 20, color: Color(0xFF94A3B8)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content,
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, height: 1.6, color: AppTheme.textMain, fontFamily: 'Pretendard'),
                ),
                if (isLong)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _isExpanded ? '접기' : '...더보기',
                        style: const TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Pretendard'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: _isToggling ? null : () => _toggleInteraction('pray'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          displayPraying ? Icons.favorite : lucide.LucideIcons.heart, 
                          size: 18, 
                          color: displayPraying ? AppTheme.primaryViolet : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayPraying ? '함께 기도 중' : '함께 기도하기', 
                          style: TextStyle(
                            fontSize: 12.5, 
                            color: displayPraying ? AppTheme.primaryViolet : const Color(0xFF94A3B8), 
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                        if (displayCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: displayPraying ? AppTheme.primaryViolet : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$displayCount', 
                              style: TextStyle(
                                fontSize: 10, 
                                color: displayPraying ? Colors.white : const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Pretendard',
                              )
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _isToggling ? null : () => _toggleInteraction('save'),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          displaySaved ? Icons.bookmark : lucide.LucideIcons.bookmark, 
                          size: 18, 
                          color: displaySaved ? AppTheme.primaryViolet : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displaySaved ? '보관 중' : '보관하기',
                          style: TextStyle(
                            fontSize: 12.5, 
                            color: displaySaved ? AppTheme.primaryViolet : const Color(0xFF94A3B8), 
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

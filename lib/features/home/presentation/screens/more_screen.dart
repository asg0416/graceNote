import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';
import 'package:grace_note/features/home/presentation/screens/ai_settings_screen.dart';
import 'package:grace_note/features/home/presentation/screens/saved_prayers_screen.dart';
import 'package:grace_note/features/group_management/presentation/screens/group_leader_admin_screen.dart';
import 'package:grace_note/features/home/presentation/screens/profile_screen.dart';
import 'package:grace_note/features/home/presentation/screens/notice_list_screen.dart';
import 'package:grace_note/features/home/presentation/screens/inquiry_screen.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  void initState() {
    super.initState();
    // [SYNC FIX] 화면 진입 시 소속 정보 및 관련 데이터 강제 갱신
    // 마이크로오스크로 실행하여 빌드 단계와 분리
    Future.microtask(() {
      ref.invalidate(userGroupsProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(unreadInquiryCountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '더보기',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textMain, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _buildProfileCard(context, ref),
            const SizedBox(height: 24),
            _buildMenuSection(
              context: context,
              title: '즐겨찾기',
              items: [
                _MenuItem(
                  icon: Icons.bookmark_rounded, 
                  label: '저장된 기도제목', 
                  color: const Color(0xFF6366F1),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SavedPrayersScreen()),
                    );
                  }
                ),
              ],
            ),
            const SizedBox(height: 16),
            groupsAsync.when(
              data: (groups) {
                final activeRole = ref.watch(activeRoleProvider);
                final isAdminMode = activeRole == AppRole.admin;
                final isLeaderMode = activeRole == AppRole.leader;
                
                return Column(
                  children: [
                    if (isLeaderMode) ...[
                      _buildMenuSection(
                        context: context,
                        title: '사역 관리',
                        items: [
                          _MenuItem(
                            icon: Icons.groups_rounded, 
                            label: '조원 출석 및 기도 관리', 
                            color: const Color(0xFF4F46E5),
                            onTap: () {
                              final group = groups.firstWhere(
                                (g) => g['role_in_group'] == 'leader' || g['role_in_group'] == 'admin',
                                orElse: () => groups.isNotEmpty ? groups.first : <String, dynamic>{},
                              );
                              if (group.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GroupLeaderAdminScreen(
                                    groupId: group['group_id'],
                                    groupName: group['group_name'],
                                  ),
                                ),
                              );
                            }
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildMenuSection(
                      context: context,
                      title: '설정',
                      items: [
                        if (isLeaderMode)
                          _MenuItem(
                            icon: Icons.auto_awesome_rounded, 
                            label: 'AI 스타일 설정', 
                            color: const Color(0xFF818CF8),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AISettingsScreen()),
                              );
                            }
                          ),
                        _MenuItem(
                          icon: Icons.manage_accounts_rounded, 
                          label: '프로필 및 계정 관리', 
                          color: const Color(0xFF8B5CF6),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ProfileScreen()),
                            );
                          }
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            _buildMenuSection(
              context: context,
              title: '고객지원',
              items: [
                _MenuItem(
                  icon: Icons.campaign_rounded, 
                  label: '공지사항', 
                  color: const Color(0xFFEC4899),
                  showBadge: ref.watch(hasNewNoticesProvider).value ?? false,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NoticeListScreen()),
                    );
                  }
                ),
                _MenuItem(
                  icon: Icons.chat_bubble_rounded, 
                  label: '1:1 문의하기', 
                  color: const Color(0xFF10B981),
                  showBadge: (ref.watch(unreadInquiryCountProvider).value ?? 0) > 0,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const InquiryScreen()),
                    );
                  }
                ),
                _MenuItem(
                  icon: Icons.menu_book_rounded, 
                  label: '서비스 가이드 및 FAQ', 
                  color: const Color(0xFF64748B),
                  onTap: () {
                    _showServiceGuide(context);
                  }
                ),
              ],
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('로그아웃'),
                      content: const Text('정말 로그아웃 하시겠습니까?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('로그아웃', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    // 1. Sign out from Supabase
                    await Supabase.instance.client.auth.signOut();
                    
                    // 2. [CRITICAL] Invalidate ALL user-specific providers to clear memory cache
                    ref.invalidate(userProfileProvider);
                    ref.invalidate(userProfileFutureProvider); 
                    ref.invalidate(userGroupsProvider);
                    ref.invalidate(prayerInteractionsProvider);
                    ref.invalidate(savedPrayersProvider);
                    ref.invalidate(weeklyDataProvider);
                    ref.invalidate(departmentWeeklyDataProvider);
                    ref.invalidate(weekIdProvider);
                    ref.invalidate(selectedWeekDateProvider); // 날짜 선택 상태도 초기화
                    ref.invalidate(memberPrayerHistoryProvider); // 패밀리 전체 무효화
                    ref.read(activeRoleProvider.notifier).reset(); // 저장된 역할 초기화

                    if (context.mounted) {
                      // 3. Clear all navigations and go to Login
                      Navigator.pushAndRemoveUntil(
                        context, 
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false
                      );
                    }
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
                label: const Text('로그아웃', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w800, fontSize: 15)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: AppTheme.error.withOpacity(0.05),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'v${AppConstants.appVersion}',
                style: const TextStyle(color: AppTheme.textLight, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final groupsAsync = ref.watch(userGroupsProvider);
    final unreadInquiryCount = ref.watch(unreadInquiryCountProvider).value ?? 0;
    final hasNewNotices = ref.watch(hasNewNoticesProvider).value ?? false;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: profileAsync.when(
                    data: (profile) {
                      if (profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty) {
                        return Image.network(profile.avatarUrl!, fit: BoxFit.cover);
                      }
                      return Image.asset(
                        'assets/images/avatar.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: AppTheme.surfaceIndigo,
                          child: const Icon(Icons.person_rounded, size: 50, color: AppTheme.primaryIndigo),
                        ),
                      );
                    },
                    loading: () => Container(color: AppTheme.surfaceIndigo, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (_, __) => Container(color: AppTheme.surfaceIndigo, child: const Icon(Icons.error, size: 50, color: AppTheme.primaryIndigo)),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 20),
          profileAsync.when(
            data: (profile) => Text(
              '${profile?.fullName ?? "성도"}님', 
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textMain)
            ),
            loading: () => const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            error: (_, __) => const Text('이름 정보 없음'),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          groupsAsync.when(
            data: (groups) {
              final profile = profileAsync.value;
              final isGlobalAdmin = profile != null && (profile.role == 'admin' || profile.isMaster);
              final availableRoles = ref.watch(availableRolesProvider);

              // [FIX] UI 렌더링 전 데이터 준비
              Map<String, dynamic>? displayGroup;
              String displayRoleStr = '조원';
              Color displayRoleColor = AppTheme.textSub;

              if (groups.isNotEmpty) {
                final activeRole = ref.watch(activeRoleProvider);
                
                // [Logic Refinement] 현재 역할에 맞는 그룹 찾기
                if (activeRole == AppRole.leader) {
                  displayGroup = groups.firstWhere(
                    (g) => g['role_in_group'] == 'leader', 
                    orElse: () => groups.first
                  );
                  displayRoleStr = '조장';
                  displayRoleColor = const Color(0xFF6366F1);
                } else if (activeRole == AppRole.member) {
                  // 멤버 역할일 때는 role_in_group이 member인 것을 우선하되, 없으면 아무거나
                  displayGroup = groups.firstWhere(
                    (g) => g['role_in_group'] == 'member', 
                    orElse: () => groups.first
                  );
                  displayRoleStr = '조원';
                  displayRoleColor = AppTheme.textSub;
                } else if (activeRole == AppRole.admin) {
                  displayGroup = groups.firstWhere(
                    (g) => g['role_in_group'] == 'admin', 
                    orElse: () => groups.first
                  );
                  displayRoleStr = '관리자';
                  displayRoleColor = const Color(0xFFF59E0B);
                } else {
                  displayGroup = groups.first;
                }
              }

              return InkWell(
                onTap: availableRoles.length > 1 ? () => _showRoleSelectionSheet(context, ref) : null,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Column(
                    children: [
                      if (groups.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isGlobalAdmin ? const Color(0xFFF59E0B).withOpacity(0.1) : AppTheme.divider.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isGlobalAdmin ? (profile.isMaster ? '전체 관리자' : '교회 관리자') : '소속 정보 없음', 
                            style: TextStyle(
                              color: isGlobalAdmin ? const Color(0xFFF59E0B) : AppTheme.textSub, 
                              fontSize: 13, 
                              fontWeight: FontWeight.w600
                            )
                          ),
                        )
                      else if (displayGroup != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: displayRoleColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: displayRoleColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${displayGroup['group_name']} ',
                                style: TextStyle(
                                  color: AppTheme.textMain,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Container(
                                width: 1, 
                                height: 12, 
                                color: AppTheme.divider,
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              Text(
                                displayRoleStr,
                                style: TextStyle(
                                  color: displayRoleColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (availableRoles.length > 1) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: displayRoleColor,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Text('로딩 중...', style: TextStyle(color: AppTheme.textSub, fontSize: 14)),
            error: (_, __) => const Text('소속 정보 오류', style: TextStyle(color: AppTheme.textSub, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: textColor),
        ],
      ),
    );
  }

  Widget _buildMenuSection({required BuildContext context, required String title, required List<_MenuItem> items}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textSub)),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isLast = index == items.length - 1;

                return Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(item.icon, size: 22, color: item.color),
                      ),
                      title: Text(item.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMain)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.showBadge)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            ),
                          const Icon(Icons.arrow_forward_ios, color: AppTheme.divider, size: 16),
                        ],
                      ),
                      onTap: item.onTap,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: index == 0 ? const Radius.circular(24) : Radius.zero,
                          bottom: isLast ? const Radius.circular(24) : Radius.zero,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(height: 1, color: AppTheme.divider.withOpacity(0.5)),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final bool showBadge;
  final VoidCallback onTap;
  _MenuItem({required this.icon, required this.label, required this.color, required this.onTap, this.showBadge = false});
}

extension MoreScreenRoleExtension on _MoreScreenState {
  void _showRoleSelectionSheet(BuildContext context, WidgetRef ref) {
    final availableRoles = ref.watch(availableRolesProvider);
    final activeRole = ref.watch(activeRoleProvider);
    final groups = ref.watch(userGroupsProvider).value ?? [];
    final groupName = groups.isNotEmpty ? groups.first['group_name'] : '소속 조';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
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
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '역할 선택',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textMain),
            ),
            const SizedBox(height: 8),
            const Text(
              '전환할 역할을 선택해 주세요.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSub),
            ),
            const SizedBox(height: 24),
            ...availableRoles.map((role) {
              final isSelected = activeRole == role;
              String label = role.label;
              if (role == AppRole.leader) {
                label = '$groupName 조장';
              } else if (role == AppRole.member) {
                label = '$groupName 조원';
              } else if (role == AppRole.admin) {
                label = '전체 관리자';
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    ref.read(activeRoleProvider.notifier).setRole(role);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryIndigo.withOpacity(0.05) : AppTheme.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryIndigo.withOpacity(0.3) : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                            color: isSelected ? AppTheme.primaryIndigo : AppTheme.textMain,
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: AppTheme.primaryIndigo, size: 24),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }

  void _showServiceGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '서비스 가이드',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textMain),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildGuideSection(
                      '시스템 운영 정책',
                      '그레이스노트는 교회의 승인을 받은 분들만 이용할 수 있는 폐쇄형 서비스입니다.\n\n'
                      '• 관리자가 사전에 등록한 성도 정보(이름, 전화번호)가 일치해야 가입 및 이용이 가능합니다.\n'
                      '• 소속된 조(그룹)가 있어야 앱의 주요 기능을 사용할 수 있습니다.'
                    ),
                    _buildGuideSection(
                      '메인 화면 (나의 기도)',
                      '나의 기도 제목을 작성하고 AI의 도움을 받아 정제할 수 있습니다.\n\n'
                      '• AI 정제: 작성한 기도 제목을 더 깊이 있고 은혜로운 문장으로 다듬어줍니다.\n'
                      '• 공유 설정: 작성한 기도는 소속된 조원들에게만 공유됩니다.'
                    ),
                    _buildGuideSection(
                      '기도소식',
                      '우리 조원들과 교회 전체의 기도 제목을 확인하고 함께 기도할 수 있습니다.\n\n'
                      '• 아멘: 함께 기도하고 있다는 마음을 표현할 수 있습니다.\n'
                      '• 저장하기: 나중에 다시 보고 싶은 기도 제목을 즐겨찾기에 추가할 수 있습니다.'
                    ),
                    _buildGuideSection(
                      '자주 묻는 질문 (FAQ)',
                      'Q. 회원가입이 안 돼요.\n'
                      'A. 관리자가 성도님을 사전에 등록하지 않았거나, 입력하신 전화번호가 등록된 정보와 다를 수 있습니다. 관리자에게 문의해 주세요.\n\n'
                      'Q. 조편성 정보가 달라요.\n'
                      'A. 관리자(또는 조장)가 조편성을 변경한 후 "변경사항 확정"을 눌러야 앱에 반영됩니다.'
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primaryIndigo),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: const TextStyle(fontSize: 14, color: AppTheme.textMain, height: 1.6),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _isLoading = false;

  Future<void> _updatePreference(String field, bool value) async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({field: value})
            .eq('id', user.id);
        
        // Refresh profile provider manually
        ref.invalidate(userProfileProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '알림 설정', 
          style: TextStyle(
            fontWeight: FontWeight.w800, 
            color: AppTheme.textMain, 
            fontSize: 17, 
            fontFamily: 'Pretendard', 
            letterSpacing: -0.5
          )
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text('프로필을 불러올 수 없습니다.'));

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  '알림 수신 설정', 
                  '각 항목별 알림 수신 여부를 개별적으로 설정할 수 있습니다.'
                ),
                
                _buildSelectionContainer(
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        title: '기도제목 알림',
                        subtitle: '조원들의 새로운 기도제목 등록 시 알림',
                        value: profile.pushPrayerEnabled,
                        onChanged: (val) => _updatePreference('push_prayer_enabled', val),
                      ),
                      _buildInnerDivider(),
                      _buildSwitchTile(
                        title: '공지사항 알림',
                        subtitle: '교회 및 부서 공지사항 등록 시 알림',
                        value: profile.pushNoticeEnabled,
                        onChanged: (val) => _updatePreference('push_notice_enabled', val),
                      ),
                      _buildInnerDivider(),
                      _buildSwitchTile(
                        title: '활동 리마인더',
                        subtitle: '출석체크 및 기도제목 미제출 시 리마인더',
                        value: profile.pushReminderEnabled,
                        onChanged: (val) => _updatePreference('push_reminder_enabled', val),
                      ),
                    ],
                  ),
                ),
                
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet),
                        strokeWidth: 3,
                      ),
                    ),
                  ),

                const SizedBox(height: 40),
                _buildInfoCard(),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet))),
        error: (e, _) => Center(child: Text('에러 발생: $e')),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
              fontFamily: 'Pretendard',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSub.withOpacity(0.7),
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildInnerDivider() {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: _isLoading ? null : onChanged,
      activeColor: AppTheme.primaryViolet,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800, 
          fontSize: 15, 
          color: AppTheme.textMain, 
          fontFamily: 'Pretendard'
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13, 
          color: AppTheme.textSub.withOpacity(0.6), 
          fontFamily: 'Pretendard'
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryViolet.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryViolet.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.primaryViolet, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '앱 푸시 알림을 통해 교회 소식을 가장 빠르게 받아보실 수 있습니다. 원치 않는 알림은 언제든지 이곳에서 끄실 수 있습니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.primaryViolet.withOpacity(0.7),
                fontWeight: FontWeight.w500,
                height: 1.5,
                fontFamily: 'Pretendard',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/models/models.dart';
import 'package:grace_note/core/providers/user_role_provider.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  // Optimistic update for personal toggles
  final Map<String, bool> _optimistic = {};

  // Department schedule settings (admin only)
  Map<String, dynamic>? _deptSettings;
  bool _deptLoading = true;
  String? _departmentId;

  bool _getValue(String field, bool profileValue) =>
      _optimistic.containsKey(field) ? _optimistic[field]! : profileValue;

  Future<void> _updatePreference(String field, bool value) async {
    final previous = _optimistic[field];
    setState(() => _optimistic[field] = value);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({field: value})
            .eq('id', user.id);
      }
    } catch (e) {
      // Rollback on failure
      if (mounted) {
        setState(() {
          if (previous != null) {
            _optimistic[field] = previous;
          } else {
            _optimistic.remove(field);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _loadDeptSettings(String departmentId) async {
    try {
      final res = await Supabase.instance.client
          .from('departments')
          .select('leader_reminder_enabled, leader_reminder_days, leader_reminder_time, climbing_alert_enabled, climbing_alert_day, climbing_alert_time')
          .eq('id', departmentId)
          .single();
      if (mounted) {
        setState(() {
          _deptSettings = Map<String, dynamic>.from(res);
          _deptLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _deptLoading = false);
    }
  }

  Future<void> _updateDeptSetting(String field, dynamic value) async {
    if (_departmentId == null || _deptSettings == null) return;
    final previous = _deptSettings![field];
    setState(() => _deptSettings![field] = value);
    try {
      await Supabase.instance.client
          .from('departments')
          .update({field: value})
          .eq('id', _departmentId!);
    } catch (e) {
      if (mounted) {
        setState(() => _deptSettings![field] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('부서 설정 저장 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final activeRole = ref.watch(activeRoleProvider);
    final activeMembership = ref.watch(activeMembershipProvider);

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
            letterSpacing: -0.5,
          ),
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
        skipError: true, // [FIX] 일시적 Realtime 에러 시 에러 화면 전환 방지 (다른 화면과 동일 처리)
        data: (profile) {
          if (profile == null) return const Center(child: Text('프로필을 불러올 수 없습니다.'));

          // [FIX] Use activeRole and activeMembership for context-aware UI
          final isAdmin = activeRole == AppRole.admin;
          final targetDepartmentId = activeMembership?.departmentId ?? profile.departmentId;

          // Load dept settings once for admin, or if department changes
          if (isAdmin && targetDepartmentId != null && _departmentId != targetDepartmentId) {
            _departmentId = targetDepartmentId;
            _deptLoading = true;
            Future.microtask(() => _loadDeptSettings(targetDepartmentId));
          }

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section 1: Personal notification toggles
                _buildSectionHeader(
                  '알림 수신 설정',
                  '각 항목별 알림 수신 여부를 개별적으로 설정할 수 있습니다.',
                ),
                _buildSelectionContainer(
                  child: Column(
                    children: [
                      _buildSwitchTile(
                        title: '기도제목 알림',
                        subtitle: '조원들의 새로운 기도제목 등록 시 알림',
                        value: _getValue('push_prayer_enabled', profile.pushPrayerEnabled),
                        onChanged: (val) => _updatePreference('push_prayer_enabled', val),
                      ),
                      _buildInnerDivider(),
                      _buildSwitchTile(
                        title: '공지사항 알림',
                        subtitle: '교회 및 부서 공지사항 등록 시 알림',
                        value: _getValue('push_notice_enabled', profile.pushNoticeEnabled),
                        onChanged: (val) => _updatePreference('push_notice_enabled', val),
                      ),
                      if (!isAdmin) ...[
                        _buildInnerDivider(),
                        _buildSwitchTile(
                          title: '활동 리마인더',
                          subtitle: '출석체크 및 기도제목 미제출 시 리마인더',
                          value: _getValue('push_reminder_enabled', profile.pushReminderEnabled),
                          onChanged: (val) => _updatePreference('push_reminder_enabled', val),
                        ),
                      ],
                    ],
                  ),
                ),

                // Section 2: Department schedule (admin only)
                if (isAdmin && targetDepartmentId != null) ...[
                  const SizedBox(height: 40),
                  _buildSectionHeader(
                    '부서 자동 알림 스케줄',
                    '부서 조장들에게 자동으로 발송되는 알림을 설정합니다.',
                  ),
                  if (_deptLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet),
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  else if (_deptSettings != null) ...[
                    // Leader Reminder
                    _buildScheduleCard(
                      title: '조장 리마인더 (미제출자)',
                      subtitle: '출석/기도 미등록 조의 조장에게 리마인더 발송',
                      enabled: _deptSettings!['leader_reminder_enabled'] ?? false,
                      onToggle: (val) => _updateDeptSetting('leader_reminder_enabled', val),
                      days: List<int>.from(_deptSettings!['leader_reminder_days'] ?? []),
                      multiSelectDays: true,
                      onDaysChanged: (days) => _updateDeptSetting('leader_reminder_days', days),
                      time: _parseTime(_deptSettings!['leader_reminder_time']),
                      onTimeChanged: (time) => _updateDeptSetting(
                        'leader_reminder_time',
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00',
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Climbing Alert
                    _buildScheduleCard(
                      title: '새가족 등반 알림',
                      subtitle: '등반 예정자가 있는 경우 관리자 및 새가족조 조장에게 자동 알림',
                      enabled: _deptSettings!['climbing_alert_enabled'] ?? false,
                      onToggle: (val) => _updateDeptSetting('climbing_alert_enabled', val),
                      days: [_deptSettings!['climbing_alert_day'] ?? 5],
                      multiSelectDays: false,
                      onDaysChanged: (days) {
                        if (days.isNotEmpty) _updateDeptSetting('climbing_alert_day', days.last);
                      },
                      time: _parseTime(_deptSettings!['climbing_alert_time']),
                      onTimeChanged: (time) => _updateDeptSetting(
                        'climbing_alert_time',
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00',
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 40),
                _buildInfoCard(),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryViolet),
          ),
        ),
        error: (e, _) => Center(child: Text('에러 발생: $e')),
      ),
    );
  }

  TimeOfDay _parseTime(dynamic timeStr) {
    if (timeStr == null) return const TimeOfDay(hour: 22, minute: 0);
    final parts = timeStr.toString().split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 22,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  Widget _buildScheduleCard({
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required List<int> days,
    required bool multiSelectDays,
    required ValueChanged<List<int>> onDaysChanged,
    required TimeOfDay time,
    required ValueChanged<TimeOfDay> onTimeChanged,
  }) {
    return _buildSelectionContainer(
      child: Column(
        children: [
          // Toggle header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.textMain,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub.withOpacity(0.6),
                          fontFamily: 'Pretendard',
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onToggle,
                  activeColor: AppTheme.primaryViolet,
                ),
              ],
            ),
          ),
          // Day & time selection (only shown when enabled)
          if (enabled) ...[
            _buildInnerDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    multiSelectDays ? '알림 요일' : '알림 요일 (매주 1회)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub.withOpacity(0.7),
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildDaySelector(
                    selectedDays: days,
                    multiSelect: multiSelectDays,
                    onChanged: onDaysChanged,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '알림 발송 시간',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSub.withOpacity(0.7),
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildTimePicker(time: time, onChanged: onTimeChanged),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDaySelector({
    required List<int> selectedDays,
    required bool multiSelect,
    required ValueChanged<List<int>> onChanged,
  }) {
    const dayLabels = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: List.generate(7, (idx) {
        final isSelected = selectedDays.contains(idx);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: idx < 6 ? 6 : 0),
            child: GestureDetector(
              onTap: () {
                if (multiSelect) {
                  final newDays = List<int>.from(selectedDays);
                  if (isSelected) {
                    newDays.remove(idx);
                  } else {
                    newDays.add(idx);
                    newDays.sort();
                  }
                  onChanged(newDays);
                } else {
                  onChanged([idx]);
                }
              },
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryViolet : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryViolet : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  dayLabels[idx],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppTheme.textSub,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTimePicker({
    required TimeOfDay time,
    required ValueChanged<TimeOfDay> onChanged,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(primary: AppTheme.primaryViolet),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 18, color: AppTheme.textSub.withOpacity(0.5)),
            const SizedBox(width: 10),
            Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMain,
                fontFamily: 'Pretendard',
              ),
            ),
          ],
        ),
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
      onChanged: onChanged,
      activeColor: AppTheme.primaryViolet,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: AppTheme.textMain,
          fontFamily: 'Pretendard',
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: AppTheme.textSub.withOpacity(0.6),
          fontFamily: 'Pretendard',
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

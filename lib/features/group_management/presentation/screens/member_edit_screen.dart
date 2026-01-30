import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/snack_bar_util.dart';
import '../../../../core/utils/database_error_helper.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class MemberEditScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? member;
  final String groupId;
  final String groupName;

  const MemberEditScreen({
    super.key,
    this.member,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends ConsumerState<MemberEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _birthController;
  late final TextEditingController _weddingController;
  late final TextEditingController _spouseController;
  late final TextEditingController _childrenController;
  late final TextEditingController _notesController;

  bool _isActive = true;
  bool _isSaving = false;
  String? _selectedGroupId;
  String? _selectedGroupName;
  String _groupSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.groupId;
    _selectedGroupName = widget.groupName;
    _nameController = TextEditingController(text: widget.member?['full_name']);
    _phoneController = TextEditingController(text: widget.member?['phone']);
    _birthController = TextEditingController(text: widget.member?['birth_date']);
    _weddingController = TextEditingController(text: widget.member?['wedding_anniversary']);
    _spouseController = TextEditingController(text: widget.member?['spouse_name']);
    _childrenController = TextEditingController(text: widget.member?['children_info']);
    _notesController = TextEditingController(text: widget.member?['notes']);
    _isActive = widget.member?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _birthController.dispose();
    _weddingController.dispose();
    _spouseController.dispose();
    _childrenController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    DateTime? initialDate;
    if (controller.text.isNotEmpty) {
      try {
        initialDate = DateTime.parse(controller.text);
      } catch (_) {}
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryViolet,
              onPrimary: Colors.white,
              onSurface: AppTheme.textMain,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '이름을 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(repositoryProvider);
      final profile = ref.read(userProfileProvider).value;
      
      if (profile == null) {
        throw Exception('프로필 정보를 불러올 수 없습니다. 네트워크 상태를 확인해주세요.');
      }
      
      final data = {
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'birth_date': _birthController.text.trim().isEmpty ? null : _birthController.text.trim(),
        'wedding_anniversary': _weddingController.text.trim().isEmpty ? null : _weddingController.text.trim(),
        'spouse_name': _spouseController.text.trim().isEmpty ? null : _spouseController.text.trim(),
        'children_info': _childrenController.text.trim().isEmpty ? null : _childrenController.text.trim(),
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'group_name': _selectedGroupName, // 변경된 조 이름 반영
        'is_active': _isActive, // 상태 반영
      };

      if (widget.member == null) {
        // Add new
        await repo.addDirectoryMember({
          ...data,
          'church_id': profile.churchId,
          'department_id': profile.departmentId,
        });
      } else {
        // Update existing
        await repo.updateDirectoryMember(widget.member!['id'], data);
        
        // 조가 변경되었고 연동된 프로필이 있는 경우 group_members도 업데이트 시도
        if (_selectedGroupId != widget.groupId && widget.member!['profile_id'] != null) {
          await repo.completeOnboarding(
            profileId: widget.member!['profile_id'], 
            fullName: _nameController.text.trim(),
             churchId: profile.churchId,
            groupId: _selectedGroupId,
          );
        }
      }

      ref.invalidate(groupMembersProvider(widget.groupId));
      if (_selectedGroupId != widget.groupId) {
        ref.invalidate(groupMembersProvider(_selectedGroupId!));
      }
      
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: '정보가 성공적으로 저장되었습니다.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: DatabaseErrorHelper.getFriendlyMessage(e),
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleGroupChange(String newGroupId, String newGroupName) async {
    if (newGroupId == _selectedGroupId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('소속 조 변경'),
        content: Text('조원을 [$newGroupName]으로 이동시키겠습니까?\n이동 시 기존 출석 및 기도제목 데이터의 소속 정보도 함께 변경될 수 있습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('변경하기', style: TextStyle(color: AppTheme.primaryViolet)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedGroupId = newGroupId;
        _selectedGroupName = newGroupName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.member == null ? '조원 등록' : '조원 정보 수정', 
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('기본 정보', '조원의 성함과 연락처를 입력하세요.'),
                  _buildTextField(
                    controller: _nameController,
                    label: '이름',
                    hint: '성함(본명) 입력',
                  ),
                  _buildTextField(
                    controller: _phoneController,
                    label: '연락처',
                    hint: '010-0000-0000',
                    keyboardType: TextInputType.phone,
                  ),
                  
                  _buildDivider(),
                  
                  _buildSectionHeader('중요 기념일', '생일과 결혼기념일을 관리합니다.'),
                  _buildDateField(
                    context: context,
                    controller: _birthController,
                    label: '생년월일',
                  ),
                  _buildDateField(
                    context: context,
                    controller: _weddingController,
                    label: '결혼기념일',
                  ),
                  
                  _buildDivider(),
                  
                  _buildSectionHeader('가족 및 기타', '가족 관계와 추가 참고 사항을 기록하세요.'),
                  _buildTextField(
                    controller: _spouseController,
                    label: '배우자 성함',
                    hint: '배우자 성함 입력',
                  ),
                  _buildTextField(
                    controller: _childrenController,
                    label: '자녀 정보',
                    hint: '자녀 이름, 나이 등',
                  ),
                  _buildTextField(
                    controller: _notesController,
                    label: '메모 사항',
                    hint: '심방 내용이나 특이사항을 자유롭게 기록하세요',
                    maxLines: 5,
                  ),

                  if (widget.member != null) ...[
                    _buildDivider(),

                    _buildSectionHeader('소속 조 설정', '조원을 다른 조로 이동시키거나 소속을 변경합니다.'),
                    _buildGroupSelector(ref),

                    _buildDivider(),

                    _buildSectionHeader('계정 상태 설정', '조원을 비활성화하면 명단에서 제외되지만 데이터는 보존됩니다.'),
                    _buildStatusToggle(),
                  ],

                  const SizedBox(height: 48),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          // 하단 저장 버튼 (Bottom Save Button)
          Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: AppTheme.border, width: 1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryViolet,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Pretendard',
                  ),
                ),
                child: _isSaving 
                  ? const SizedBox(width: 24, height: 24, child: ShadcnSpinner())
                  : const Text('변경사항 저장하기'),
              ),
            ),
          ),
        ],
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

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Divider(color: AppTheme.border, thickness: 1),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0), // 선명한 회색 테두리
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              cursorColor: AppTheme.primaryViolet,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                fontFamily: 'Pretendard',
                color: AppTheme.textMain,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: AppTheme.textSub.withOpacity(0.35),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  fontFamily: 'Pretendard',
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                fillColor: Colors.white,
                filled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _selectDate(context, controller),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0), // 선명한 회색 테두리
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      controller.text.isEmpty ? '날짜 선택' : controller.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        fontFamily: 'Pretendard',
                        color: controller.text.isEmpty 
                          ? AppTheme.textSub.withOpacity(0.35) 
                          : AppTheme.textMain,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppTheme.textSub.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildStatusToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isActive ? const Color(0xFFE2E8F0) : Colors.red.withOpacity(0.3), 
          width: _isActive ? 1.0 : 2.0
        ),
      ),
      child: SwitchListTile(
        value: _isActive,
        onChanged: (val) => setState(() => _isActive = val),
        title: Text(
          _isActive ? '현재 활동 중' : '현재 비활성화 상태',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: _isActive ? AppTheme.textMain : Colors.red,
            fontFamily: 'Pretendard',
          ),
        ),
        subtitle: Text(
          _isActive ? '조원 명단에 노출됩니다.' : '명단에서 숨겨지며 출석 체크 대상에서 제외됩니다.',
          style: TextStyle(
            fontSize: 13,
            color: _isActive ? AppTheme.textSub.withOpacity(0.6) : Colors.red.withOpacity(0.6),
            fontFamily: 'Pretendard',
          ),
        ),
        activeColor: AppTheme.primaryViolet,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildGroupSelector(WidgetRef ref) {
    // 조장 여부 판별 로직 추가
    final bool isLeaderOrAdmin = widget.member?['profiles'] != null && 
        (widget.member!['profiles']?['role_in_group'] == 'leader' || 
         widget.member!['profiles']?['role_in_group'] == 'admin');

    if (isLeaderOrAdmin) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(lucide.LucideIcons.alertTriangle, color: Colors.amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.groupName}의 조장/관리자입니다.',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textMain, fontFamily: 'Pretendard'),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '조장은 다른 조로 이동할 수 없습니다.\n직본을 먼저 변경해주세요.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub, height: 1.4, fontFamily: 'Pretendard'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final profileAsync = ref.watch(userProfileProvider);
    
    return profileAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        
        final groupsAsync = ref.watch(departmentGroupsProvider(profile.departmentId!));
        
        return groupsAsync.when(
          data: (groups) {
            final filteredGroups = groups.where((g) => 
               g['name'].toString().toLowerCase().contains(_groupSearchQuery.toLowerCase())
            ).toList();

            return Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
              ),
              child: shad.ShadSelect<String>.withSearch(
                placeholder: const Text('조 이동', style: TextStyle(fontSize: 15, color: AppTheme.textSub, fontFamily: 'Pretendard')),
                initialValue: _selectedGroupId,
                minWidth: double.infinity,
                maxHeight: 400,
                decoration: shad.ShadDecoration(
                  border: shad.ShadBorder.none,
                ),
                onChanged: (val) {
                  if (val != null) {
                    final group = groups.firstWhere((g) => g['id'].toString() == val);
                    _handleGroupChange(val, group['name'].toString());
                  }
                },
                selectedOptionBuilder: (context, value) {
                  final group = groups.firstWhere((g) => g['id'].toString() == value, orElse: () => groups.first);
                  return Text(
                    group['name'].toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textMain,
                      fontFamily: 'Pretendard',
                    ),
                  );
                },
                options: filteredGroups.map((g) => shad.ShadOption(
                  value: g['id'] as String,
                  child: Text(g['name'] as String, style: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w500, fontSize: 14)),
                )).toList(),
                searchPlaceholder: const Text('조 이름을 입력하세요', style: TextStyle(fontFamily: 'Pretendard', fontSize: 14)),
                onSearchChanged: (query) => setState(() => _groupSearchQuery = query),
              ),
            );
          },
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
          error: (_, __) => const Text('그룹 정보를 불러올 수 없습니다.'),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

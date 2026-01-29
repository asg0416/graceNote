import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/snack_bar_util.dart';
import '../../../../core/utils/database_error_helper.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

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

  @override
  void initState() {
    super.initState();
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
        'group_name': widget.groupName, // 조 이름 동기화 강제
      };

      if (widget.member == null) {
        // Add new
        await repo.addDirectoryMember({
          ...data,
          'church_id': profile?.churchId,
          'department_id': profile?.departmentId,
          'group_name': widget.groupName,
        });
      } else {
        // Update existing
        await repo.updateDirectoryMember(widget.member!['id'], data);
      }

      ref.invalidate(groupMembersProvider(widget.groupId));
      
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

  Future<void> _toggleActive() async {
    final bool currentStatus = _isActive;
    final String actionText = currentStatus ? '비활성화' : '활성화';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('조원 $actionText'),
        content: Text('이 조원을 $actionText 하시겠습니까?\n${currentStatus ? '비활성화하면 조원 목록에서 보이지 않게 됩니다.' : '활성화하면 다시 조원 목록에 나타납니다.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(actionText, style: TextStyle(color: currentStatus ? Colors.red : AppTheme.primaryViolet)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(repositoryProvider).toggleMemberActivation(widget.member!['id'], !currentStatus);
      ref.invalidate(groupMembersProvider(widget.groupId));
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: '성공적으로 $actionText 되었습니다.');
        Navigator.pop(context); // To member list
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.member == null ? '조원 등록' : '조원 정보 수정', 
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving 
              ? SizedBox(width: 20, height: 20, child: ShadcnSpinner())
              : const Text('저장', style: TextStyle(color: AppTheme.primaryViolet, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            _buildInfoCard(
              title: '기본 정보',
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: '이름',
                  hint: '성함(본명)을 입력하세요',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  label: '연락처',
                  hint: '010-0000-0000',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoCard(
              title: '중요 기념일',
              children: [
                _buildDateField(
                  context: context,
                  controller: _birthController,
                  label: '생년월일',
                  icon: Icons.cake_outlined,
                ),
                const SizedBox(height: 16),
                _buildDateField(
                  context: context,
                  controller: _weddingController,
                  label: '결혼기념일',
                  icon: Icons.favorite_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoCard(
              title: '가족 및 기타',
              children: [
                _buildTextField(
                  controller: _spouseController,
                  label: '배우자 성함',
                  hint: '배우자 성함을 입력하세요',
                  icon: Icons.people_outline_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _childrenController,
                  label: '자녀 정보',
                  hint: '자녀 이름, 나이 등을 입력하세요',
                  icon: Icons.child_care_rounded,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _notesController,
                  label: '메모 사항',
                  hint: '특이사항이나 심방 내용 등을 기록하세요',
                  icon: Icons.notes_rounded,
                  maxLines: 4,
                ),
              ],
            ),
            if (widget.member != null) ...[
              const SizedBox(height: 40),
              TextButton.icon(
                onPressed: _isSaving ? null : _toggleActive,
                icon: Icon(_isActive ? Icons.person_off_rounded : Icons.person_add_rounded, size: 18),
                label: Text(_isActive ? '조원 비활성화하기' : '조원 다시 활성화하기'),
                style: TextButton.styleFrom(
                  foregroundColor: _isActive ? Colors.red : AppTheme.primaryViolet,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _isActive ? Colors.red.withOpacity(0.2) : AppTheme.primaryViolet.withOpacity(0.2)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.textSub,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppTheme.primaryViolet.withOpacity(0.4), size: 20),
          labelStyle: TextStyle(color: AppTheme.textSub.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 13),
          hintStyle: TextStyle(color: AppTheme.textSub.withOpacity(0.2), fontWeight: FontWeight.w500, fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildDateField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: () => _selectDate(context, controller),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: AbsorbPointer(
          child: TextField(
            controller: controller,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            decoration: InputDecoration(
              labelText: label,
              hintText: '날짜를 선택하세요',
              prefixIcon: Icon(icon, color: AppTheme.primaryViolet.withOpacity(0.4), size: 20),
              labelStyle: TextStyle(color: AppTheme.textSub.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 13),
              hintStyle: TextStyle(color: AppTheme.textSub.withOpacity(0.2), fontWeight: FontWeight.w500, fontSize: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
            ),
          ),
        ),
      ),
    );
  }
}

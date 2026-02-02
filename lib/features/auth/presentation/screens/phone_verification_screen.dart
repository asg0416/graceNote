import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:grace_note/core/error/exceptions.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/church_selection_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/group_selection_screen.dart';
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends ConsumerState<PhoneVerificationScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  
  bool _isCodeSent = false;
  bool _isLoading = false;
  Timer? _timer;
  int _remainingTime = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _remainingTime = 180;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTime > 0) {
        setState(() => _remainingTime--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _timerString {
    final minutes = (_remainingTime / 60).floor();
    final seconds = _remainingTime % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      SnackBarUtil.showSnackBar(context, message: '올바른 휴대폰 번호를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(repositoryProvider);
      await repo.sendVerificationSMS(phone);

      setState(() {
        _isCodeSent = true;
      });
      _startTimer();
      _codeController.clear();
      
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: '인증번호가 발송되었습니다.');
      }
    } on AccountExistsException catch (e) {
      if (mounted) {
        _showAccountExistsDialog(e);
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('FunctionException: ', '');
        if (msg.contains('{')) msg = msg.split('{')[0].trim();
        SnackBarUtil.showSnackBar(context, message: msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    
    if (name.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '성함(실명)을 입력해주세요.', isError: true);
      return;
    }
    if (code.length < 4) return;

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final repo = ref.read(repositoryProvider);
      final result = await repo.verifySMS(phone, code, fullName: name);
      final List<dynamic> matchedMembers = result['matched_members'] ?? [];
      
      final profile = ref.read(userProfileProvider).value;
      final isAdmin = profile?.role == 'admin' || (profile?.adminStatus != null && profile!.adminStatus != 'none');

      if (isAdmin && profile?.phone != null && profile!.phone!.isNotEmpty) {
        final cleanProfilePhone = profile.phone!.replaceAll(RegExp(r'[^0-9]'), '');
        final cleanVerifiedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
        
        if (cleanProfilePhone != cleanVerifiedPhone) {
          if (mounted) {
            SnackBarUtil.showSnackBar(
              context, 
              message: '가입 시 입력하신 번호와 인증하신 번호가 일치하지 않습니다.\n관리자에게 문의해 주세요.', 
              isError: true,
            );
          }
          return;
        }
      }

      if (matchedMembers.isEmpty) {
        if (isAdmin) {
          await repo.completeOnboarding(
            profileId: user!.id,
            fullName: profile!.fullName,
            churchId: profile.churchId,
            phone: phone,
          );
          if (mounted) {
            SnackBarUtil.showSnackBar(context, message: '관리자 인증이 완료되었습니다.');
            ref.invalidate(userProfileProvider);
          }
          return;
        }
        if (mounted) {
          SnackBarUtil.showSnackBar(
            context, 
            message: '성도 명부에 등록되지 않은 번호입니다.\n교회 담당자에게 문의해 주세요.', 
            isError: true,
          );
        }
        return;
      }

      // [NEW] 중복 성도 or 단일 성도 처리
      // 모두 동일한 churchId를 가진다고 가정 (같은 전화번호니까)
      final firstMatch = matchedMembers.first;
      final churchId = firstMatch['church_id'];
      
      final churchRes = await Supabase.instance.client
          .from('churches')
          .select('name')
          .eq('id', churchId)
          .single();
      final churchName = churchRes['name'];

      if (mounted) {
        if (isAdmin) {
          if (user != null) {
            await Supabase.instance.client.from('profiles').upsert({
              'id': user.id,
              'full_name': profile!.fullName,
              'email': user.email,
              'church_id': churchId,
              'phone': phone,
            });
          }
          // 관리자는 첫 번째 매칭 정보로 진행 (또는 관리자용 로직)
          await repo.completeOnboarding(
             profileId: user!.id,
             fullName: profile!.fullName,
             churchId: churchId,
             phone: phone,
             matchedData: Map<String, dynamic>.from(firstMatch),
          );

          // [FIX] 관리자도 데이터 동기화 대기
          if (mounted) {
            setState(() => _isLoading = true);
            await ref.read(userProfileFutureProvider.future);
          }

           if (mounted) {
            SnackBarUtil.showSnackBar(context, message: '관리자 인증이 완료되었습니다.');
            ref.invalidate(userProfileProvider);
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
          return;
        }

        // 일반 사용자: 중복 여부에 따라 다이얼로그 분기
        bool? isConfirmed;
        Map<String, dynamic>? selectedMatch;

        if (matchedMembers.length > 1) {
           // 중복 성도 다이얼로그 표시
           isConfirmed = await _showMultipleMatchesConfirmationDialog(
             churchName: churchName,
             matches: List<Map<String, dynamic>>.from(matchedMembers),
           );
           // 확인 시 첫 번째 항목 사용 (DB 트리거가 person_id로 나머지 자동 연결)
           if (isConfirmed == true) selectedMatch = Map<String, dynamic>.from(firstMatch);
        } else {
           // 단일 성도 다이얼로그 표시
           selectedMatch = Map<String, dynamic>.from(firstMatch);
           final String departmentName = selectedMatch['departments']?['name'] ?? '부서 미정';
           isConfirmed = await _showMatchConfirmationDialog(
             churchName: churchName,
             departmentName: departmentName,
             groupName: selectedMatch['group_name'] ?? '조 미정',
             role: selectedMatch['role_in_group'] == 'leader' ? '조장' : '조원',
           );
        }

        if (isConfirmed == true && selectedMatch != null) {
            await repo.completeOnboarding(
              profileId: user!.id,
              fullName: name,
              churchId: churchId,
              phone: phone,
              matchedData: selectedMatch,
            );
            
            // [FIX] 가입 완료 후 프로필 정보가 DB 트리거에 의해 생성/업데이트될 때까지 대기
            // AuthGate가 로딩 상태에 빠지는 것을 방지하기 위해 확실히 데이터가 생길 때까지 기다립니다.
            if (mounted) {
              setState(() => _isLoading = true); // 대기 중 로딩 인디케이터 유지
              await ref.read(userProfileFutureProvider.future);
            }

            ref.invalidate(userProfileProvider);
            ref.invalidate(userGroupsProvider);
            
            if (mounted) {
              SnackBarUtil.showSnackBar(context, message: '인증이 완료되었습니다.');
              // [SAFE] 명시적으로 '/'로 이동하여 AuthGate가 다시 판단하게 함
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          } else if (isConfirmed == false) {
             if (mounted) {
               _showContactAdminDialog();
             }
          }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showMatchConfirmationDialog({
    required String churchName,
    required String departmentName,
    required String groupName,
    required String role,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShadDialog(
        title: const Text('정보 확인', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        description: const Text('아래 정보로 본인 인증을 진행할까요?', style: TextStyle(fontFamily: 'Pretendard')),
        actionsAxis: Axis.horizontal,
        expandActionsWhenTiny: false,
        removeBorderRadiusWhenTiny: false,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 320,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(LucideIcons.church, '교회', churchName),
              _buildInfoRow(LucideIcons.layers, '부서', departmentName),
              _buildInfoRow(LucideIcons.users, '소속', groupName),
              _buildInfoRow(LucideIcons.userCheck, '역할', role),
            ],
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('정보가 틀려요', style: TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('네, 맞아요', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  // [NEW] 중복 성도 확인 다이얼로그
  Future<bool?> _showMultipleMatchesConfirmationDialog({
    required String churchName,
    required List<Map<String, dynamic>> matches,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShadDialog(
        title: const Text('정보 확인', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        description: Text(
          '${matches.length}개의 소속 정보가 발견되었습니다.\n모두 본인의 정보가 맞으신가요?',
          style: const TextStyle(height: 1.5, fontFamily: 'Pretendard'),
        ),
        actionsAxis: Axis.horizontal,
        expandActionsWhenTiny: false,
        removeBorderRadiusWhenTiny: false,
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 320,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(LucideIcons.church, '교회', churchName),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: matches.map((m) {
                      final deptName = m['departments']?['name'] ?? '부서 미정';
                      final groupName = m['group_name'] ?? '조 미정';
                      final role = m['role_in_group'] == 'leader' ? '조장' : '조원';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(LucideIcons.layers, size: 14, color: AppTheme.textSub),
                                const SizedBox(width: 8),
                                Text(deptName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(LucideIcons.users, size: 14, color: AppTheme.textSub),
                                const SizedBox(width: 8),
                                Text(groupName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentViolet,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(role, style: const TextStyle(fontSize: 11, color: AppTheme.primaryViolet, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '확인을 누르면 위 모든 소속이\n계정과 자동으로 연결됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.primaryViolet, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('정보가 틀려요', style: TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('네, 맞아요', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  void _showContactAdminDialog() {
    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('관리자 문의 필요', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        description: const Text('명부와 정보가 일치하지 않습니다.\n관리자에게 정보를 올바르게 수정을 요청해주세요.', style: TextStyle(height: 1.5, fontFamily: 'Pretendard')),
        actionsAxis: Axis.horizontal,
        expandActionsWhenTiny: false,
        removeBorderRadiusWhenTiny: false,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 320,
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentViolet,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppTheme.primaryViolet),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppTheme.textSub, fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'Pretendard')),
              Text(value, style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'Pretendard')),
            ],
          ),
        ],
      ),
    );
  }

  void _showAccountExistsDialog(AccountExistsException e) {
    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: AppTheme.primaryViolet),
            const SizedBox(width: 8),
            const Text('계정 안내', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ],
        ),
        description: const Text('이미 가입된 다른 계정이 있습니다.', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textMain, fontFamily: 'Pretendard')),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('가입된 성함: ${e.fullName}', style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
              Text('가입된 계정: ${e.maskedEmail ?? "비공개"}\n\n다른 방법(소셜 등)으로 이미 가입하셨을 수 있습니다.', style: const TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.5, fontFamily: 'Pretendard')),
            ],
          ),
        ),
        actions: [
          ShadButton.ghost(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppTheme.textSub, fontFamily: 'Pretendard')),
          ),
          ShadButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(repositoryProvider).cancelRegistration();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('로그인하러 가기', style: TextStyle(fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final repo = ref.read(repositoryProvider);
    await repo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('본인 확인', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        actions: [
          ShadButton.ghost(
            onPressed: _logout,
            child: const Text('로그아웃', style: TextStyle(color: AppTheme.textSub, fontSize: 13, fontFamily: 'Pretendard')),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              profile?.role == 'admin' 
                  ? '${profile?.fullName ?? '관리자'}님,\n본인 인증이 필요합니다'
                  : '휴대폰 번호로\n본인을 인증해주세요',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.8, fontFamily: 'Pretendard'),
            ),
            const SizedBox(height: 12),
            Text(
              profile?.role == 'admin'
                  ? '관리자 등록 시 입력하신 번호로\n인증을 진행해주세요.'
                  : '교회 성도 명부에 등록된\n성함과 휴대폰 번호를 입력해주세요.',
              style: const TextStyle(color: AppTheme.textSub, fontSize: 15, height: 1.5, fontFamily: 'Pretendard'),
            ),
            const SizedBox(height: 48),
            
            const Text('성함(실명)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
            const SizedBox(height: 10),
            ShadInput(
              controller: _nameController,
              readOnly: _isCodeSent,
              placeholder: Text('명부상의 실명 입력', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              constraints: const BoxConstraints(minHeight: 56),
              leading: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(LucideIcons.user, size: 20, color: AppTheme.textSub),
              ),
            ),
            const SizedBox(height: 24),

            const Text('휴대폰 번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
            const SizedBox(height: 10),
            ShadInput(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              readOnly: _isCodeSent,
              placeholder: Text('01012345678', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              constraints: const BoxConstraints(minHeight: 56),
              leading: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(LucideIcons.smartphone, size: 20, color: AppTheme.textSub),
              ),
              trailing: Container(
                padding: const EdgeInsets.only(right: 8),
                child: _isCodeSent
                  ? ShadButton.ghost(
                      onPressed: () {
                        setState(() {
                          _isCodeSent = false;
                          _timer?.cancel();
                        });
                      },
                      size: ShadButtonSize.sm,
                      child: const Text('재입력', style: TextStyle(fontSize: 12, color: AppTheme.primaryViolet, fontFamily: 'Pretendard')),
                    )
                  : ShadButton.ghost(
                      onPressed: _isLoading ? null : _sendCode,
                      size: ShadButtonSize.sm,
                      child: _isLoading 
                        ? SizedBox(width: 14, height: 14, child: ShadcnSpinner())
                        : const Text('인증요청', style: TextStyle(fontSize: 12, color: AppTheme.primaryViolet, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                    ),
              ),
            ),

            if (_isCodeSent) ...[
              const SizedBox(height: 24),
              const Text('인증번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
              const SizedBox(height: 10),
              ShadInput(
                controller: _codeController,
                keyboardType: TextInputType.number,
                placeholder: Text('6자리 번호 입력', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                constraints: const BoxConstraints(minHeight: 56),
                leading: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(LucideIcons.shieldCheck, size: 20, color: AppTheme.textSub),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(_timerString, style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                ),
              ),
              const SizedBox(height: 48),
              ShadButton(
                onPressed: _isLoading ? null : _verifyCode,
                size: ShadButtonSize.lg,
                child: _isLoading 
                  ? SizedBox(width: 20, height: 20, child: ShadcnSpinner(color: Colors.white))
                  : const Text('인증 및 다음 단계', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
              ),
              const SizedBox(height: 20),
              if (_phoneController.text == '01000000000')
                 const Text('테스트 모드: 인증번호 [123456]', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSub, fontSize: 12, fontFamily: 'Pretendard')),
            ],
          ],
        ),
      ),
    );
  }
}

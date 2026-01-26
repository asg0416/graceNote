import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:grace_note/core/error/exceptions.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/church_selection_screen.dart'; // Fallback
import 'package:grace_note/features/auth/presentation/screens/group_selection_screen.dart'; // Success Match
import 'package:grace_note/features/auth/presentation/screens/login_screen.dart';

class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends ConsumerState<PhoneVerificationScreen> {
  final _nameController = TextEditingController(); // [NEW] Real name for registry matching
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  
  bool _isCodeSent = false;
  bool _isLoading = false;
  Timer? _timer;
  int _remainingTime = 0; // seconds

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
      _remainingTime = 180; // 3 minutes
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
        // Strip out brackets and raw data if any remain
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
      final matchedMember = result['matched_member'];

      final profile = ref.read(userProfileProvider).value;
      final isAdmin = profile?.role == 'admin' || (profile?.adminStatus != null && profile!.adminStatus != 'none');

      // [SECURITY] If admin has a registered phone, it MUST match the verified phone
      if (isAdmin && profile?.phone != null && profile!.phone!.isNotEmpty) {
        // Normalize for comparison
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

      if (matchedMember == null) {
        if (isAdmin) {
          // Admin bypass: just link phone and complete onboarding
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

        // [BLOCK] No match in directory
        if (mounted) {
          SnackBarUtil.showSnackBar(
            context, 
            message: '성도 명부에 등록되지 않은 번호입니다.\n교회 담당자에게 문의해 주세요.', 
            isError: true,
          );
        }
        return;
      }

      // Match Found!
      final churchId = matchedMember['church_id'];
      
      // Fetch church name (Quick one-off query)
      final churchRes = await Supabase.instance.client
          .from('churches')
          .select('name')
          .eq('id', churchId)
          .single();
      
      final churchName = churchRes['name'];

      // [FIX] Use upsert instead of update to ensure profile exists
      // This is crucial because get_my_church_id() used in RLS relies on profiles.church_id
      if (user != null) {
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          'full_name': name,
          'email': user.email,
          'church_id': churchId,
          'phone': phone,
        });

        // Refresh userProfileProvider so the app state reflects the new church_id
        ref.invalidate(userProfileProvider);
        
        // Give a tiny bit of time for RLS/Provider to catch up
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (mounted) {
        if (isAdmin) {
          // Even if matched, if admin, just complete onboarding
          await repo.completeOnboarding(
            profileId: user!.id,
            fullName: profile!.fullName,
            churchId: churchId, // Use the matched churchId instead of profile.churchId (which might be null)
            phone: phone,
            matchedData: Map<String, dynamic>.from(matchedMember),
          );
          SnackBarUtil.showSnackBar(context, message: '관리자 인증이 완료되었습니다.');
          ref.invalidate(userProfileProvider);
          return;
        }

        // Refresh group provider for this church to bypass old RLS-cached empty results
        ref.invalidate(churchGroupsProvider(churchId));

        // Go to GroupSelectionScreen directly
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupSelectionScreen(
              churchId: churchId,
              churchName: churchName,
              prefilledName: matchedMember['full_name'],
              prefilledPhone: phone,
              matchedData: Map<String, dynamic>.from(matchedMember),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: e.toString().replaceFirst('Exception: ', ''), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAccountExistsDialog(AccountExistsException e) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryIndigo),
            SizedBox(width: 8),
            Text('계정 안내', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('등록된 휴대폰 번호로 가입된 다른 계정이 있습니다.', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('가입된 성함: ${e.fullName}', style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600)),
            Text('가입된 계정: ${e.maskedEmail ?? "비공개 계정"}', style: const TextStyle(color: AppTheme.textSub)),
            const SizedBox(height: 12),
            const Text('혹시 카카오나 구글 등 다른 방법으로 가입하셨나요?\n해당 계정으로 다시 로그인해 주세요.', style: TextStyle(fontSize: 13, color: AppTheme.textSub, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryIndigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('로그인하러 가기'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final repo = ref.read(repositoryProvider);
    await repo.signOut();
    // AuthGate will handle the redirect to Login
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('본인 확인'),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text('로그아웃', style: TextStyle(color: AppTheme.textSub)),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              profile?.role == 'admin' 
                  ? '${profile?.fullName ?? '관리자'}님 환영합니다!\n휴대폰 번호를 인증해주세요'
                  : '휴대폰 번호로\n본인을 인증해주세요',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text(
              profile?.role == 'admin'
                  ? '웹에서 등록하신 정보와 일치하는\n휴대폰 번호로 인증해주세요.'
                  : '교회 성도 명부에 등록된\n성함과 휴대폰 번호로 인증해주세요.',
              style: const TextStyle(color: AppTheme.textSub),
            ),
            // Name Input (Real name)
            TextField(
              controller: _nameController,
              readOnly: _isCodeSent,
              decoration: InputDecoration(
                labelText: '성함(실명)',
                hintText: '성도 명부에 등록된 성함을 적어주세요',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),

            // Phone Input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              // [FIX] Don't disable the whole TextField if we need interactiviy in suffixIcon.
              // Instead, we can make it readOnly if needed, but for now let's just use it.
              readOnly: _isCodeSent, 
              decoration: InputDecoration(
                labelText: '휴대폰 번호',
                hintText: '01012345678',
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                // suffixIcon is usually part of the tap target only if TextField is enabled.
                // However, TextButton inside suffixIcon should work if we handle it carefully.
                suffixIcon: !_isCodeSent
                    ? _isLoading 
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) 
                        : TextButton(
                            onPressed: _sendCode,
                            child: const Text('인증요청'),
                          )
                    : TextButton(
                        onPressed: () {
                          setState(() {
                            _isCodeSent = false;
                            _remainingTime = 0;
                            _timer?.cancel();
                          });
                        },
                        child: const Text('재입력'),
                      ),
              ),
            ),

            if (_isCodeSent) ...[
              const SizedBox(height: 16),
              // Code Input
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '인증번호 6자리',
                  hintText: '123456',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  helperText: '남은 시간: $_timerString',
                  helperStyle: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('인증 및 다음단계'),
              ),
              const SizedBox(height: 16),
              if (_phoneController.text == '01000000000')
                 const Text('테스트 모드: 인증번호 [123456]', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}

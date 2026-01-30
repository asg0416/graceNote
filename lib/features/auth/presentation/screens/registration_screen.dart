import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/utils/auth_error_helper.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class RegistrationScreen extends StatefulWidget {
  final String? initialEmail;
  final bool showOtpFirst;

  const RegistrationScreen({
    super.key,
    this.initialEmail,
    this.showOtpFirst = false,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isOtpSent = false;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  // Password validation states
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
    if (widget.showOtpFirst) {
      _isOtpSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocusNode.requestFocus();
      });
    }
    _passwordController.addListener(_validatePassword);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_validatePassword);
    _passwordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _validatePassword() {
    final password = _passwordController.text;
    setState(() {
      _hasMinLength = password.length >= 6;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool get _isPasswordValid => 
      _hasMinLength && _hasUppercase && _hasLowercase && _hasDigit && _hasSpecialChar;

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '모든 필드를 입력해주세요.', isError: true);
      return;
    }

    if (!_isPasswordValid) {
      SnackBarUtil.showSnackBar(context, message: '비밀번호 보안 규칙을 모두 충족해야 합니다.', isError: true);
      return;
    }

    if (password != confirmPassword) {
      SnackBarUtil.showSnackBar(context, message: '비밀번호가 일치하지 않습니다.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
        emailRedirectTo: kIsWeb ? null : 'io.supabase.flutter://registration-callback',
      );
      
      if (mounted) {
        if (response.session != null) {
          Navigator.of(context).pop();
        } else {
          setState(() => _isOtpSent = true);
          _startResendTimer();
          SnackBarUtil.showSnackBar(context, message: '인증 번호가 이메일로 발송되었습니다.');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _otpFocusNode.requestFocus();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: AuthErrorHelper.getFriendlyMessage(e),
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _handleResendOtp() async {
    if (_resendSeconds > 0) return;
    
    final email = _emailController.text.trim();
    _callOtpResend(email);
  }
  
  Future<void> _callOtpResend(String email) async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kIsWeb ? null : 'io.supabase.flutter://registration-callback',
      );
      
      _startResendTimer();
      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: '인증 번호가 다시 발송되었습니다.');
        _otpFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '인증 번호 재발송에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _handleVerifyOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (email.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '이메일 정보가 없습니다. 다시 시도해주세요.', isError: true);
      setState(() => _isOtpSent = false);
      return;
    }

    if (otp.length < 6) {
      SnackBarUtil.showSnackBar(context, message: '인증 번호 6자리를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('Verifying OTP for $email: $otp');
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );

      if (mounted) {
        if (response.session != null) {
          SnackBarUtil.showSnackBar(context, message: '인증이 완료되었습니다!');
          // 약간의 지연 후 뒤로 가기 (성공 피드백 인지 시간 부여)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else {
          // 세션은 없지만 성공했을 수 있음 (이미 인증됨 등)
          debugPrint('VerifyOTP Success but Session is NULL');
          SnackBarUtil.showSnackBar(context, message: '인증이 확인되었습니다. 로그인해 주세요.');
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('VerifyOTP Error: $e');
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '인증 번호가 올바르지 않거나 만료되었습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
        _otpController.clear();
        _otpFocusNode.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_isOtpSent ? '인증 번호 확인' : '회원가입', 
            style: const TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: ShadButton.ghost(
          onPressed: () {
            if (_isOtpSent) {
              setState(() => _isOtpSent = false);
            } else {
              Navigator.pop(context);
            }
          },
          child: Icon(LucideIcons.chevronLeft, size: 24, color: AppTheme.textMain),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isOtpSent) ...[
                const SizedBox(height: 12),
                const Text(
                  '인증 번호를 입력해 주세요',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.5,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_emailController.text} 이메일로 발송된\n6자리 번호를 입력해 주세요.',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textSub,
                    height: 1.5,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(height: 48),
                // Modern Pin Code Input Layout
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Hidden field to capture input
                    Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (val) {
                          setState(() {});
                          if (val.length == 6) {
                            _handleVerifyOtp();
                          }
                        },
                      ),
                    ),
                    // Visual Boxes
                    GestureDetector(
                      onTap: () => _otpFocusNode.requestFocus(), // Trigger hidden field focus
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          final char = _otpController.text.length > index 
                              ? _otpController.text[index] 
                              : '';
                          final isFocused = _otpController.text.length == index;
                          
                          return Container(
                            width: 1400 / 33, // Approximately 42-45
                            constraints: const BoxConstraints(maxWidth: 50, minWidth: 44),
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isFocused ? AppTheme.primaryViolet : AppTheme.border.withOpacity(0.5),
                                width: isFocused ? 2 : 1,
                              ),
                              boxShadow: isFocused ? [
                                BoxShadow(
                                  color: AppTheme.primaryViolet.withOpacity(0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ] : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              char,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryViolet,
                                fontFamily: 'Pretendard',
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                ShadButton(
                  onPressed: _isLoading || _otpController.text.length < 6 ? null : _handleVerifyOtp,
                  size: ShadButtonSize.lg,
                  child: _isLoading 
                      ? ShadcnSpinner(color: Colors.white, size: 20)
                      : const Text('인증 및 가입 완료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      ShadButton.ghost(
                        onPressed: _isLoading || _resendSeconds > 0 ? null : _handleResendOtp,
                        child: Text(
                          _resendSeconds > 0 ? '인증 번호 재전송 ($_resendSeconds초)' : '인증 번호를 받지 못하셨나요? 재전송하기',
                          style: TextStyle(
                            color: _resendSeconds > 0 ? AppTheme.textSub.withOpacity(0.5) : AppTheme.primaryViolet,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ),
                      ShadButton.link(
                        onPressed: () => setState(() {
                          _isOtpSent = false;
                          _resendTimer?.cancel();
                          _resendSeconds = 0;
                        }),
                        child: const Text('이메일 주소 수정하기', style: TextStyle(color: AppTheme.textSub, fontSize: 13, fontFamily: 'Pretendard')),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  '새로운 시작을 환영합니다',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMain,
                    letterSpacing: -0.5,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(height: 24),
                const ShadAlert(
                  icon: Icon(LucideIcons.info, size: 18),
                  title: Text('등록 안내', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                  description: Text('성도 등록이 완료된 분만 가입이 가능하며,\n미등록 시 관리자에게 문의바랍니다.', style: TextStyle(fontFamily: 'Pretendard')),
                ),
                const SizedBox(height: 36),
                
                const Text('이름', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
                const SizedBox(height: 10),
                ShadInput(
                  controller: _nameController,
                  placeholder: Text('실명을 입력해주세요', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  constraints: const BoxConstraints(minHeight: 56),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(LucideIcons.user, size: 20, color: AppTheme.textSub),
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text('이메일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
                const SizedBox(height: 10),
                ShadInput(
                  controller: _emailController,
                  placeholder: Text('example@email.com', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                  keyboardType: TextInputType.emailAddress,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  constraints: const BoxConstraints(minHeight: 56),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(LucideIcons.mail, size: 20, color: AppTheme.textSub),
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text('비밀번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
                const SizedBox(height: 10),
                ShadInput(
                  controller: _passwordController,
                  placeholder: Text('••••••••', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                  obscureText: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(LucideIcons.lock, size: 20, color: AppTheme.textSub),
                  ),
                ),
                const SizedBox(height: 12),
                
                _buildPasswordRequirements(),
                const SizedBox(height: 24),
                
                const Text('비밀번호 확인', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
                const SizedBox(height: 10),
                ShadInput(
                  controller: _confirmPasswordController,
                  placeholder: Text('••••••••', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                  obscureText: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 8),
                    child: Icon(Icons.check_circle_outline, size: 20, color: AppTheme.textSub),
                  ),
                ),
                const SizedBox(height: 48),
                
                ShadButton(
                  onPressed: _isLoading || !_isPasswordValid ? null : _handleSignUp,
                  size: ShadButtonSize.lg,
                  child: _isLoading 
                      ? ShadcnSpinner(color: Colors.white, size: 20)
                      : const Text('가입하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '보안 규칙을 충족해야 합니다',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSub.withOpacity(0.8), fontFamily: 'Pretendard'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildValidationItem('6자 이상', _hasMinLength),
              _buildValidationItem('대문자', _hasUppercase),
              _buildValidationItem('소문자', _hasLowercase),
              _buildValidationItem('숫자', _hasDigit),
              _buildValidationItem('특수문자', _hasSpecialChar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildValidationItem(String text, bool isValid) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isValid ? LucideIcons.check : LucideIcons.circle,
          size: 14,
          color: isValid ? AppTheme.success : AppTheme.textSub.withOpacity(0.4),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isValid ? AppTheme.success : AppTheme.textSub.withOpacity(0.6),
            fontWeight: isValid ? FontWeight.w700 : FontWeight.w500,
            fontFamily: 'Pretendard',
          ),
        ),
      ],
    );
  }
}

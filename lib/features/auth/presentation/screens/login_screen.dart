import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../core/utils/snack_bar_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/features/auth/presentation/screens/registration_screen.dart';
import 'package:grace_note/core/utils/auth_error_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_note/core/widgets/shadcn_spinner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _handleEmailLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '이메일과 비밀번호를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      if (mounted) {
        final isNotConfirmed = e is AuthException && 
            (e.code == 'email_not_confirmed' || e.message.contains('Email not confirmed'));
        
        SnackBarUtil.showSnackBar(
          context,
          message: AuthErrorHelper.getFriendlyMessage(e),
          isError: true,
          technicalDetails: e.toString(),
          duration: isNotConfirmed ? const Duration(seconds: 10) : null,
          action: isNotConfirmed ? SnackBarAction(
            label: '인증번호 입력',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RegistrationScreen(
                    initialEmail: email,
                    showOtpFirst: true,
                  ),
                ),
              );
            },
          ) : null,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithSocial(OAuthProvider provider) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(repositoryProvider).signInWithOAuth(provider);
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

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('비밀번호 찾기', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        description: const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 20),
          child: Text(
            '가입하신 이메일 주소를 입력해 주세요.\n비밀번호 재설정 링크를 보내드립니다.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.5, fontFamily: 'Pretendard'),
          ),
        ),
        actionsAxis: Axis.horizontal, // 모바일에서도 가로 배치 유지
        expandActionsWhenTiny: false, // 버튼이 화면 끝까지 늘어나는 것 방지
        removeBorderRadiusWhenTiny: false, // 둥근 모서리 유지
        titleTextAlign: TextAlign.start,
        descriptionTextAlign: TextAlign.start,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          minWidth: 320,
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이메일 주소', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
              const SizedBox(height: 10),
              ShadInput(
                controller: emailController,
                placeholder: Text('example@email.com', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                keyboardType: TextInputType.emailAddress,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                leading: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: Icon(LucideIcons.mail, size: 20, color: AppTheme.textSub),
                ),
              ),
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
              final email = emailController.text.trim();
              if (email.isEmpty) return;

              Navigator.pop(context);

              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(
                  email,
                  redirectTo: kIsWeb ? null : 'io.supabase.flutter://reset-callback',
                );
                
                if (mounted) {
                  SnackBarUtil.showSnackBar(
                    context, 
                    message: '비밀번호 재설정 링크가 이메일로 발송되었습니다.',
                  );
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
              }
            },
            child: const Text('이메일 발송', style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Subtle radial gradient background
          Positioned(
            top: -150,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primaryViolet.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    // Logo & App Name
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.accentViolet,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              height: 60,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            AppConstants.appName,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textMain,
                              letterSpacing: -1.0,
                              fontFamily: 'Pretendard',
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '기록은 가볍게, 기도는 깊게',
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSub,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Pretendard',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 52),
                    
                    // Email Input
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
                    
                    // Password Input
                    const Text('비밀번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSub, fontFamily: 'Pretendard', letterSpacing: -0.2)),
                    const SizedBox(height: 10),
                    ShadInput(
                      controller: _passwordController,
                      placeholder: Text('••••••••', style: TextStyle(color: AppTheme.textSub.withOpacity(0.4), fontSize: 15)),
                      obscureText: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      constraints: const BoxConstraints(minHeight: 56),
                      leading: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 8),
                        child: Icon(LucideIcons.lock, size: 20, color: AppTheme.textSub),
                      ),
                    ),
                    
                    Align(
                      alignment: Alignment.centerRight,
                      child: ShadButton.ghost(
                        onPressed: () => _showForgotPasswordDialog(context),
                        padding: EdgeInsets.zero,
                        child: const Text(
                          '비밀번호 찾기',
                          style: TextStyle(
                            color: AppTheme.textSub,
                            fontSize: 13,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Login Button
                    ShadButton(
                      onPressed: _isLoading ? null : _handleEmailLogin,
                      size: ShadButtonSize.lg,
                      child: _isLoading 
                          ? ShadcnSpinner(color: Colors.white, size: 20) 
                          : const Text('로그인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Pretendard')),
                    ),
                    
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('계정이 없으신가요?', style: TextStyle(color: AppTheme.textSub, fontSize: 14, fontFamily: 'Pretendard')),
                        ShadButton.link(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: const Text('회원가입', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryViolet, fontFamily: 'Pretendard')),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppTheme.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('소셜 로그인', style: TextStyle(color: AppTheme.textSub.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Pretendard')),
                        ),
                        const Expanded(child: Divider(color: AppTheme.border)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Social Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton.outline(
                            onPressed: () => _signInWithSocial(OAuthProvider.kakao),
                            backgroundColor: const Color(0xFFFEE500),
                            hoverBackgroundColor: const Color(0xFFFDE100),
                            // 보더 제거를 위해 최신 API에 맞는 속성 사용 또는 명시적 투명 설정
                            pressedBackgroundColor: const Color(0xFFFEE500),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.messageCircle, size: 20, color: Color(0xFF191919)),
                                SizedBox(width: 10),
                                Text('카카오', style: TextStyle(color: Color(0xFF191919), fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ShadButton.outline(
                            onPressed: () => _signInWithSocial(OAuthProvider.google),
                            backgroundColor: Colors.white,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.g_mobiledata, size: 28, color: AppTheme.textMain),
                                SizedBox(width: 4),
                                Text('Google', style: TextStyle(color: AppTheme.textMain, fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                    Center(
                      child: Text(
                        'Version ${AppConstants.appVersion}',
                        style: TextStyle(color: AppTheme.textSub.withOpacity(0.5), fontSize: 12, fontFamily: 'Pretendard'),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.1),
              child: Center(child: ShadcnSpinner(size: 40)),
            ),
        ],
      ),
    );
  }
}

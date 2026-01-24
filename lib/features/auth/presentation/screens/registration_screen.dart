import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:grace_note/core/constants/app_constants.dart';
import 'package:grace_note/core/utils/auth_error_helper.dart';
import 'package:grace_note/core/utils/snack_bar_util.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '모든 필드를 입력해주세요.', isError: true);
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
      );
      
      if (mounted) {
        if (response.session != null) {
          // [PATCH] Explicitly pop and let AuthGate handle the navigation.
          // On Web, sometimes popping slowly helps the state listener catch up.
          Navigator.of(context).pop();
        } else {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('회원가입 완료'),
              content: const Text('인증 메일이 발송되었습니다. 메일의 링크를 클릭하여 가입을 완료해 주세요.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); 
                    Navigator.pop(context); 
                  },
                  child: const Text('확인'),
                ),
              ],
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('회원가입', style: TextStyle(color: AppTheme.textMain)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                '새로운 시작을 환영합니다',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryIndigo.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppTheme.primaryIndigo, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '성도 등록이 이미 완료된 분만 가입이 가능합니다. 등록되지 않은 경우 관리자에게 문의해 주세요.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryIndigo.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '이름',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '이메일 주소',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: '비밀번호 확인',
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 32),
              
              ElevatedButton(
                onPressed: _isLoading ? null : _handleSignUp,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: _isLoading 
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('가입하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

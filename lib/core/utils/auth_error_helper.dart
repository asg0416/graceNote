import 'package:supabase_flutter/supabase_flutter.dart';

class AuthErrorHelper {
  static String getFriendlyMessage(Object error) {
    if (error is AuthException) {
      switch (error.code) {
        case 'invalid_credentials':
          return '이메일 또는 비밀번호가 잘못되었습니다.';
        case 'user_already_exists':
          return '이미 가입된 이메일 주소입니다.';
        case 'weak_password':
          return '비밀번호가 너무 취약합니다. (최소 6자 이상)';
        case 'email_not_confirmed':
          return '이메일 인증이 완료되지 않았습니다. 메일함의 인증번호 6자리를 입력해 주세요.';
        case 'over_email_send_rate_limit':
          return '짧은 시간에 너무 많은 요청을 보냈습니다. 잠시 후 다시 시도해주세요.';
        case 'network_error':
          return '네트워크 연결이 원활하지 않습니다.';
        default:
          if (error.message.contains('Email not confirmed')) {
            return '이메일 인증이 완료되지 않았습니다.';
          }
          return '인증 오류: ${error.message}';
      }
    }
    
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('network') || errorStr.contains('socket')) {
      return '서버와 연결할 수 없습니다. 인터넷 상태를 확인해 주세요.';
    }
    
    return '알 수 없는 오류가 발생했습니다. 다시 시도해 주세요.';
  }
}

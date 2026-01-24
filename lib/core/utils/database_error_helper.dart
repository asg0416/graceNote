import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseErrorHelper {
  static String getFriendlyMessage(Object error) {
    if (error is PostgrestException) {
      // https://www.postgresql.org/docs/current/errcodes-appendix.html
      switch (error.code) {
        case '23505': // unique_violation
          if (error.message.contains('member_directory_unique_assignment')) {
            return '이미 같은 조에 동일한 이름의 조원이 존재합니다.';
          }
          if (error.message.contains('member_directory_phone_key') || 
              error.message.contains('profiles_phone_key')) {
            return '이미 등록된 연락처입니다.';
          }
          if (error.message.contains('phone_cross_uniqueness')) {
            return '이미 시스템에 등록된 연락처입니다. (계정 또는 다른 조원)';
          }
          return '이미 존재하는 정보입니다. (중복 오류)';
        
        case '42501': // insufficient_privilege (RLS)
          return '저장 권한이 없습니다. 관리자에게 문의하세요.';
          
        case '23503': // foreign_key_violation
          return '관련된 정보가 존재하지 않아 저장할 수 없습니다.';
          
        default:
          return '데이터베이스 처리 중 오류가 발생했습니다: ${error.message}';
      }
    }
    
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('network') || errorStr.contains('socket')) {
      return '서버와 연결할 수 없습니다. 인터넷 상태를 확인해 주세요.';
    }
    
    return '알 수 없는 오류가 발생했습니다: $error';
  }
}

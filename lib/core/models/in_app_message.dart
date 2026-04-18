// lib/core/models/in_app_message.dart

class InAppMessage {
  final String id;
  final String? churchId;
  final String? departmentId;
  final String title;
  final String body;           // HTML (DOMPurify 살균 후 저장된 값)
  final String? ctaLabel;
  final String? ctaUrl;        // https:// 만 허용 (DB CHECK constraint)
  final IamType type;
  final IamDisplayType displayType;
  final IamTargetRole targetRole;
  final DateTime startsAt;
  final DateTime? expiresAt;
  final bool isActive;
  final bool isDeleted;
  final int priority;
  final DateTime createdAt;

  const InAppMessage({
    required this.id,
    this.churchId,
    this.departmentId,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.ctaUrl,
    required this.type,
    required this.displayType,
    required this.targetRole,
    required this.startsAt,
    this.expiresAt,
    required this.isActive,
    required this.isDeleted,
    required this.priority,
    required this.createdAt,
  });

  factory InAppMessage.fromJson(Map<String, dynamic> json) {
    return InAppMessage(
      id:            json['id'] as String,
      churchId:      json['church_id'] as String?,
      departmentId:  json['department_id'] as String?,
      title:         json['title'] as String,
      body:          json['body'] as String,
      ctaLabel:      json['cta_label'] as String?,
      ctaUrl:        json['cta_url'] as String?,
      type:          IamType.fromString(json['type'] as String? ?? 'announcement'),
      displayType:   IamDisplayType.fromString(json['display_type'] as String? ?? 'slide_up'),
      targetRole:    IamTargetRole.fromString(json['target_role'] as String? ?? 'all'),
      startsAt:      DateTime.parse(json['starts_at'] as String),
      expiresAt:     json['expires_at'] != null
                       ? DateTime.parse(json['expires_at'] as String)
                       : null,
      isActive:      json['is_active'] as bool? ?? true,
      isDeleted:     json['is_deleted'] as bool? ?? false,
      priority:      json['priority'] as int? ?? 0,
      createdAt:     DateTime.parse(json['created_at'] as String),
    );
  }

  /// RLS가 만료 메시지를 필터하지만, 앱 실행 중 만료된 경우
  /// 클라이언트에서도 이중 체크
  bool get isCurrentlyActive {
    final now = DateTime.now();
    if (!isActive || isDeleted) return false;
    if (now.isBefore(startsAt)) return false;
    if (expiresAt != null && now.isAfter(expiresAt!)) return false;
    return true;
  }
}

enum IamType {
  announcement,
  update,
  survey;

  static IamType fromString(String s) => switch (s) {
    'update'  => IamType.update,
    'survey'  => IamType.survey,
    _         => IamType.announcement,
  };
}

enum IamDisplayType {
  slideUp,
  modal;

  static IamDisplayType fromString(String s) =>
    s == 'modal' ? IamDisplayType.modal : IamDisplayType.slideUp;
}

enum IamTargetRole {
  all,
  leader,
  member;

  static IamTargetRole fromString(String s) => switch (s) {
    'leader' => IamTargetRole.leader,
    'member' => IamTargetRole.member,
    _        => IamTargetRole.all,
  };
}

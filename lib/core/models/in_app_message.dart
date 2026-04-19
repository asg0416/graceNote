// lib/core/models/in_app_message.dart

/// 슬라이드 모드에서 각 페이지 콘텐츠
class IamSlide {
  final String title;      // 슬라이드별 제목
  final String body;       // HTML
  final String? imageUrl;

  const IamSlide({required this.title, required this.body, this.imageUrl});

  factory IamSlide.fromJson(Map<String, dynamic> json) => IamSlide(
    title:    json['title']     as String? ?? '',
    body:     json['body']      as String? ?? '',
    imageUrl: json['image_url'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'title':    title,
    'body':     body,
    if (imageUrl != null) 'image_url': imageUrl,
  };
}

class InAppMessage {
  final String id;
  final String? churchId;
  final String? departmentId;
  final String title;
  final String body;           // HTML (단일 본문 모드)
  final String? imageUrl;      // 단일 이미지 (슬라이드 미사용 시)
  final List<IamSlide> slides; // 슬라이드 모드 (비어있으면 단일 모드)
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
    this.imageUrl,
    this.slides = const [],
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
    final rawSlides = json['slides'];
    final slides = (rawSlides is List)
        ? rawSlides
            .whereType<Map<String, dynamic>>()
            .map(IamSlide.fromJson)
            .toList()
        : <IamSlide>[];

    return InAppMessage(
      id:            json['id'] as String,
      churchId:      json['church_id'] as String?,
      departmentId:  json['department_id'] as String?,
      title:         json['title'] as String,
      body:          json['body'] as String,
      imageUrl:      json['image_url'] as String?,
      slides:        slides,
      ctaLabel:      json['cta_label'] as String?,
      ctaUrl:        json['cta_url'] as String?,
      type:          IamType.fromString(json['type'] as String? ?? 'announcement'),
      displayType:   IamDisplayType.fromString(json['display_type'] as String? ?? 'slide_up'),
      targetRole:    IamTargetRole.fromString(json['target_role'] as String? ?? 'all'),
      startsAt:      DateTime.tryParse(json['starts_at'] as String? ?? '') ?? DateTime.now().toUtc(),
      expiresAt:     json['expires_at'] != null
                       ? DateTime.tryParse(json['expires_at'] as String)
                       : null,
      isActive:      json['is_active'] as bool? ?? true,
      isDeleted:     json['is_deleted'] as bool? ?? false,
      priority:      json['priority'] as int? ?? 0,
      createdAt:     DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now().toUtc(),
    );
  }

  bool get isSlideMode => slides.isNotEmpty;

  /// RLS가 만료 메시지를 필터하지만, 앱 실행 중 만료된 경우
  /// 클라이언트에서도 이중 체크
  bool get isCurrentlyActive {
    final now = DateTime.now().toUtc();
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

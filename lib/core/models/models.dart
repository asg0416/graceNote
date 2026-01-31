// lib/core/models/models.dart

class AttendanceModel {
  final String? id;
  final String weekId;
  final String? groupId;
  final String? groupMemberId;
  final String directoryMemberId;
  final String status; // 'present', 'absent', 'late', 'excused'
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? memberInfo; // Optional join data

  AttendanceModel({
    this.id,
    required this.weekId,
    this.groupId,
    this.groupMemberId,
    required this.directoryMemberId,
    this.status = 'absent',
    this.createdAt,
    this.updatedAt,
    this.memberInfo,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    return AttendanceModel(
      id: json['id'],
      weekId: json['week_id'],
      groupId: json['group_id'],
      groupMemberId: json['group_member_id'],
      directoryMemberId: json['directory_member_id'] ?? '',
      status: json['status'] ?? 'absent',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      memberInfo: json['member_directory'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'week_id': weekId,
      if (groupId != null) 'group_id': groupId,
      if (groupMemberId != null) 'group_member_id': groupMemberId,
      'directory_member_id': directoryMemberId,
      'status': status,
    };
  }
}

class PrayerEntryModel {
  final String? id;
  final String weekId;
  final String groupId;
  final String? authorId;
  final String? memberId; // Legacy/App User Profile ID
  final String directoryMemberId; // New primary source
  final String? content;
  final String? aiRefinedContent;
  final String status; // 'draft', 'published'
  final bool isRefining;
  final DateTime? updatedAt;

  PrayerEntryModel({
    this.id,
    required this.weekId,
    required this.groupId,
    this.authorId,
    this.memberId,
    required this.directoryMemberId,
    this.content,
    this.aiRefinedContent,
    this.status = 'draft',
    this.isRefining = false,
    this.updatedAt,
  });

  factory PrayerEntryModel.fromJson(Map<String, dynamic> json) {
    return PrayerEntryModel(
      id: json['id'],
      weekId: json['week_id'],
      groupId: json['group_id'],
      authorId: json['author_id'],
      memberId: json['member_id'],
      directoryMemberId: json['directory_member_id'] ?? '',
      content: json['content'],
      aiRefinedContent: json['ai_refined_content'],
      status: json['status'] ?? 'draft',
      isRefining: json['is_refining'] ?? false,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'week_id': weekId,
      'group_id': groupId,
      'author_id': authorId,
      if (memberId != null) 'member_id': memberId,
      'directory_member_id': directoryMemberId,
      'content': content,
      'ai_refined_content': aiRefinedContent,
      'status': status,
      'is_refining': isRefining,
    };
  }
}

class ProfileModel {
  final String id;
  final String? churchId;
  final String? departmentId;
  final String? familyId;
  final String? spouseId;
  final String fullName;
  final String role;
  final String adminStatus; // 'none', 'pending', 'approved', 'rejected'
  final bool isMaster;
  final String? phone;
  final String? weddingAnniversary; // YYYY-MM-DD
  final String? birthDate; // YYYY-MM-DD
  final String? childrenInfo;
  final bool isOnboardingComplete;
  final String? avatarUrl;
  final DateTime? lastNoticeCheckedAt;
  final DateTime? createdAt;

  ProfileModel({
    required this.id,
    this.churchId,
    this.departmentId,
    this.familyId,
    this.spouseId,
    required this.fullName,
    this.role = 'user',
    this.adminStatus = 'none',
    this.isMaster = false,
    this.phone,
    this.weddingAnniversary,
    this.birthDate,
    this.childrenInfo,
    this.isOnboardingComplete = false,
    this.avatarUrl,
    this.lastNoticeCheckedAt,
    this.createdAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      churchId: json['church_id'],
      departmentId: json['department_id'],
      familyId: json['family_id'],
      spouseId: json['spouse_id'],
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? 'user',
      adminStatus: json['admin_status'] ?? 'none',
      isMaster: json['is_master'] ?? false,
      phone: json['phone'],
      weddingAnniversary: json['wedding_anniversary'],
      birthDate: json['birth_date'],
      childrenInfo: json['children_info'],
      isOnboardingComplete: json['is_onboarding_complete'] ?? false,
      avatarUrl: json['avatar_url'],
      lastNoticeCheckedAt: json['last_notice_checked_at'] != null ? DateTime.parse(json['last_notice_checked_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'church_id': churchId,
      'department_id': departmentId,
      'family_id': familyId,
      'spouse_id': spouseId,
      'full_name': fullName,
      'role': role,
      'admin_status': adminStatus,
      'is_master': isMaster,
      'phone': phone,
      'wedding_anniversary': weddingAnniversary,
      'birth_date': birthDate,
      'children_info': childrenInfo,
      'is_onboarding_complete': isOnboardingComplete,
      'avatar_url': avatarUrl,
      'last_notice_checked_at': lastNoticeCheckedAt?.toIso8601String(),
    };
  }
}

class DepartmentModel {
  final String id;
  final String churchId;
  final String name;
  final String profileMode;
  final bool allowLateEntry;

  DepartmentModel({
    required this.id,
    required this.churchId,
    required this.name,
    this.profileMode = 'individual',
    this.allowLateEntry = true,
  });

  factory DepartmentModel.fromJson(Map<String, dynamic> json) {
    return DepartmentModel(
      id: json['id'],
      churchId: json['church_id'],
      name: json['name'],
      profileMode: json['profile_mode'] ?? 'individual',
      allowLateEntry: json['allow_late_entry'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'church_id': churchId,
      'name': name,
      'profile_mode': profileMode,
      'allow_late_entry': allowLateEntry,
    };
  }
}

class FamilyModel {
  final String id;
  final String churchId;
  final String? departmentId;
  final String? name;

  FamilyModel({
    required this.id,
    required this.churchId,
    this.departmentId,
    this.name,
  });

  factory FamilyModel.fromJson(Map<String, dynamic> json) {
    return FamilyModel(
      id: json['id'],
      churchId: json['church_id'],
      departmentId: json['department_id'],
      name: json['name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'church_id': churchId,
      'department_id': departmentId,
      'name': name,
    };
  }
}

class UserMembership {
  final String groupId;
  final String groupName;
  final String roleInGroup; // 'leader', 'member', 'admin'
  final String? departmentName;
  final String? churchId;

  UserMembership({
    required this.groupId,
    required this.groupName,
    required this.roleInGroup,
    this.departmentName,
    this.churchId,
  });

  factory UserMembership.fromMap(Map<String, dynamic> map) {
    return UserMembership(
      groupId: map['group_id'] ?? '',
      groupName: map['group_name'] ?? '',
      roleInGroup: map['role_in_group'] ?? 'member',
      departmentName: map['department_name'],
      churchId: map['church_id'],
    );
  }

  String get roleLabel {
    switch (roleInGroup) {
      case 'admin':
        return '관리자';
      case 'leader':
        return '조장';
      default:
        return '조원';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserMembership &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          roleInGroup == other.roleInGroup;

  @override
  int get hashCode => groupId.hashCode ^ roleInGroup.hashCode;
}

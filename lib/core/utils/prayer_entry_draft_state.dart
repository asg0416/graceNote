const String prayerDraftContentKey = 'draft_content';
const String prayerDraftUpdatedAtKey = 'draft_updated_at';

enum PrayerRecordBadgeStatus { empty, draft, published }

String resolveEditablePrayerContent(Map<String, dynamic> prayer) {
  final status = prayer['status']?.toString();
  final draftContent = prayer[prayerDraftContentKey]?.toString();
  if (status == 'published' &&
      draftContent != null &&
      draftContent.trim().isNotEmpty) {
    return draftContent;
  }
  return prayer['content']?.toString() ?? '';
}

bool hasPendingPrayerDraft(Map<String, dynamic> prayer) {
  final draftContent = prayer[prayerDraftContentKey]?.toString();
  return draftContent != null && draftContent.trim().isNotEmpty;
}

String resolveLocalPrayerStatusAfterSave({
  required String requestedStatus,
  required String currentStatus,
}) {
  if (requestedStatus == 'draft' && currentStatus == 'published') {
    return 'published';
  }
  return requestedStatus;
}

bool shouldWriteDraftBesidePublished({
  required String requestedStatus,
  required String? existingStatus,
}) {
  return requestedStatus == 'draft' && existingStatus == 'published';
}

PrayerRecordBadgeStatus resolvePrayerRecordBadgeStatus(
  Iterable<Map<String, dynamic>> members, {
  bool isAutoSaving = false,
  bool isDirty = false,
}) {
  if (members.isEmpty) return PrayerRecordBadgeStatus.empty;

  final hasDraftState = members.any((member) {
    return member['prayerStatus'] == 'draft' ||
        member['hasPendingPrayerDraft'] == true;
  });
  if (hasDraftState || isAutoSaving || isDirty) {
    return PrayerRecordBadgeStatus.draft;
  }

  final hasPublished =
      members.any((member) => member['prayerStatus'] == 'published');
  if (hasPublished) return PrayerRecordBadgeStatus.published;

  return PrayerRecordBadgeStatus.empty;
}

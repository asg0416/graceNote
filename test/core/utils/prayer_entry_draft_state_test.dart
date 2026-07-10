import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/utils/prayer_entry_draft_state.dart';

void main() {
  test('draft autosave after publish keeps the local prayer status published',
      () {
    expect(
      resolveLocalPrayerStatusAfterSave(
        requestedStatus: 'draft',
        currentStatus: 'published',
      ),
      'published',
    );
  });

  test('ordinary draft autosave stays draft before the first publish', () {
    expect(
      resolveLocalPrayerStatusAfterSave(
        requestedStatus: 'draft',
        currentStatus: 'initial',
      ),
      'draft',
    );
  });

  test('record editor uses pending draft content over published content', () {
    expect(
      resolveEditablePrayerContent({
        'status': 'published',
        'content': '이미 등록된 기도제목',
        'draft_content': '수정 중인 기도제목',
      }),
      '수정 중인 기도제목',
    );
  });

  test('published prayer without pending draft uses published content', () {
    expect(
      resolveEditablePrayerContent({
        'status': 'published',
        'content': '이미 등록된 기도제목',
        'draft_content': '',
      }),
      '이미 등록된 기도제목',
    );
  });

  test('published prayer should receive autosaved draft beside published row',
      () {
    expect(
      shouldWriteDraftBesidePublished(
        requestedStatus: 'draft',
        existingStatus: 'published',
      ),
      isTrue,
    );
  });

  test('record badge prefers draft when published prayer has pending draft',
      () {
    expect(
      resolvePrayerRecordBadgeStatus([
        {
          'prayerStatus': 'published',
          'hasPendingPrayerDraft': true,
        },
      ]),
      PrayerRecordBadgeStatus.draft,
    );
  });

  test('record badge is published only when there is no pending draft', () {
    expect(
      resolvePrayerRecordBadgeStatus([
        {
          'prayerStatus': 'published',
          'hasPendingPrayerDraft': false,
        },
      ]),
      PrayerRecordBadgeStatus.published,
    );
  });

  test('record badge treats unsaved local edits as draft state', () {
    expect(
      resolvePrayerRecordBadgeStatus(
        [
          {
            'prayerStatus': 'published',
            'hasPendingPrayerDraft': false,
          },
        ],
        isDirty: true,
      ),
      PrayerRecordBadgeStatus.draft,
    );
  });
}

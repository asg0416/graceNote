import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/models/models.dart';

void main() {
  test('PrayerEntryModel serializes phase3 snapshot fields when present', () {
    final prayer = PrayerEntryModel(
      weekId: 'week-1',
      groupId: 'group-1',
      authorId: 'profile-author',
      memberId: 'profile-member',
      directoryMemberId: 'directory-member-1',
      content: '기도제목',
      status: 'published',
      personId: 'person-1',
      membershipId: 'membership-1',
      recordedGroupId: 'recorded-group-1',
      recordedDepartmentId: 'recorded-department-1',
    );

    expect(prayer.toJson(), containsPair('person_id', 'person-1'));
    expect(prayer.toJson(), containsPair('membership_id', 'membership-1'));
    expect(prayer.toJson(), containsPair('recorded_group_id', 'recorded-group-1'));
    expect(
      prayer.toJson(),
      containsPair('recorded_department_id', 'recorded-department-1'),
    );
  });
}

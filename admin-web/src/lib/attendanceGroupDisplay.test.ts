import assert from 'node:assert/strict';
import test from 'node:test';
import { applyAttendanceWeekGroupDisplayNames } from './attendanceGroupDisplay.ts';

test('selected week roster name wins over current live group name for the same group id', () => {
  const groups = applyAttendanceWeekGroupDisplayNames(
    [
      { id: 'group-1', name: '1조-1', isActive: true },
      { id: 'group-2', name: '2조-2', isActive: true },
    ],
    [
      { groupId: 'group-1', groupName: '1조' },
      { groupId: 'group-2', groupName: '2조' },
    ]
  );

  assert.deepEqual(groups.map((group) => group.name), ['1조', '2조']);
});

test('groups without selected week evidence keep their current name', () => {
  const groups = applyAttendanceWeekGroupDisplayNames(
    [
      { id: 'group-1', name: '1조' },
      { id: 'group-4', name: '4조' },
    ],
    [{ groupId: 'group-1', groupName: '1조' }]
  );

  assert.deepEqual(groups.map((group) => group.name), ['1조', '4조']);
});

test('empty and unassigned names are ignored', () => {
  const groups = applyAttendanceWeekGroupDisplayNames(
    [{ id: 'group-1', name: '1조' }],
    [
      { groupId: 'group-1', groupName: ' ' },
      { groupId: 'group-1', groupName: '조 없음' },
    ]
  );

  assert.equal(groups[0].name, '1조');
});

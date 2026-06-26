import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canCopyRegroupingMemberToTargetGroup,
  getRegroupingEditorShellMode,
  isRegroupingSeasonPeriodCoveringDate,
  shouldCreateHistoricalUnassignedMoveRows,
  shouldAutoSyncRegroupingSeasonPeriodRows,
  buildRegroupingSuppressedHistoricalTargetKeys,
  shouldKeepMappedRegroupingSeasonMember,
  shouldHideHistoricalMoveSourceOnBoard,
  shouldUseRegroupingSeasonMemberAsVisibleAssigned,
  shouldUseRegroupingSeasonMemberAsVisibleUnassigned,
  isUnassignedPlaceholderPairedWithRemovedMembership,
  isMoveSourceMembershipPeriodClosure,
  isRegroupingBoardReadonly,
  shouldShowSeasonMemberPeriodChange,
} from './regroupingSeasonUiState.ts';

test('applied season boards are read-only', () => {
  assert.equal(isRegroupingBoardReadonly('season', 'applied'), true);
});

test('draft and ready season boards remain editable', () => {
  assert.equal(isRegroupingBoardReadonly('season', 'draft'), false);
  assert.equal(isRegroupingBoardReadonly('season', 'ready'), false);
});

test('live correction boards remain editable regardless of season status', () => {
  assert.equal(isRegroupingBoardReadonly('live', 'applied'), false);
  assert.equal(isRegroupingBoardReadonly('live', null), false);
});

test('copying a member is allowed only into an assigned group', () => {
  assert.equal(canCopyRegroupingMemberToTargetGroup('plan-group-1'), true);
  assert.equal(canCopyRegroupingMemberToTargetGroup(null), false);
});

test('editor shell switches between normal and focus mode', () => {
  assert.equal(getRegroupingEditorShellMode(false), 'normal');
  assert.equal(getRegroupingEditorShellMode(true), 'focus');
});

test('season end week covers the whole selected week', () => {
  assert.equal(
    isRegroupingSeasonPeriodCoveringDate({
      effectiveWeekDate: '2026-06-14',
      endWeekDate: '2026-06-21',
      dateInputValue: '2026-06-25',
    }),
    true
  );
});

test('applied season period edits still auto-sync default board row periods', () => {
  assert.equal(
    shouldAutoSyncRegroupingSeasonPeriodRows({
      mode: 'season',
      seasonStatus: 'applied',
    }),
    true
  );
  assert.equal(
    shouldAutoSyncRegroupingSeasonPeriodRows({
      mode: 'season',
      seasonStatus: 'draft',
    }),
    true
  );
});

test('inactive unassigned season assignment rows stay visible as planned unassigned members', () => {
  const plannedUnassignedMember = {
    season_assignment_id: 'assignment-unassigned',
    group_id: null,
    is_active: false,
    plan_change_type: null,
  };

  assert.equal(
    shouldKeepMappedRegroupingSeasonMember(plannedUnassignedMember),
    true
  );
  assert.equal(
    shouldUseRegroupingSeasonMemberAsVisibleUnassigned(plannedUnassignedMember),
    true
  );
});

test('inactive season assignment rows stay visible after assigning to a group', () => {
  const movedFromUnassignedMember = {
    season_assignment_id: 'assignment-unassigned',
    group_id: 'plan-group-1',
    is_active: false,
    plan_change_type: 'moved',
  };
  const inactiveDirectoryOnlyMember = {
    group_id: 'plan-group-1',
    is_active: false,
    plan_change_type: null,
  };

  assert.equal(
    shouldUseRegroupingSeasonMemberAsVisibleAssigned(movedFromUnassignedMember),
    true
  );
  assert.equal(
    shouldUseRegroupingSeasonMemberAsVisibleAssigned(inactiveDirectoryOnlyMember),
    false
  );
});

test('unassigned placeholder paired with removed membership is not a separate move history row', () => {
  const removedMembership = {
    id: 'removed-source',
    phase2_person_id: 'person-1',
    group_id: null,
    plan_change_type: 'removed',
    previous_source_group_id: 'live-group-1',
    source_membership_group_id: 'live-group-1',
  };
  const unassignedPlaceholder = {
    id: 'temp-unassigned-person-1',
    phase2_person_id: 'person-1',
    group_id: null,
    plan_change_type: null,
    previous_source_group_id: 'live-group-1',
    source_membership_group_id: 'live-group-1',
  };
  const standaloneUnassigned = {
    id: 'temp-unassigned-person-2',
    phase2_person_id: 'person-2',
    group_id: null,
    plan_change_type: null,
    previous_source_group_id: 'live-group-1',
    source_membership_group_id: 'live-group-1',
  };

  assert.equal(
    isUnassignedPlaceholderPairedWithRemovedMembership({
      member: unassignedPlaceholder,
      allMembers: [removedMembership, unassignedPlaceholder],
    }),
    true
  );
  assert.equal(
    isUnassignedPlaceholderPairedWithRemovedMembership({
      member: standaloneUnassigned,
      allMembers: [removedMembership, standaloneUnassigned],
    }),
    false
  );
});

test('draft season unassigned moves keep a single visible board card', () => {
  assert.equal(
    shouldCreateHistoricalUnassignedMoveRows({
      mode: 'season',
      isCurrentAppliedSeason: false,
    }),
    false
  );
});

test('live and current applied season unassigned moves keep historical rows', () => {
  assert.equal(
    shouldCreateHistoricalUnassignedMoveRows({
      mode: 'live',
      isCurrentAppliedSeason: false,
    }),
    true
  );
  assert.equal(
    shouldCreateHistoricalUnassignedMoveRows({
      mode: 'season',
      isCurrentAppliedSeason: true,
    }),
    true
  );
});

test('period change remains visible after user corrects the current value until save resets baseline', () => {
  assert.equal(
    shouldShowSeasonMemberPeriodChange({
      currentStart: '2026-02-01',
      currentEnd: '2026-06-28',
      expectedStart: '2026-02-01',
      expectedEnd: '2026-06-28',
      baselineStart: '2026-01-04',
      baselineEnd: '2026-06-28',
    }),
    true
  );
});

test('period change is hidden only when current and baseline both match expected range', () => {
  assert.equal(
    shouldShowSeasonMemberPeriodChange({
      currentStart: '2026-02-01',
      currentEnd: '2026-06-28',
      expectedStart: '2026-02-01',
      expectedEnd: '2026-06-28',
      baselineStart: '2026-02-01',
      baselineEnd: '2026-06-28',
    }),
    false
  );
});

test('move source membership closures are not treated as standalone period adjustments', () => {
  const sourceMembership = {
    id: 'source-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-group-3',
    source_membership_group_id: 'live-group-3',
    starts_week_date: '2026-06-14',
    ends_week_date: '2026-06-14',
  };
  const movedMembership = {
    id: 'moved-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-group-1',
    plan_change_type: 'moved',
    previous_source_group_id: 'live-group-3',
    starts_week_date: '2026-06-21',
    ends_week_date: '2026-12-27',
  };

  assert.equal(
    isMoveSourceMembershipPeriodClosure({
      member: sourceMembership,
      allMembers: [sourceMembership, movedMembership],
      currentSourceGroupId: 'live-group-3',
      seasonEffectiveWeekDate: '2026-06-14',
    }),
    true
  );
});

test('historical move source rows stay out of the editable board cards', () => {
  const sourceMembership = {
    id: 'source-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-new-family',
    source_membership_group_id: 'live-new-family',
    starts_week_date: '2026-03-08',
    ends_week_date: '2026-03-15',
  };
  const movedMembership = {
    id: 'moved-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-regular',
    plan_change_type: 'moved',
    previous_source_group_id: 'live-new-family',
    starts_week_date: '2026-03-22',
    ends_week_date: '2026-06-28',
  };

  assert.equal(
    shouldHideHistoricalMoveSourceOnBoard({
      member: sourceMembership,
      allMembers: [sourceMembership, movedMembership],
      seasonEffectiveWeekDate: '2026-01-04',
    }),
    true
  );
  assert.equal(
    shouldHideHistoricalMoveSourceOnBoard({
      member: movedMembership,
      allMembers: [sourceMembership, movedMembership],
      seasonEffectiveWeekDate: '2026-01-04',
    }),
    false
  );
});

test('persisted move source groups are not backfilled as period memberships', () => {
  const suppressedTargets = buildRegroupingSuppressedHistoricalTargetKeys({
    members: [
      {
        id: 'source-row',
        season_assignment_id: 'assignment-source',
        phase2_person_id: 'person-1',
        group_id: null,
        previous_source_group_id: 'live-group-3',
        source_membership_id: 'old-membership',
      },
      {
        id: 'moved-row',
        season_assignment_id: 'assignment-moved',
        phase2_person_id: 'person-1',
        group_id: 'plan-group-1',
        plan_change_type: 'moved',
        previous_source_group_id: 'live-group-3',
      },
    ],
    planGroups: [
      { id: 'plan-group-1', source_group_id: 'live-group-1' },
      { id: 'plan-group-3', source_group_id: 'live-group-3' },
    ],
  });

  assert.equal(suppressedTargets.has('person-1|plan-group-3'), true);
  assert.equal(suppressedTargets.has('person-1|plan-group-1'), false);
});

test('manual period adjustments remain visible when they are not paired with a move', () => {
  const sourceMembership = {
    id: 'source-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-group-3',
    source_membership_group_id: 'live-group-3',
    starts_week_date: '2026-06-14',
    ends_week_date: '2026-06-21',
  };
  const movedMembership = {
    id: 'moved-row',
    phase2_person_id: 'person-1',
    group_id: 'plan-group-1',
    plan_change_type: 'moved',
    previous_source_group_id: 'live-group-3',
    starts_week_date: '2026-06-21',
    ends_week_date: '2026-12-27',
  };

  assert.equal(
    isMoveSourceMembershipPeriodClosure({
      member: sourceMembership,
      allMembers: [sourceMembership, movedMembership],
      currentSourceGroupId: 'live-group-3',
      seasonEffectiveWeekDate: '2026-06-14',
    }),
    false
  );
});

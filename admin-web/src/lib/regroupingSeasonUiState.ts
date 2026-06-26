export type RegroupingMode = 'season' | 'live';
export type RegroupingSeasonStatus = 'draft' | 'ready' | 'applied' | 'archived' | 'cancelled' | null | undefined;

export const isRegroupingBoardReadonly = (
  mode: RegroupingMode,
  seasonStatus: RegroupingSeasonStatus
) => mode === 'season' && seasonStatus === 'applied';

export const canCopyRegroupingMemberToTargetGroup = (targetGroupId?: string | null) =>
  Boolean(targetGroupId);

export const getRegroupingEditorShellMode = (isFocusMode: boolean) =>
  isFocusMode ? 'focus' : 'normal';

const addDaysToDateInput = (value: string, dayCount: number) => {
  const base = new Date(`${value}T00:00:00`);
  if (Number.isNaN(base.getTime())) return value;
  base.setDate(base.getDate() + dayCount);
  const year = base.getFullYear();
  const month = String(base.getMonth() + 1).padStart(2, '0');
  const day = String(base.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
};

export const isRegroupingSeasonPeriodCoveringDate = ({
  effectiveWeekDate,
  endWeekDate,
  dateInputValue,
}: {
  effectiveWeekDate?: string | null;
  endWeekDate?: string | null;
  dateInputValue: string;
}) => {
  if (!effectiveWeekDate || effectiveWeekDate > dateInputValue) return false;
  if (!endWeekDate) return true;
  return addDaysToDateInput(endWeekDate, 6) >= dateInputValue;
};

export const shouldAutoSyncRegroupingSeasonPeriodRows = ({
  mode,
}: {
  mode: RegroupingMode;
  seasonStatus: RegroupingSeasonStatus;
}) => mode === 'season';

type SeasonMemberPeriodChangeInput = {
  currentStart?: string | null;
  currentEnd?: string | null;
  expectedStart?: string | null;
  expectedEnd?: string | null;
  baselineStart?: string | null;
  baselineEnd?: string | null;
};

type SeasonMembershipRow = {
  id?: string | null;
  season_assignment_id?: string | null;
  phase2_person_id?: string | null;
  person_id?: string | null;
  source_member_directory_id?: string | null;
  source_membership_id?: string | null;
  full_name?: string | null;
  phone?: string | null;
  group_id?: string | null;
  source_membership_group_id?: string | null;
  previous_source_group_id?: string | null;
  starts_week_date?: string | null;
  ends_week_date?: string | null;
  plan_change_type?: string | null;
  change_type?: string | null;
  is_active?: boolean | null;
};

type SeasonPlanGroupRow = {
  id?: string | null;
  source_group_id?: string | null;
};

const normalizeWeekDate = (value?: string | null) => value || null;

const normalizeText = (value?: string | null) =>
  typeof value === 'string' && value.trim() ? value.trim() : null;

const normalizePhone = (value?: string | null) =>
  typeof value === 'string' ? value.replace(/[^0-9]/g, '') : '';

export const shouldKeepMappedRegroupingSeasonMember = (member: SeasonMembershipRow) => {
  const changeType = normalizeText(member.plan_change_type) || normalizeText(member.change_type);
  if (changeType === 'removed') return true;
  if (normalizeText(member.group_id)) return true;
  if (normalizeText(member.season_assignment_id)) return true;
  return member.is_active !== false;
};

export const shouldUseRegroupingSeasonMemberAsVisibleUnassigned = (member: SeasonMembershipRow) => {
  const changeType = normalizeText(member.plan_change_type) || normalizeText(member.change_type);
  return changeType !== 'removed' &&
    !normalizeText(member.group_id) &&
    Boolean(normalizeText(member.season_assignment_id));
};

export const shouldUseRegroupingSeasonMemberAsVisibleAssigned = (member: SeasonMembershipRow) => {
  const changeType = normalizeText(member.plan_change_type) || normalizeText(member.change_type);
  return changeType !== 'removed' &&
    Boolean(normalizeText(member.group_id)) &&
    (
      member.is_active !== false ||
      Boolean(normalizeText(member.season_assignment_id))
    );
};

const getSeasonMembershipIdentityKey = (member: SeasonMembershipRow) => {
  const id = normalizeText(member.phase2_person_id)
    || normalizeText(member.person_id)
    || normalizeText(member.source_member_directory_id);
  if (id) return id;

  const name = normalizeText(member.full_name);
  const phone = normalizePhone(member.phone);
  return name && phone ? `${name}|${phone}` : null;
};

const getPreviousWeekDate = (value?: string | null) => {
  if (!value) return null;
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return null;
  date.setDate(date.getDate() - 7);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
};

const getSourceGroupId = (member: SeasonMembershipRow, fallbackGroupId?: string | null) =>
  normalizeText(member.source_membership_group_id)
  || normalizeText(member.previous_source_group_id)
  || normalizeText(fallbackGroupId);

export const buildRegroupingSuppressedHistoricalTargetKeys = ({
  members,
  planGroups,
}: {
  members: SeasonMembershipRow[];
  planGroups: SeasonPlanGroupRow[];
}) => {
  const planGroupIdBySourceGroupId = new Map<string, string>();
  const planGroupIds = new Set<string>();

  planGroups.forEach(group => {
    const planGroupId = normalizeText(group.id);
    if (!planGroupId) return;
    planGroupIds.add(planGroupId);

    const sourceGroupId = normalizeText(group.source_group_id);
    if (sourceGroupId) {
      planGroupIdBySourceGroupId.set(sourceGroupId, planGroupId);
    }
  });

  const suppressedTargets = new Set<string>();
  members.forEach(member => {
    const identityKey = getSeasonMembershipIdentityKey(member);
    const previousSourceGroupId = normalizeText(member.previous_source_group_id)
      || normalizeText(member.source_membership_group_id);
    if (!identityKey || !previousSourceGroupId) return;

    const changeType = normalizeText(member.plan_change_type) || normalizeText(member.change_type);
    const isPersistedSourceClosure = !normalizeText(member.group_id) && Boolean(
      normalizeText(member.season_assignment_id)
      || normalizeText(member.source_membership_id)
      || normalizeText(member.source_member_directory_id)
    );
    if (changeType !== 'moved' && changeType !== 'removed' && !isPersistedSourceClosure) return;

    const planGroupId = planGroupIdBySourceGroupId.get(previousSourceGroupId)
      || (planGroupIds.has(previousSourceGroupId) ? previousSourceGroupId : null);
    if (!planGroupId) return;

    suppressedTargets.add(`${identityKey}|${planGroupId}`);
  });

  return suppressedTargets;
};

export const isMoveSourceMembershipPeriodClosure = ({
  member,
  allMembers,
  currentSourceGroupId,
  seasonEffectiveWeekDate,
}: {
  member: SeasonMembershipRow;
  allMembers: SeasonMembershipRow[];
  currentSourceGroupId?: string | null;
  seasonEffectiveWeekDate: string;
}) => {
  const identityKey = getSeasonMembershipIdentityKey(member);
  const sourceGroupId = normalizeText(currentSourceGroupId) || getSourceGroupId(member, member.group_id);
  const closedEndWeekDate = normalizeWeekDate(member.ends_week_date);
  if (!identityKey || !sourceGroupId || !closedEndWeekDate) return false;

  return allMembers.some(candidate => {
    if (candidate === member) return false;
    const candidateChangeType = normalizeText(candidate.plan_change_type) || normalizeText(candidate.change_type);
    if (candidateChangeType !== 'moved') return false;
    if (getSeasonMembershipIdentityKey(candidate) !== identityKey) return false;
    if (getSourceGroupId(candidate) !== sourceGroupId) return false;

    const moveStartWeekDate = normalizeWeekDate(candidate.starts_week_date) || seasonEffectiveWeekDate;
    return getPreviousWeekDate(moveStartWeekDate) === closedEndWeekDate;
  });
};

export const shouldHideHistoricalMoveSourceOnBoard = ({
  member,
  allMembers,
  seasonEffectiveWeekDate,
}: {
  member: SeasonMembershipRow;
  allMembers: SeasonMembershipRow[];
  seasonEffectiveWeekDate: string;
}) => {
  const changeType = normalizeText(member.plan_change_type) || normalizeText(member.change_type);
  if (changeType === 'moved' || changeType === 'added' || changeType === 'removed') return false;
  if (!normalizeText(member.group_id)) return false;

  const sourceGroupId = getSourceGroupId(member, member.group_id);
  return isMoveSourceMembershipPeriodClosure({
    member,
    allMembers,
    currentSourceGroupId: sourceGroupId,
    seasonEffectiveWeekDate,
  });
};

export const shouldShowSeasonMemberPeriodChange = ({
  currentStart,
  currentEnd,
  expectedStart,
  expectedEnd,
  baselineStart,
  baselineEnd,
}: SeasonMemberPeriodChangeInput) => {
  const expectedStartDate = normalizeWeekDate(expectedStart);
  const expectedEndDate = normalizeWeekDate(expectedEnd);

  const currentDiffers = normalizeWeekDate(currentStart) !== expectedStartDate
    || normalizeWeekDate(currentEnd) !== expectedEndDate;
  const baselineDiffers = normalizeWeekDate(baselineStart) !== expectedStartDate
    || normalizeWeekDate(baselineEnd) !== expectedEndDate;

  return currentDiffers || baselineDiffers;
};

export const shouldCreateHistoricalUnassignedMoveRows = ({
  mode,
  isCurrentAppliedSeason,
}: {
  mode: RegroupingMode;
  isCurrentAppliedSeason: boolean;
}) => mode === 'live' || isCurrentAppliedSeason;

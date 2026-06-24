export type RegroupingMode = 'season' | 'live';
export type RegroupingSeasonStatus = 'draft' | 'ready' | 'applied' | 'archived' | 'cancelled' | null | undefined;

export const isRegroupingBoardReadonly = (
  mode: RegroupingMode,
  seasonStatus: RegroupingSeasonStatus
) => mode === 'season' && seasonStatus === 'applied';

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
  phase2_person_id?: string | null;
  person_id?: string | null;
  source_member_directory_id?: string | null;
  full_name?: string | null;
  phone?: string | null;
  group_id?: string | null;
  source_membership_group_id?: string | null;
  previous_source_group_id?: string | null;
  starts_week_date?: string | null;
  ends_week_date?: string | null;
  plan_change_type?: string | null;
  change_type?: string | null;
};

const normalizeWeekDate = (value?: string | null) => value || null;

const normalizeText = (value?: string | null) =>
  typeof value === 'string' && value.trim() ? value.trim() : null;

const normalizePhone = (value?: string | null) =>
  typeof value === 'string' ? value.replace(/[^0-9]/g, '') : '';

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

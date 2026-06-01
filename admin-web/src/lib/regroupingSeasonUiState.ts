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

const normalizeWeekDate = (value?: string | null) => value || null;

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

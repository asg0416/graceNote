export const canDeletePendingRegroupingSeason = (season: {
  status?: string | null;
  effective_week_date?: string | null;
}) => ['draft', 'ready'].includes(String(season.status || ''));

export const canApplyRegroupingSeason = ({
  mode,
  hasSelectedSeason,
  isApplied,
  isFuture,
  hasInvalidPeriod,
  hasOverlappingPeriod,
  hasUnsavedChanges,
}: {
  mode: 'season' | 'live';
  hasSelectedSeason: boolean;
  isApplied: boolean;
  isFuture: boolean;
  hasInvalidPeriod: boolean;
  hasOverlappingPeriod: boolean;
  hasUnsavedChanges: boolean;
}) => mode === 'season' &&
  hasSelectedSeason &&
  !isApplied &&
  !isFuture &&
  !hasInvalidPeriod &&
  !hasOverlappingPeriod &&
  !hasUnsavedChanges;

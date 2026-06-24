export const shouldReturnToSeasonListOnMissingSeasonQuery = ({
  seasonIdFromQuery,
  selectedSeasonId,
  regroupingView,
  pendingSeasonUrlSyncId,
}: {
  seasonIdFromQuery?: string | null;
  selectedSeasonId?: string | null;
  regroupingView: 'list' | 'seasonEditor' | 'liveCorrection';
  pendingSeasonUrlSyncId?: string | null;
}) => (
  !seasonIdFromQuery &&
  regroupingView !== 'list' &&
  Boolean(selectedSeasonId) &&
  pendingSeasonUrlSyncId !== selectedSeasonId
);

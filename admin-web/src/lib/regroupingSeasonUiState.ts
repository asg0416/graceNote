export type RegroupingMode = 'season' | 'live';
export type RegroupingSeasonStatus = 'draft' | 'ready' | 'applied' | 'archived' | 'cancelled' | null | undefined;

export const isRegroupingBoardReadonly = (
  mode: RegroupingMode,
  seasonStatus: RegroupingSeasonStatus
) => mode === 'season' && seasonStatus === 'applied';

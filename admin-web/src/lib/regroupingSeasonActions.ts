export const canDeletePendingRegroupingSeason = (season: {
  status?: string | null;
  effective_week_date?: string | null;
}) => ['draft', 'ready'].includes(String(season.status || ''));

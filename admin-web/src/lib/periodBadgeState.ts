export const isPeriodEdited = (
    initialStart?: string | null,
    initialEnd?: string | null,
    currentStart?: string | null,
    currentEnd?: string | null
) => (initialStart || null) !== (currentStart || null) || (initialEnd || null) !== (currentEnd || null);

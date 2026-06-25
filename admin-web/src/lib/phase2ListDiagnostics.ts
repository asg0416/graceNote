type DiagnosticLegacyMember = {
  id: string;
  phase2PersonId?: string | null;
  personKey: string;
};

type DiagnosticPlanAssignment = {
  personId?: string | null;
};

type CurrentSeasonPhase2ListCheckInput = {
  activeLegacyMembers: DiagnosticLegacyMember[];
  planAssignments: DiagnosticPlanAssignment[];
};

export type CurrentSeasonPhase2ListCheckResult = {
  legacyActiveCount: number;
  phase2ActiveCount: number;
  legacyActivePersonCount: number;
  phase2ActivePersonCount: number;
  missingCount: number;
  extraCount: number;
  issueCount: number;
};

const isPresentText = (value?: string | null): value is string => Boolean(value);

export const buildCurrentSeasonPhase2ListCheck = ({
  activeLegacyMembers,
  planAssignments,
}: CurrentSeasonPhase2ListCheckInput): CurrentSeasonPhase2ListCheckResult => {
  const activeLegacyPersonIds = new Set(activeLegacyMembers.map(member => member.personKey));
  const activeLegacyPhase2PersonIds = new Set(
    activeLegacyMembers
      .map(member => member.phase2PersonId)
      .filter(isPresentText)
  );
  const planPersonIds = new Set(
    planAssignments
      .map(row => row.personId)
      .filter(isPresentText)
  );
  const missingLinkedCount = Array.from(activeLegacyPhase2PersonIds)
    .filter(personId => !planPersonIds.has(personId))
    .length;
  const missingUnlinkedCount = activeLegacyMembers
    .filter(member => !member.phase2PersonId)
    .length;
  const missingCount = missingLinkedCount + missingUnlinkedCount;
  const extraCount = Array.from(planPersonIds)
    .filter(personId => !activeLegacyPhase2PersonIds.has(personId))
    .length;

  return {
    legacyActiveCount: activeLegacyMembers.length,
    phase2ActiveCount: planAssignments.filter(row => isPresentText(row.personId)).length,
    legacyActivePersonCount: activeLegacyPersonIds.size,
    phase2ActivePersonCount: planPersonIds.size,
    missingCount,
    extraCount,
    issueCount: missingCount + extraCount,
  };
};

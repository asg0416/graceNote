import { spawnSync } from 'node:child_process';

export const localGates = [
  {
    name: 'regrouping season boundary',
    command: ['node', 'scripts/verify-regrouping-season-boundary.mjs'],
  },
];

export const runLocalGates = () => {
  const results = [];
  let hasFailure = false;

  for (const gate of localGates) {
    const [command, ...args] = gate.command;
    const result = spawnSync(command, args, {
      cwd: process.cwd(),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    const passed = result.status === 0;
    if (!passed) hasFailure = true;

    results.push({
      name: gate.name,
      passed,
      stdout: result.stdout.trim(),
      stderr: result.stderr.trim(),
    });
  }

  return { results, hasFailure };
};

export const printLocalGateSummary = ({ results }) => {
  console.log('\n## Local preprod gates');

  for (const result of results) {
    console.log(`- ${result.name}: ${result.passed ? 'PASS' : 'FAILED'}`);
    if (result.stdout) console.log(result.stdout);
    if (result.stderr) console.log(result.stderr);
  }
};

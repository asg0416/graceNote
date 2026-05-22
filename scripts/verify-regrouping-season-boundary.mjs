import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

const BLOCKED_TOKENS = [
  'regrouping_seasons',
  'regrouping_plan_groups',
  'regrouping_plan_assignments',
  'create_regrouping_season',
  'save_regrouping_season_draft',
  'apply_regrouping_season',
];

const SCANNED_EXTENSIONS = new Set(['.dart', '.ts', '.tsx', '.js', '.mjs', '.sql']);
const IGNORED_DIRS = new Set([
  '.git',
  '.next',
  '.dart_tool',
  'build',
  'node_modules',
  'coverage',
]);

const ALWAYS_ALLOWED_PREFIXES = [
  'docs/',
  'supabase/migrations/',
  'supabase/verify_',
  'scripts/verify-regrouping-season-boundary',
];

const RUNTIME_ALLOWED_PREFIXES = [
  'admin-web/src/app/regrouping/',
  'admin-web/src/lib/regroupingSeason',
];

const hasScannedExtension = (filePath) => {
  const index = filePath.lastIndexOf('.');
  if (index === -1) return false;
  return SCANNED_EXTENSIONS.has(filePath.slice(index));
};

const normalizeRelativePath = (root, filePath) =>
  relative(root, filePath).split('\\').join('/');

const isAllowedReferencePath = (relativePath) =>
  ALWAYS_ALLOWED_PREFIXES.some(prefix => relativePath.startsWith(prefix)) ||
  RUNTIME_ALLOWED_PREFIXES.some(prefix => relativePath.startsWith(prefix));

async function walkFiles(root, current = root) {
  const entries = await readdir(current, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    if (IGNORED_DIRS.has(entry.name)) continue;
    const fullPath = join(current, entry.name);
    if (entry.isDirectory()) {
      files.push(...await walkFiles(root, fullPath));
    } else if (entry.isFile() && hasScannedExtension(entry.name)) {
      files.push(fullPath);
    }
  }

  return files;
}

export async function findRegroupingSeasonBoundaryViolations(root = process.cwd()) {
  const files = await walkFiles(root);
  const violations = [];

  for (const filePath of files) {
    const relativePath = normalizeRelativePath(root, filePath);
    if (isAllowedReferencePath(relativePath)) continue;

    const contents = await readFile(filePath, 'utf8');
    const matchedTokens = BLOCKED_TOKENS.filter(token => contents.includes(token));
    if (matchedTokens.length > 0) {
      violations.push(`${relativePath}: ${matchedTokens.join(', ')}`);
    }
  }

  return violations;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  const violations = await findRegroupingSeasonBoundaryViolations();
  if (violations.length > 0) {
    console.error('Regrouping season draft references leaked into operational code:');
    for (const violation of violations) {
      console.error(`- ${violation}`);
    }
    process.exit(1);
  }

  console.log('Regrouping season boundary OK: draft tables/RPCs are isolated from operational app code.');
}

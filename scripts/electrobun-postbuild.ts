import { cpSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const targetOs = process.env.ELECTROBUN_OS ?? '';
if (targetOs !== 'macos') {
  process.exit(0);
}

const buildDir = process.env.ELECTROBUN_BUILD_DIR ?? '';
if (!buildDir) {
  console.warn('[postBuild] ELECTROBUN_BUILD_DIR is missing');
  process.exit(0);
}

const sourceIconPath = join(process.cwd(), 'assets', 'icons', 'icon.icns');
if (!existsSync(sourceIconPath)) {
  console.warn(`[postBuild] Source icon not found: ${sourceIconPath}`);
  process.exit(0);
}

const appBundles = readdirSync(buildDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && entry.name.endsWith('.app'))
  .map((entry) => join(buildDir, entry.name));

if (appBundles.length === 0) {
  console.warn(`[postBuild] No .app bundle found in ${buildDir}`);
  process.exit(0);
}

for (const appBundlePath of appBundles) {
  const resourcesPath = join(appBundlePath, 'Contents', 'Resources');
  if (!existsSync(resourcesPath)) {
    continue;
  }

  const destinationIconPath = join(resourcesPath, 'AppIcon.icns');
  cpSync(sourceIconPath, destinationIconPath, { dereference: true });
  console.log(`[postBuild] Wrote icon: ${destinationIconPath}`);
}

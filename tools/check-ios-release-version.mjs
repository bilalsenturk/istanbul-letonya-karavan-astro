import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));

function read(relativePath) {
  return readFileSync(`${root}/${relativePath}`, 'utf8');
}

function parseInteger(rawValue, label) {
  const normalized = String(rawValue)
    .trim()
    .replace(/^['"]|['"]$/g, '');
  if (!/^\d+$/.test(normalized) || Number(normalized) < 1) {
    throw new Error(`${label} pozitif bir tam sayı olmalı (bulunan: ${JSON.stringify(rawValue)})`);
  }
  return Number(normalized);
}

function collectBuilds() {
  const yaml = read('ios/project.yml');
  const yamlMatches = [...yaml.matchAll(/^\s*CURRENT_PROJECT_VERSION:\s*([^\s#]+)\s*(?:#.*)?$/gm)];
  if (yamlMatches.length !== 2) {
    throw new Error(`ios/project.yml app ve widget için iki build değeri içermeli (bulunan: ${yamlMatches.length})`);
  }

  const project = read('ios/Kuzey.xcodeproj/project.pbxproj');
  const projectMatches = [...project.matchAll(/^\s*CURRENT_PROJECT_VERSION\s*=\s*([^;]+);\s*$/gm)];
  if (projectMatches.length !== 4) {
    throw new Error(
      `Kuzey.xcodeproj app ve widget yapılandırmaları için dört build değeri içermeli (bulunan: ${projectMatches.length})`,
    );
  }

  const manifest = JSON.parse(read('public/kuzey-version.json'));
  const latestBuild = parseInteger(manifest.latestBuild, 'manifest latestBuild');
  const minBuild = parseInteger(manifest.minBuild, 'manifest minBuild');
  if (minBuild > latestBuild) {
    throw new Error(`manifest minBuild (${minBuild}) latestBuild'den (${latestBuild}) büyük olamaz`);
  }

  return [
    ...yamlMatches.map((match, index) => ({
      label: `project.yml target ${index + 1}`,
      value: parseInteger(match[1], `project.yml target ${index + 1}`),
    })),
    ...projectMatches.map((match, index) => ({
      label: `project.pbxproj config ${index + 1}`,
      value: parseInteger(match[1], `project.pbxproj config ${index + 1}`),
    })),
    { label: 'kuzey-version.json latestBuild', value: latestBuild },
  ];
}

try {
  const builds = collectBuilds();
  const versions = [...new Set(builds.map(({ value }) => value))];
  if (versions.length !== 1) {
    const details = builds.map(({ label, value }) => `${label}=${value}`).join(', ');
    throw new Error(`iOS build sürümleri eşleşmiyor: ${details}`);
  }

  console.log(`✅ iOS sürüm zinciri tutarlı: build ${versions[0]} (${builds.length} kaynak)`);
} catch (error) {
  console.error(`❌ ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}

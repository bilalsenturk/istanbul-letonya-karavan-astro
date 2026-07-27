#!/usr/bin/env node
// Letonca içerik paketini üretir.
//
//   OPENROUTER_API_KEY=... node tools/generate-latvian-pack.mjs --text     # kelime/cümle üret + denetle
//   OPENROUTER_API_KEY=... node tools/generate-latvian-pack.mjs --audio    # sesleri üret (Görev 8)
//   ... --scene lv-s03-markette   # yalnızca bir sahne
//   ... --dry-run                 # istek atmadan istemi göster
//
// Taslak her sahne sonunda kaydedilir; yarıda kalırsa aynı komut kaldığı yerden devam eder.

import fs from 'node:fs/promises';
import path from 'node:path';

import { audioIdFor } from '../src/learning-lv/audio.ts';
import { filterByFrequency, parseFrequencyList } from '../src/learning-lv/frequency.ts';
import {
  applyReview,
  buildReviewRequest,
  buildSceneRequest,
  parseReviewResponse,
  parseSceneResponse,
} from '../src/learning-lv/generate-prompts.ts';
import { SCENE_PLAN } from '../src/learning-lv/scenes.ts';

const CHAT_URL = 'https://openrouter.ai/api/v1/chat/completions';
const CONTENT_MODEL = process.env.OPENROUTER_CONTENT_MODEL ?? 'google/gemini-3.5-flash';
const REVIEW_MODEL = process.env.OPENROUTER_REVIEW_MODEL ?? 'google/gemini-3.5-flash';
const MAX_FREQ_RANK = 20000;
const BASE_ALLOW_LIST = ['Turcija', 'no Turcijas', 'Latvija', 'Rīga', 'eiro', 'kempings'];
const ALLOW_LIST = [...new Set([...BASE_ALLOW_LIST, ...SCENE_PLAN.flatMap(scene => scene.seedWords)])];

const args = process.argv.slice(2);
const flagValue = name => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const hasFlag = name => args.includes(name);

const root = process.cwd();
const draftPath = path.join(root, 'data/lv-pack-draft.json');
const frequencyPath = path.join(root, 'data/lv-frequency-top20000.txt');

const onlyScene = flagValue('--scene');
const dryRun = hasFlag('--dry-run');

if (!hasFlag('--text')) {
  console.error('Kullanım: node tools/generate-latvian-pack.mjs --text [--scene <id>] [--dry-run]');
  process.exit(1);
}

const apiKey = process.env.OPENROUTER_API_KEY;
if (!apiKey && !dryRun) {
  console.error('OPENROUTER_API_KEY tanımlı değil.');
  process.exit(1);
}

const ranks = parseFrequencyList(await fs.readFile(frequencyPath, 'utf8'));
const draft = await readDraft();

for (const scene of SCENE_PLAN) {
  if (onlyScene && scene.id !== onlyScene) continue;
  if (draft.scenes[scene.id] && !onlyScene) {
    console.log(`↷ ${scene.title} zaten üretilmiş, atlanıyor`);
    continue;
  }

  console.log(`\n▸ ${scene.index}. ${scene.title}`);
  const request = buildSceneRequest(scene, CONTENT_MODEL);

  if (dryRun) {
    console.log(request.messages[1].content);
    continue;
  }

  const generated = parseSceneResponse(await chat(request));
  console.log(`  üretildi: ${generated.words.length} kelime, ${generated.sentences.length} cümle`);

  const verdicts = parseReviewResponse(await chat(buildReviewRequest(generated, scene, REVIEW_MODEL)));
  const { accepted, dropped, unreviewed } = applyReview(generated, verdicts);
  for (const entry of dropped) console.log(`  ✗ ${entry.lv} — ${entry.reason}`);
  if (unreviewed.length > 0) {
    console.log(`  ⚠ ${unreviewed.length} madde denetlenmedi: ${unreviewed.slice(0, 3).join(', ')}`);
  }

  const wordFilter = filterByFrequency(accepted.words, ranks, {
    maxRank: MAX_FREQ_RANK,
    allowList: ALLOW_LIST,
  });
  for (const entry of wordFilter.rejected) console.log(`  ✗ ${entry.lv} — ${entry.reason}`);
  const invented = wordFilter.rejected.filter(entry => entry.reason.startsWith('frekans listesinde yok')).length;
  const tooRare = wordFilter.rejected.filter(entry => entry.reason.startsWith('çok nadir')).length;
  if (invented > 0 || tooRare > 0) {
    console.log(`  ${scene.title}: ${invented} uydurma (listede yok), ${tooRare} çok nadir`);
  }

  const keptWords = new Set(wordFilter.kept.map(word => word.lv.toLowerCase()));
  const sentences = accepted.sentences
    .map(sentence => ({
      ...sentence,
      usesWords: sentence.usesWords.filter(lv => keptWords.has(lv.toLowerCase())),
    }))
    .filter(sentence => sentence.usesWords.length > 0);

  draft.scenes[scene.id] = {
    words: wordFilter.kept.map(word => ({ ...word, audioId: audioIdFor(word.lv) })),
    sentences: sentences.map(sentence => ({ ...sentence, audioId: audioIdFor(sentence.lv) })),
  };
  await writeDraft(draft);
  console.log(`  ✓ kaydedildi: ${draft.scenes[scene.id].words.length} kelime, ${draft.scenes[scene.id].sentences.length} cümle`);
}

console.log('\nMetin aşaması tamam.');

async function chat(request) {
  const response = await fetch(CHAT_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://istanbul-letonya-karavan-astro.vercel.app',
      'X-Title': 'Kuzey Letonca',
    },
    body: JSON.stringify(request),
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    throw new Error(`OpenRouter ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
  const payload = await response.json();
  const content = payload.choices?.[0]?.message?.content;
  if (!content) throw new Error('OpenRouter yanıtında içerik yok');
  return content;
}

async function readDraft() {
  try {
    return JSON.parse(await fs.readFile(draftPath, 'utf8'));
  } catch {
    return { scenes: {} };
  }
}

async function writeDraft(value) {
  await fs.mkdir(path.dirname(draftPath), { recursive: true });
  await fs.writeFile(draftPath, `${JSON.stringify(value, null, 2)}\n`);
}

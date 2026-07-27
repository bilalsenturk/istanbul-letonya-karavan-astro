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

import {
  assertUsableAudio,
  audioIdFor,
  buildSpeechRequest,
  extractAudioFromStream,
  wrapPcm16AsWav,
} from '../src/learning-lv/audio.ts';
import { filterByFrequency, parseFrequencyList } from '../src/learning-lv/frequency.ts';
import {
  applyReview,
  buildReviewRequest,
  buildSceneRequest,
  parseReviewResponse,
  parseSceneResponse,
} from '../src/learning-lv/generate-prompts.ts';
import { PACK_VERSION, validatePack } from '../src/learning-lv/pack-schema.ts';
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

const stages = {
  text: hasFlag('--text'),
  audio: hasFlag('--audio'),
  pack: hasFlag('--pack'),
  upload: hasFlag('--upload'),
};

if (!stages.text && !stages.audio && !stages.pack && !stages.upload) {
  console.error(
    'Kullanım: node tools/generate-latvian-pack.mjs [--text] [--audio] [--pack] [--upload] [--scene <id>] [--dry-run]',
  );
  process.exit(1);
}

const apiKey = process.env.OPENROUTER_API_KEY;
if (!apiKey && !dryRun && (stages.text || stages.audio)) {
  console.error('OPENROUTER_API_KEY tanımlı değil.');
  process.exit(1);
}

const draft = await readDraft();

if (stages.text) {
  const ranks = parseFrequencyList(await fs.readFile(frequencyPath, 'utf8'));
  let emptySceneCount = 0;

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

    const sceneResult = {
      words: wordFilter.kept.map(word => ({ ...word, audioId: audioIdFor(word.lv) })),
      sentences: sentences.map(sentence => ({ ...sentence, audioId: audioIdFor(sentence.lv) })),
    };

    if (sceneResult.words.length === 0 || sceneResult.sentences.length === 0) {
      emptySceneCount += 1;
      console.log(
        `  ⚠ UYARI: ${scene.title} boş döndü (${sceneResult.words.length} kelime, ${sceneResult.sentences.length} cümle) — kaydedilmedi, sonraki çalıştırmada tekrar denenecek`,
      );
      continue;
    }

    draft.scenes[scene.id] = sceneResult;
    await writeDraft(draft);
    console.log(`  ✓ kaydedildi: ${draft.scenes[scene.id].words.length} kelime, ${draft.scenes[scene.id].sentences.length} cümle`);
  }

  if (emptySceneCount > 0) {
    console.log(`\n${emptySceneCount} sahne boş döndü, sonraki çalıştırmada tekrar denenecek`);
  }
  console.log('\nMetin aşaması tamam.');
}

const audioDir = path.join(root, 'data/lv-audio');
const packPath = path.join(root, 'ios/Karavan/Resources/latvian-pack.json');
const SPEECH_MODEL = process.env.OPENROUTER_TTS_MODEL ?? 'openai/gpt-audio-mini';
const SPEECH_VOICE = process.env.OPENROUTER_TTS_VOICE ?? 'nova';

if (stages.audio) {
  await fs.mkdir(audioDir, { recursive: true });
  const targets = collectAudioTargets(draft);
  console.log(`\n▸ ${targets.length} ses hedefi`);

  let produced = 0;
  let skipped = 0;
  let failed = 0;
  for (const target of targets) {
    const filePath = path.join(audioDir, `${target.audioId}.wav`);
    if (await exists(filePath)) {
      skipped += 1;
      continue;
    }
    if (dryRun) {
      console.log(`  · ${target.audioId} ← "${target.text}"`);
      continue;
    }
    try {
      const wav = await synthesize(target.text);
      await writeFileAtomic(filePath, wav);
      produced += 1;
      console.log(`  ✓ ${target.audioId} "${target.text}" (${Math.round(wav.length / 1024)} KB)`);
    } catch (error) {
      failed += 1;
      console.error(`  ✗ ${target.audioId} "${target.text}" — ${error.message}`);
    }
  }
  console.log(`Ses aşaması tamam: ${produced} üretildi, ${skipped} atlandı, ${failed} başarısız.`);
}

if (stages.pack) {
  const audioBaseUrl = process.env.LV_AUDIO_BASE_URL ?? draft.audioBaseUrl;
  if (!audioBaseUrl) {
    console.error('LV_AUDIO_BASE_URL tanımlı değil ve taslakta kayıtlı değil. Önce --upload çalıştır.');
    process.exit(1);
  }
  if (Object.keys(draft.scenes).length === 0) {
    console.error('Taslakta hiç sahne yok. Önce --text çalıştır.');
    process.exit(1);
  }
  const pack = buildPack(draft, audioBaseUrl);
  validatePack(pack);
  await fs.writeFile(packPath, `${JSON.stringify(pack, null, 2)}\n`);
  const wordCount = pack.scenes.reduce((sum, scene) => sum + scene.words.length, 0);
  const sentenceCount = pack.scenes.reduce((sum, scene) => sum + scene.sentences.length, 0);
  console.log(`\nPaket yazıldı: ${pack.scenes.length} sahne, ${wordCount} kelime, ${sentenceCount} cümle`);
  console.log(`  → ${path.relative(root, packPath)}`);
}

if (stages.upload) {
  const { put } = await import('@vercel/blob');
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) {
    console.error('BLOB_READ_WRITE_TOKEN tanımlı değil.');
    process.exit(1);
  }
  let files;
  try {
    files = (await fs.readdir(audioDir)).filter(name => name.endsWith('.wav'));
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error(`Ses klasörü yok: ${audioDir}. Önce --audio çalıştır.`);
      process.exit(1);
    }
    throw err;
  }
  if (files.length === 0) {
    console.error(`Ses klasöründe .wav dosyası yok: ${audioDir}. Önce --audio çalıştır.`);
    process.exit(1);
  }
  console.log(`\n▸ ${files.length} ses dosyası yükleniyor`);
  let base;
  for (const name of files) {
    const blob = await put(`letonca/ses/${name}`, await fs.readFile(path.join(audioDir, name)), {
      access: 'public',
      token,
      contentType: 'audio/wav',
      addRandomSuffix: false,
      allowOverwrite: true,
    });
    base ??= blob.url.slice(0, blob.url.lastIndexOf('/'));
  }
  if (base) {
    draft.audioBaseUrl = base;
    await writeDraft(draft);
    console.log(`Yükleme tamam. audioBaseUrl: ${base}`);
  }
}

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
  let raw;
  try {
    raw = await fs.readFile(draftPath, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return { scenes: {} };
    throw err;
  }

  try {
    return JSON.parse(raw);
  } catch (err) {
    const corruptPath = await findAvailableCorruptPath();
    await fs.rename(draftPath, corruptPath);
    console.error(
      `Taslak dosyası bozuk: ${draftPath}\n` +
        `JSON ayrıştırılamadı (${err.message}).\n` +
        `Bozuk dosya şuraya taşındı: ${corruptPath}\n` +
        `Elle inceleyip gerekirse geri yükleyin; script bu durumda otomatik olarak sıfırdan üretmeyecek.`,
    );
    process.exit(1);
  }
}

async function findAvailableCorruptPath() {
  const dir = path.dirname(draftPath);
  const base = path.basename(draftPath, '.json');
  for (let n = 1; ; n += 1) {
    const candidate = path.join(dir, `${base}.corrupt-${n}.json`);
    try {
      await fs.access(candidate);
    } catch {
      return candidate;
    }
  }
}

async function writeDraft(value) {
  await fs.mkdir(path.dirname(draftPath), { recursive: true });
  const tmpPath = path.join(path.dirname(draftPath), `.${path.basename(draftPath)}.tmp-${process.pid}`);
  await fs.writeFile(tmpPath, `${JSON.stringify(value, null, 2)}\n`);
  await fs.rename(tmpPath, draftPath);
}

function collectAudioTargets(value) {
  const seen = new Map();
  for (const scene of Object.values(value.scenes)) {
    for (const word of scene.words) seen.set(word.audioId, word.lv);
    for (const sentence of scene.sentences) seen.set(sentence.audioId, sentence.lv);
  }
  return [...seen].map(([audioId, text]) => ({ audioId, text }));
}

async function synthesize(text) {
  const request = buildSpeechRequest({ apiKey, text, model: SPEECH_MODEL, voice: SPEECH_VOICE });
  const response = await fetch(request.url, { ...request.init, signal: AbortSignal.timeout(60_000) });
  if (!response.ok) {
    throw new Error(`OpenRouter ${response.status}: ${(await response.text()).slice(0, 200)}`);
  }
  const pcm = extractAudioFromStream(await response.text());
  assertUsableAudio(pcm, text);
  return wrapPcm16AsWav(pcm);
}

function buildPack(value, audioBaseUrl) {
  const scenes = SCENE_PLAN
    .filter(scene => value.scenes[scene.id])
    .map((scene, position) => {
      const entry = value.scenes[scene.id];
      const wordIdByLv = new Map(
        entry.words.map(word => [word.lv.toLowerCase(), `${scene.id}-w-${word.audioId}`]),
      );
      return {
        id: scene.id,
        index: position + 1,
        title: scene.title,
        words: entry.words.map(word => ({
          id: wordIdByLv.get(word.lv.toLowerCase()),
          lv: word.lv,
          tr: word.tr,
          icon: word.icon,
          audioId: word.audioId,
          lemma: word.lemma,
          freqRank: word.freqRank,
          caseForm: word.caseForm,
        })),
        sentences: entry.sentences.map(sentence => ({
          id: `${scene.id}-s-${sentence.audioId}`,
          lv: sentence.lv,
          tr: sentence.tr,
          audioId: sentence.audioId,
          wordIds: [...new Set(sentence.usesWords.map(lv => wordIdByLv.get(lv.toLowerCase())))].filter(Boolean),
          supports: sentence.supports,
        })).filter(sentence => sentence.wordIds.length > 0),
      };
    });

  return {
    version: PACK_VERSION,
    generatedAt: new Date().toISOString(),
    audioBaseUrl: audioBaseUrl.replace(/\/$/, ''),
    scenes,
  };
}

async function exists(filePath) {
  try {
    await fs.stat(filePath);
    return true;
  } catch {
    return false;
  }
}

async function writeFileAtomic(filePath, data) {
  const tmpPath = path.join(path.dirname(filePath), `.${path.basename(filePath)}.tmp-${process.pid}`);
  await fs.writeFile(tmpPath, data);
  await fs.rename(tmpPath, filePath);
}

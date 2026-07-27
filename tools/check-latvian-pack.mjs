import { PACK_VERSION, validatePack } from '../src/learning-lv/pack-schema.ts';
import { SCENE_PLAN } from '../src/learning-lv/scenes.ts';

let failures = 0;

function expect(condition, message) {
  if (condition) {
    console.log(`  ✓ ${message}`);
  } else {
    console.error(`  ✗ ${message}`);
    failures += 1;
  }
}

function rejects(build, fragment, message) {
  try {
    validatePack(build());
    expect(false, `${message} (hata bekleniyordu)`);
  } catch (error) {
    expect(String(error.message).includes(fragment), message);
  }
}

function validScene() {
  return {
    id: 'lv-s01',
    index: 1,
    title: 'Tanışma',
    words: [
      { id: 'w-labdien', lv: 'labdien', tr: 'iyi günler', audioId: 'a1', lemma: 'labdien', freqRank: 400 },
      { id: 'w-paldies', lv: 'paldies', tr: 'teşekkürler', audioId: 'a2', lemma: 'paldies', freqRank: 300 },
    ],
    sentences: [
      {
        id: 's-labdien',
        lv: 'Labdien, mani sauc Leyla.',
        tr: 'İyi günler, benim adım Leyla.',
        audioId: 'a3',
        wordIds: ['w-labdien'],
        supports: ['lv_to_tr', 'tr_to_lv', 'dictation'],
      },
    ],
  };
}

function validPack() {
  return {
    version: PACK_VERSION,
    generatedAt: '2026-07-27T00:00:00.000Z',
    audioBaseUrl: 'https://blob.example.com/lv',
    scenes: [validScene()],
  };
}

console.log('\n=== Letonca paket şeması ===');

expect(validatePack(validPack()).scenes.length === 1, 'geçerli paket kabul ediliyor');

rejects(() => ({ ...validPack(), version: 99 }), 'sürümü', 'yanlış sürüm reddediliyor');

rejects(() => ({ ...validPack(), audioBaseUrl: 'https://x/' }), 'eğik çizgi', 'sondaki eğik çizgi reddediliyor');

rejects(() => {
  const pack = validPack();
  pack.scenes[0].index = 5;
  return pack;
}, 'index', 'yanlış sahne sırası reddediliyor');

rejects(() => {
  const pack = validPack();
  pack.scenes[0].words[1].id = 'w-labdien';
  return pack;
}, 'yinelenen id', 'yinelenen id reddediliyor');

rejects(() => {
  const pack = validPack();
  pack.scenes[0].sentences[0].wordIds = ['w-yok'];
  return pack;
}, 'bilinmeyen kelimeye', 'tanımsız kelimeye bağlı cümle reddediliyor');

rejects(() => {
  const pack = validPack();
  pack.scenes[0].sentences[0].supports = ['ucan_daire'];
  return pack;
}, 'bilinmeyen soru tipi', 'bilinmeyen soru tipi reddediliyor');

rejects(() => {
  const pack = validPack();
  pack.scenes[0].words[0].caseForm = {
    base: 'kafija',
    form: 'ar kafiju',
    case: 'instrumental',
    suffix: 'u',
    distractorSuffixes: ['u', 'a'],
  };
  return pack;
}, 'çeldiricisi doğru ekle aynı', 'doğru ekle çakışan çeldirici reddediliyor');

console.log('\n=== Sahne planı ===');

expect(SCENE_PLAN.length === 12, '12 sahne var');
expect(
  SCENE_PLAN.every((scene, position) => scene.index === position + 1),
  'sahne sıraları kesintisiz ve artan',
);
expect(
  new Set(SCENE_PLAN.map(scene => scene.id)).size === SCENE_PLAN.length,
  'sahne id\'leri benzersiz',
);
expect(
  SCENE_PLAN.every(scene => scene.seedWords.length >= 5),
  'her sahnede en az beş çekirdek kelime var',
);
expect(
  SCENE_PLAN.every(scene => scene.brief.trim().endsWith('.')),
  'her sahne açıklaması tam cümle',
);

if (failures > 0) {
  console.error(`\n${failures} kontrol başarısız.`);
  process.exit(1);
}
console.log('\nTüm paket şeması kontrolleri geçti.\n');

import { filterByFrequency, parseFrequencyList } from '../src/learning-lv/frequency.ts';
import { buildSceneRequest, parseSceneResponse } from '../src/learning-lv/generate-prompts.ts';
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

console.log('\n=== Frekans süzgeci ===');

const ranks = parseFrequencyList('ir 900\nun 800\nkafija 700\nkafija 650\nretais 600\n');

expect(ranks.get('ir') === 0, 'ilk kelime sıfırıncı sırada');
expect(ranks.get('kafija') === 2, 'yinelenen kelime ilk sırasını koruyor');
expect(ranks.size === 4, 'yinelenen satır yeni sıra açmıyor');

const filtered = filterByFrequency(
  [
    { lv: 'kafija' },
    { lv: 'retais' },
    { lv: 'ar kafiju' },
    { lv: 'Turcija' },
    { lv: 'bilinmeyenkelime' },
  ],
  ranks,
  { maxRank: 2, allowList: ['Turcija'] },
);

expect(filtered.kept.some(entry => entry.lv === 'kafija' && entry.freqRank === 2), 'sık kelime kabul ediliyor');
expect(filtered.kept.some(entry => entry.lv === 'Turcija' && entry.freqRank === 0), 'izin listesi frekansı atlıyor');
expect(filtered.rejected.some(entry => entry.lv === 'retais'), 'nadir kelime eleniyor');
expect(
  filtered.rejected.some(entry => entry.lv === 'bilinmeyenkelime' && entry.reason.includes('listesinde yok')),
  'listede olmayan kelime gerekçesiyle eleniyor',
);
expect(
  filtered.rejected.some(entry => entry.lv === 'ar kafiju' && entry.reason.includes('listesinde yok')),
  'bileşeni listede olmayan kalıp eleniyor',
);

console.log('\n=== Üretim istemi ===');

const sceneRequest = buildSceneRequest(SCENE_PLAN[2], 'google/gemini-3.1-flash');
const userContent = sceneRequest.messages[1].content;

expect(sceneRequest.response_format.type === 'json_object', 'JSON yanıt biçimi isteniyor');
expect(userContent.includes('kafija'), 'çekirdek kelimeler isteme giriyor');
expect(userContent.includes('Markette'), 'sahne başlığı isteme giriyor');
expect(userContent.includes('case_drill'), 'soru tipleri isteme giriyor');

const draft = parseSceneResponse(`\`\`\`json
{
  "words": [
    {"lv":"kafija","tr":"kahve","lemma":"kafija","icon":"☕",
     "caseForm":{"base":"kafija","form":"ar kafiju","case":"instrumental","suffix":"u","distractorSuffixes":["a","as","u"]}},
    {"lv":"maize","tr":"ekmek","lemma":"maize"},
    {"lv":"","tr":"boş","lemma":""}
  ],
  "sentences": [
    {"lv":"Es gribu kafiju.","tr":"Kahve istiyorum.","usesWords":["kafija"],"supports":["tr_to_lv","order","ucan_daire"]},
    {"lv":"Yalnız kelime.","tr":"x","usesWords":["yok"],"supports":["order"]}
  ]
}
\`\`\``);

expect(draft.words.length === 2, 'boş kelime ayıklanıyor');
expect(draft.words[0].caseForm.distractorSuffixes.length === 2, 'doğru ekle çakışan çeldirici temizleniyor');
expect(draft.words[1].caseForm === undefined, 'çekim bilgisi yoksa alan boş kalıyor');
expect(draft.sentences.length === 1, 'tanımsız kelimeye bağlı cümle ayıklanıyor');
expect(!draft.sentences[0].supports.includes('ucan_daire'), 'bilinmeyen soru tipi ayıklanıyor');
expect(draft.sentences[0].supports.length === 2, 'geçerli soru tipleri korunuyor');

try {
  parseSceneResponse('düz metin');
  expect(false, 'JSON olmayan yanıt hata veriyor');
} catch (error) {
  expect(error.message.includes('JSON değil'), 'JSON olmayan yanıt hata veriyor');
}

if (failures > 0) {
  console.error(`\n${failures} kontrol başarısız.`);
  process.exit(1);
}
console.log('\nTüm paket şeması kontrolleri geçti.\n');

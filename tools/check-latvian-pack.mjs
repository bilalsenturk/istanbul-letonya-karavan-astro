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

const dedupedDraft = parseSceneResponse(`{
  "words": [
    {"lv":"upe","tr":"nehir","lemma":"upe",
     "caseForm":{"base":"upe","form":"upē","case":"lokatīvs","suffix":"ē","distractorSuffixes":["a","a","ē"]}},
    {"lv":"kalns","tr":"dağ","lemma":"kalns",
     "caseForm":{"base":"kalns","form":"kalnā","case":"lokatīvs","suffix":"ā","distractorSuffixes":["a","am","u"]}}
  ],
  "sentences": [
    {"lv":"Es eju uz upi.","tr":"Nehre gidiyorum.","usesWords":["upe","kalns"],"supports":["order"]}
  ]
}`);

expect(
  dedupedDraft.words[0].caseForm === undefined,
  'yinelenen çeldiriciler tekilleştirilince ikiden az kalırsa çekim bilgisi düşüyor',
);
expect(
  dedupedDraft.words[1].caseForm?.distractorSuffixes.length === 3,
  'birbirinden farklı üç çeldirici korunuyor',
);

const trailingProseDraft = parseSceneResponse(`\`\`\`json
{
  "words": [{"lv":"maize","tr":"ekmek","lemma":"maize"}],
  "sentences": [{"lv":"Es gribu maizi.","tr":"Ekmek istiyorum.","usesWords":["maize"],"supports":["order"]}]
}
\`\`\`
Let me know if you need any adjustments.`);

expect(trailingProseDraft.words.length === 1, 'kapanış çitinden sonraki metin ayıklanıp yanıt ayrıştırılıyor');

const plainJsonDraft = parseSceneResponse(
  '{"words":[{"lv":"maize","tr":"ekmek","lemma":"maize"}],"sentences":[{"lv":"Es gribu maizi.","tr":"Ekmek istiyorum.","usesWords":["maize"],"supports":["order"]}]}',
);

expect(plainJsonDraft.words.length === 1, 'çitsiz düz JSON yanıtı hâlâ ayrıştırılıyor');

console.log('\n=== Denetim geçişi ===');

const reviewDraft = {
  words: [
    { lv: 'kafija', tr: 'kahve', lemma: 'kafija' },
    { lv: 'yanlışkelime', tr: 'saçma', lemma: 'yanlışkelime' },
  ],
  sentences: [
    { lv: 'Es gribu kafiju.', tr: 'Kahve istiyorum.', usesWords: ['kafija'], supports: ['tr_to_lv'] },
    { lv: 'Bu cümle yanlışkelime içerir.', tr: 'x', usesWords: ['yanlışkelime'], supports: ['order'] },
  ],
};

const reviewRequest = buildReviewRequest(reviewDraft, SCENE_PLAN[2], 'google/gemini-3.1-flash');
expect(reviewRequest.temperature === 0, 'denetim sıcaklığı sıfır');
expect(reviewRequest.messages[1].content.includes('kafija'), 'maddeler denetim istemine giriyor');

const verdicts = parseReviewResponse(
  '{"verdicts":[{"lv":"kafija","ok":true},{"lv":"yanlışkelime","ok":false,"reason":"Letoncada böyle bir kelime yok"}]}',
);
expect(verdicts.length === 2, 'iki karar çözümleniyor');
expect(verdicts[1].ok === false, 'ret kararı okunuyor');

const reviewed = applyReview(reviewDraft, verdicts);
expect(reviewed.accepted.words.length === 1, 'reddedilen kelime düşüyor');
expect(reviewed.accepted.sentences.length === 1, 'öksüz kalan cümle düşüyor');
expect(
  reviewed.dropped.some(entry => entry.reason.includes('böyle bir kelime yok')),
  'ret gerekçesi korunuyor',
);
expect(reviewed.accepted.sentences[0].lv === 'Es gribu kafiju.', 'geçerli cümle kalıyor');

// Finding 1: ok alanı olmayan veya boolean olmayan girdiler onay sayılmamalı.
const malformedVerdicts = parseReviewResponse(
  '{"verdicts":[{"lv":"kafija"},{"lv":"yanlışkelime","ok":"false","reason":"x"}]}',
);
expect(malformedVerdicts.length === 0, 'ok alanı eksik veya boolean olmayan kararlar elenir');

const malformedApplied = applyReview(reviewDraft, malformedVerdicts);
expect(malformedApplied.accepted.words.length === 2, 'eksik kararlı kelime hâlâ pakette kalır');
expect(
  malformedApplied.unreviewed.includes('kafija') && malformedApplied.unreviewed.includes('yanlışkelime'),
  'kararı elenen maddeler unreviewed listesinde görünür',
);

// Finding 2: noktalama, boşluk ve büyük/küçük harf farkları eşleşmeyi kaçırmamalı.
const punctuationDraft = {
  words: [{ lv: 'kafija', tr: 'kahve', lemma: 'kafija' }],
  sentences: [],
};
const punctuationVerdicts = parseReviewResponse(
  '{"verdicts":[{"lv":"  Kafija.  ","ok":false,"reason":"yanlış"}]}',
);
const punctuationApplied = applyReview(punctuationDraft, punctuationVerdicts);
expect(punctuationApplied.accepted.words.length === 0, 'noktalama/boşluk/büyük-küçük harf farkı ret kararını kaçırmaz');

// Finding 3: hiç karar verilmeyen madde unreviewed listesinde görünür ve pakette kalır.
const unreviewedDraft = {
  words: [{ lv: 'maize', tr: 'ekmek', lemma: 'maize' }],
  sentences: [],
};
const unreviewedApplied = applyReview(unreviewedDraft, []);
expect(unreviewedApplied.accepted.words.length === 1, 'kararsız madde pakette kalır');
expect(unreviewedApplied.unreviewed.includes('maize'), 'kararsız madde unreviewed listesinde görünür');

// Cümlenin kendi lv değeri doğrudan reddedilirse kendi gerekçesiyle düşer.
const sentenceRejectDraft = {
  words: [{ lv: 'ūdens', tr: 'su', lemma: 'ūdens' }],
  sentences: [{ lv: 'Es gribu ūdeni.', tr: 'Su istiyorum.', usesWords: ['ūdens'], supports: ['tr_to_lv'] }],
};
const sentenceRejectVerdicts = parseReviewResponse(
  '{"verdicts":[{"lv":"ūdens","ok":true},{"lv":"Es gribu ūdeni.","ok":false,"reason":"cümle bozuk"}]}',
);
const sentenceRejectApplied = applyReview(sentenceRejectDraft, sentenceRejectVerdicts);
expect(sentenceRejectApplied.accepted.sentences.length === 0, 'doğrudan reddedilen cümle düşer');
expect(
  sentenceRejectApplied.dropped.some(entry => entry.lv === 'Es gribu ūdeni.' && entry.reason === 'cümle bozuk'),
  'doğrudan reddedilen cümle kendi gerekçesini taşır',
);

// Diyakritikler katlanmamalı: "lūdzu" reddi "ludzu" maddesini düşürmemeli.
const diacriticsDraft = {
  words: [{ lv: 'ludzu', tr: 'lütfen (diyakritiksiz)', lemma: 'ludzu' }],
  sentences: [],
};
const diacriticsVerdicts = parseReviewResponse('{"verdicts":[{"lv":"lūdzu","ok":false,"reason":"yanlış"}]}');
const diacriticsApplied = applyReview(diacriticsDraft, diacriticsVerdicts);
expect(diacriticsApplied.accepted.words.length === 1, 'diyakritikler katlanmaz, farklı kelimeler karışmaz');

if (failures > 0) {
  console.error(`\n${failures} kontrol başarısız.`);
  process.exit(1);
}
console.log('\nTüm paket şeması kontrolleri geçti.\n');

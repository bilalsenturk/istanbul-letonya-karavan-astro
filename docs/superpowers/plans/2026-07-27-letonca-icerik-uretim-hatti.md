# Letonca İçerik Üretim Hattı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 12 sahnelik Letonca içerik paketini (kelime, cümle, ses) OpenRouter ile üretip doğrulayan, sesleri Vercel Blob'a yükleyen, tek seferlik çalıştırılan bir üretim hattı kurmak.

**Architecture:** Saf TypeScript modülleri `src/learning-lv/` altında (şema, frekans süzgeci, istem kurucular, doğrulayıcılar — hepsi ağ erişimi olmadan test edilebilir), bunları birbirine bağlayan CLI betiği `tools/generate-latvian-pack.mjs`. Ağ çağrıları enjekte edilen `fetch` üzerinden yapılır, böylece testler sahte `fetch` ile çalışır. Betik kesintiye dayanıklıdır: her sahne ve her ses dosyası ayrı ayrı kaydedilir, yeniden çalıştırınca var olanı atlar.

**Tech Stack:** Node 22 (`--experimental-strip-types`), TypeScript, OpenRouter (`google/gemini-3.1-flash` üretim + denetim için, `openai/gpt-audio-mini` ses için), `@vercel/blob`.

## Global Constraints

- Node sürümü `>=22.12.0`. TypeScript dosyaları `node --experimental-strip-types` ile doğrudan çalıştırılır; derleme adımı yok.
- `src/learning-lv/` altındaki her modül saf olmalı: `fetch`, `fs`, `process.env` doğrudan kullanılamaz. Bunlar parametre olarak geçilir. Sebep: testler ağa çıkmadan çalışsın.
- Tüm test betikleri `tools/check-*.mjs` deseninde, `package.json`'a `check:*` betiği olarak eklenir ve başarısızlıkta `process.exit(1)` yapar. Mevcut `tools/check-learning-os.mjs` bu desenin örneğidir.
- Kullanıcıya görünen tüm metinler Türkçe. Kod içi tanımlayıcılar ve commit mesajları İngilizce.
- Letonca metinlerde diakritikler korunur: `ā ē ī ū č ģ ķ ļ ņ š ž`. Hiçbir yerde ASCII'ye düşürülmez.
- OpenRouter anahtarı yalnızca `OPENROUTER_API_KEY` ortam değişkeninden okunur, asla depoya yazılmaz.
- İçerik paketi şeması sürümlüdür (`version: 1`). Şema değişirse sürüm artar.
- Ses dosyaları mono MP3, dosya adı `<audioId>.mp3`, `audioId` metnin SHA-1'inin ilk 12 karakteri.

---

## File Structure

**Oluşturulacak:**

- `src/learning-lv/pack-schema.ts` — İçerik paketi tipleri ve `validatePack` doğrulayıcısı. iOS tarafının okuyacağı sözleşme burada tanımlanır.
- `src/learning-lv/scenes.ts` — 12 sahnenin planı: id, sıra, başlık, hedef kelime tohumları, kapsam açıklaması.
- `src/learning-lv/frequency.ts` — Frekans listesi yükleme ve `filterByFrequency` süzgeci.
- `src/learning-lv/generate-prompts.ts` — Üretim ve denetim istemlerini kuran saf fonksiyonlar + OpenRouter yanıtını çözümleme.
- `src/learning-lv/audio.ts` — `audioIdFor`, TTS istek kurucu, ses yanıtı doğrulayıcı.
- `tools/generate-latvian-pack.mjs` — CLI: üretim, denetim, ses, Blob yükleme, devam edebilirlik.
- `tools/check-latvian-pack.mjs` — Yukarıdaki saf modüllerin testi.
- `data/lv-frequency-top5000.txt` — İndirilmiş frekans listesi (depoya girer, ~60 KB).

**Silinecek:**

- `src/learning-os/` (tüm klasör), `src/pages/api/learning-os/` (tüm klasör), `tools/generate-latvian-learning-os.mjs`, `tools/check-learning-os.mjs`, `public/assets/learning-os/`, `ios/Karavan/Resources/learning-lv-tr-starter.json`. Bunlar Görev 9'da kaldırılır — daha önce değil, çünkü yeni hat çalışana kadar eski paket referans olarak durur.

---

### Task 1: İçerik paketi şeması ve doğrulayıcı

Bu, iOS tarafının okuyacağı sözleşme. Önce bu yazılır çünkü diğer her şey buna göre üretilir.

**Files:**
- Create: `src/learning-lv/pack-schema.ts`
- Create: `tools/check-latvian-pack.mjs`
- Modify: `package.json` (scripts bölümü)

**Interfaces:**
- Consumes: yok (ilk görev)
- Produces: `LatvianPack`, `LatvianScene`, `LatvianWord`, `LatvianSentence`, `LatvianCaseForm`, `ExerciseKind` tipleri; `validatePack(pack: unknown): LatvianPack` (geçersizse `Error` fırlatır); `PACK_VERSION = 1`; `EXERCISE_KINDS` sabiti.

- [ ] **Step 1: Şema dosyasını yaz**

`src/learning-lv/pack-schema.ts`:

```typescript
export const PACK_VERSION = 1;

export const EXERCISE_KINDS = [
  'listen_choose',
  'icon_choose',
  'lv_to_tr',
  'tr_to_lv',
  'match',
  'fill_blank',
  'case_drill',
  'dictation',
  'order',
  'speak',
] as const;

export type ExerciseKind = (typeof EXERCISE_KINDS)[number];

export type LatvianCase =
  | 'nominativ'
  | 'genitiv'
  | 'dativ'
  | 'akuzativ'
  | 'instrumental'
  | 'lokativ'
  | 'vokativ';

export interface LatvianCaseForm {
  /** Yalın hâl: "kafija" */
  base: string;
  /** Çekimli hâl bağlamıyla: "ar kafiju" */
  form: string;
  case: LatvianCase;
  /** Boşluk sorusunda beklenen ek: "u" */
  suffix: string;
  /** Çeldirici ekler, en az iki tane: ["a", "as"] */
  distractorSuffixes: string[];
}

export interface LatvianWord {
  id: string;
  lv: string;
  tr: string;
  /** Görselden-seç sorusu için emoji. Yoksa o soru tipi üretilmez. */
  icon?: string;
  audioId: string;
  lemma: string;
  /** Frekans listesindeki sırası. Düşük = daha sık. */
  freqRank: number;
  caseForm?: LatvianCaseForm;
}

export interface LatvianSentence {
  id: string;
  lv: string;
  tr: string;
  audioId: string;
  /** Bu cümlede geçen sahne kelimelerinin id'leri. En az bir tane. */
  wordIds: string[];
  /** Bu cümlenin destekleyebileceği soru tipleri. En az bir tane. */
  supports: ExerciseKind[];
}

export interface LatvianScene {
  id: string;
  /** 1'den başlar, paket içinde artan ve kesintisiz. */
  index: number;
  title: string;
  words: LatvianWord[];
  sentences: LatvianSentence[];
}

export interface LatvianPack {
  version: number;
  generatedAt: string;
  /** Ses dosyalarının indirileceği kök, sonunda eğik çizgi yok. */
  audioBaseUrl: string;
  scenes: LatvianScene[];
}

export function validatePack(input: unknown): LatvianPack {
  const pack = input as LatvianPack;
  if (!pack || typeof pack !== 'object') fail('paket bir nesne değil');
  if (pack.version !== PACK_VERSION) fail(`paket sürümü ${PACK_VERSION} olmalı`);
  if (typeof pack.generatedAt !== 'string' || !pack.generatedAt) fail('generatedAt eksik');
  if (typeof pack.audioBaseUrl !== 'string' || pack.audioBaseUrl.endsWith('/')) {
    fail('audioBaseUrl eksik veya sonunda eğik çizgi var');
  }
  if (!Array.isArray(pack.scenes) || pack.scenes.length === 0) fail('sahne yok');

  const seenIds = new Set<string>();
  const claim = (id: string, what: string): void => {
    if (!id) fail(`${what} id boş`);
    if (seenIds.has(id)) fail(`yinelenen id: ${id}`);
    seenIds.add(id);
  };

  pack.scenes.forEach((scene, position) => {
    claim(scene.id, 'sahne');
    if (scene.index !== position + 1) fail(`${scene.id} index ${position + 1} olmalı`);
    if (!scene.title) fail(`${scene.id} başlığı boş`);
    if (scene.words.length === 0) fail(`${scene.id} kelimesiz`);
    if (scene.sentences.length === 0) fail(`${scene.id} cümlesiz`);

    const wordIds = new Set<string>();
    for (const word of scene.words) {
      claim(word.id, 'kelime');
      wordIds.add(word.id);
      if (!word.lv || !word.tr) fail(`${word.id} lv/tr eksik`);
      if (!word.audioId) fail(`${word.id} audioId eksik`);
      if (!Number.isInteger(word.freqRank) || word.freqRank < 0) {
        fail(`${word.id} freqRank geçersiz`);
      }
      if (word.caseForm) validateCaseForm(word.id, word.caseForm);
    }

    for (const sentence of scene.sentences) {
      claim(sentence.id, 'cümle');
      if (!sentence.lv || !sentence.tr) fail(`${sentence.id} lv/tr eksik`);
      if (!sentence.audioId) fail(`${sentence.id} audioId eksik`);
      if (sentence.wordIds.length === 0) fail(`${sentence.id} hiçbir kelimeye bağlı değil`);
      for (const wordId of sentence.wordIds) {
        if (!wordIds.has(wordId)) fail(`${sentence.id} bilinmeyen kelimeye bağlı: ${wordId}`);
      }
      if (sentence.supports.length === 0) fail(`${sentence.id} hiçbir soru tipini desteklemiyor`);
      for (const kind of sentence.supports) {
        if (!EXERCISE_KINDS.includes(kind)) fail(`${sentence.id} bilinmeyen soru tipi: ${kind}`);
      }
    }
  });

  return pack;
}

function validateCaseForm(wordId: string, caseForm: LatvianCaseForm): void {
  if (!caseForm.base || !caseForm.form) fail(`${wordId} caseForm base/form eksik`);
  if (!caseForm.suffix) fail(`${wordId} caseForm suffix boş`);
  if (caseForm.distractorSuffixes.length < 2) {
    fail(`${wordId} caseForm en az iki çeldirici ek istiyor`);
  }
  if (caseForm.distractorSuffixes.includes(caseForm.suffix)) {
    fail(`${wordId} caseForm çeldiricisi doğru ekle aynı`);
  }
}

function fail(message: string): never {
  throw new Error(`Geçersiz Letonca paketi: ${message}`);
}
```

- [ ] **Step 2: Testi yaz**

`tools/check-latvian-pack.mjs`:

```javascript
import { PACK_VERSION, validatePack } from '../src/learning-lv/pack-schema.ts';

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

if (failures > 0) {
  console.error(`\n${failures} kontrol başarısız.`);
  process.exit(1);
}
console.log('\nTüm paket şeması kontrolleri geçti.\n');
```

- [ ] **Step 3: `package.json`'a betiği ekle**

`scripts` bölümüne, `check:learning-os` satırının hemen altına:

```json
    "check:latvian-pack": "node --experimental-strip-types tools/check-latvian-pack.mjs",
```

- [ ] **Step 4: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: her satırda `✓`, sonda `Tüm paket şeması kontrolleri geçti.`, çıkış kodu 0.

- [ ] **Step 5: Commit**

```bash
git add src/learning-lv/pack-schema.ts tools/check-latvian-pack.mjs package.json
git commit -m "feat: add Latvian content pack schema and validator"
```

---

### Task 2: Sahne planı

**Files:**
- Create: `src/learning-lv/scenes.ts`
- Modify: `tools/check-latvian-pack.mjs`

**Interfaces:**
- Consumes: yok
- Produces: `SCENE_PLAN: readonly ScenePlan[]` ve `interface ScenePlan { id: string; index: number; title: string; brief: string; seedWords: string[] }`. `brief` üretim istemine gider, `seedWords` üretilen kelime listesinin çekirdeğidir.

- [ ] **Step 1: Sahne planını yaz**

`src/learning-lv/scenes.ts`:

```typescript
export interface ScenePlan {
  id: string;
  index: number;
  title: string;
  /** Üretim istemine giren, sahnenin ne kapsadığını anlatan tek cümle. */
  brief: string;
  /** Sahnede kesinlikle bulunması gereken kelimeler. */
  seedWords: string[];
}

export const SCENE_PLAN: readonly ScenePlan[] = [
  {
    id: 'lv-s01-tanisma',
    index: 1,
    title: 'Tanışma',
    brief: 'Selamlaşma, kendini tanıtma, evet/hayır, teşekkür ve rica.',
    seedWords: ['sveiki', 'labdien', 'paldies', 'lūdzu', 'jā', 'nē', 'es', 'mani sauc'],
  },
  {
    id: 'lv-s02-sayilar',
    index: 2,
    title: 'Sayılar ve fiyat',
    brief: '0-100 arası sayılar, fiyat sorma, pahalı/ucuz, para birimi.',
    seedWords: ['viens', 'divi', 'trīs', 'desmit', 'simts', 'cik maksā', 'eiro', 'dārgi', 'lēti'],
  },
  {
    id: 'lv-s03-markette',
    index: 3,
    title: 'Markette',
    brief: 'Temel gıda alışverişi, istemek ve ihtiyaç belirtmek.',
    seedWords: ['maize', 'ūdens', 'piens', 'kafija', 'gribu', 'man vajag', 'veikals'],
  },
  {
    id: 'lv-s04-benzinlik',
    index: 4,
    title: 'Benzinlik ve yol',
    brief: 'Yakıt almak, yön sormak ve yön tarifini anlamak.',
    seedWords: ['degviela', 'pilnu bāku', 'kur ir', 'pa kreisi', 'pa labi', 'taisni', 'ceļš'],
  },
  {
    id: 'lv-s05-kamp',
    index: 5,
    title: 'Kamp alanı',
    brief: 'Konaklama yeri bulmak, süre ve müsaitlik sormak.',
    seedWords: ['telts', 'vieta', 'nakts', 'cik ilgi', 'vai ir brīvs', 'kempings'],
  },
  {
    id: 'lv-s06-yemek',
    index: 6,
    title: 'Yemek',
    brief: 'Restoranda sipariş, beğeni belirtme, hesap isteme, kısıtlar.',
    seedWords: ['ēst', 'dzert', 'garšīgs', 'rēķinu lūdzu', 'bez gaļas', 'zupa'],
  },
  {
    id: 'lv-s07-zaman',
    index: 7,
    title: 'Zaman',
    brief: 'Gün, saat, zaman aralığı ve randevu ifadeleri.',
    seedWords: ['šodien', 'rīt', 'vakar', 'pulksten', 'cikos', 'no', 'līdz'],
  },
  {
    id: 'lv-s08-hava',
    index: 8,
    title: 'Hava ve yol durumu',
    brief: 'Hava olayları, sıcaklık ve yol koşulları.',
    seedWords: ['lietus', 'sniegs', 'auksts', 'silts', 'slidens', 'vējš'],
  },
  {
    id: 'lv-s09-sinir',
    index: 9,
    title: 'Sınır ve belgeler',
    brief: 'Sınır geçişi, kimlik ve araç belgeleri, nereden geldiğini söyleme.',
    seedWords: ['pase', 'dokumenti', 'mašīna', 'no Turcijas', 'robeža'],
  },
  {
    id: 'lv-s10-yardim',
    index: 10,
    title: 'Yardım ve acil',
    brief: 'Yardım istemek, sağlık sorunu anlatmak, acil kurumlar.',
    seedWords: ['palīdziet', 'ārsts', 'slimnīca', 'man sāp', 'policija', 'aptieka'],
  },
  {
    id: 'lv-s11-sohbet',
    index: 11,
    title: 'Sohbet',
    brief: 'Hâl hatır sormak, nereli olduğunu söylemek, beğeni belirtmek.',
    seedWords: ['kā tev iet', 'no kurienes', 'patīk', 'ļoti', 'labi'],
  },
  {
    id: 'lv-s12-veda',
    index: 12,
    title: 'Kibarlık ve veda',
    brief: 'Özür dileme, vedalaşma ve kibar kapanış ifadeleri.',
    seedWords: ['atvainojiet', 'uz redzēšanos', 'ar prieku', 'nekas', 'čau'],
  },
];
```

- [ ] **Step 2: Testi ekle**

`tools/check-latvian-pack.mjs` dosyasının en üstündeki import satırının altına ekle:

```javascript
import { SCENE_PLAN } from '../src/learning-lv/scenes.ts';
```

Ve `if (failures > 0)` bloğunun hemen üstüne ekle:

```javascript
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
```

- [ ] **Step 3: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: `=== Sahne planı ===` başlığı altında beş `✓`, çıkış kodu 0.

- [ ] **Step 4: Commit**

```bash
git add src/learning-lv/scenes.ts tools/check-latvian-pack.mjs
git commit -m "feat: add 12-scene Latvian curriculum plan"
```

---

### Task 3: Frekans süzgeci

**Files:**
- Create: `src/learning-lv/frequency.ts`
- Create: `data/lv-frequency-top5000.txt`
- Modify: `tools/check-latvian-pack.mjs`

**Interfaces:**
- Consumes: yok
- Produces: `parseFrequencyList(raw: string): Map<string, number>` (kelime → sıra, 0 tabanlı); `filterByFrequency<T extends { lv: string }>(candidates: T[], ranks: Map<string, number>, options: { maxRank: number; allowList: string[] }): { kept: Array<T & { freqRank: number }>; rejected: Array<{ lv: string; reason: string }> }`.

- [ ] **Step 1: Frekans listesini indir**

```bash
mkdir -p data && curl -sL "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/lv/lv_50k.txt" | head -5000 > data/lv-frequency-top5000.txt && wc -l data/lv-frequency-top5000.txt
```

Beklenen: `5000 data/lv-frequency-top5000.txt`. Dosya formatı her satırda `kelime sayı` (boşlukla ayrılmış). Kaynak MIT lisanslı.

- [ ] **Step 2: Süzgeci yaz**

`src/learning-lv/frequency.ts`:

```typescript
export function parseFrequencyList(raw: string): Map<string, number> {
  const ranks = new Map<string, number>();
  let rank = 0;
  for (const line of raw.split('\n')) {
    const word = line.trim().split(/\s+/)[0];
    if (!word) continue;
    if (!ranks.has(word)) {
      ranks.set(word, rank);
      rank += 1;
    }
  }
  return ranks;
}

export interface FrequencyFilterOptions {
  /** Bu sıradan sonra gelen kelimeler elenir. */
  maxRank: number;
  /** Frekans listesinde olmasa bile kabul edilecek kelimeler (özel adlar, çok kelimeli kalıplar). */
  allowList: string[];
}

export interface FrequencyFilterResult<T> {
  kept: Array<T & { freqRank: number }>;
  rejected: Array<{ lv: string; reason: string }>;
}

export function filterByFrequency<T extends { lv: string }>(
  candidates: readonly T[],
  ranks: Map<string, number>,
  options: FrequencyFilterOptions,
): FrequencyFilterResult<T> {
  const allowed = new Set(options.allowList.map(entry => entry.toLowerCase()));
  const kept: Array<T & { freqRank: number }> = [];
  const rejected: Array<{ lv: string; reason: string }> = [];

  for (const candidate of candidates) {
    const normalized = candidate.lv.trim().toLowerCase();
    if (allowed.has(normalized)) {
      kept.push({ ...candidate, freqRank: 0 });
      continue;
    }
    // Çok kelimeli kalıpların sırası, en nadir bileşenine göre belirlenir.
    const tokens = normalized.split(/\s+/).filter(Boolean);
    const tokenRanks = tokens.map(token => ranks.get(token));
    if (tokenRanks.some(entry => entry === undefined)) {
      const missing = tokens.filter(token => !ranks.has(token));
      rejected.push({ lv: candidate.lv, reason: `frekans listesinde yok: ${missing.join(', ')}` });
      continue;
    }
    const freqRank = Math.max(...(tokenRanks as number[]));
    if (freqRank > options.maxRank) {
      rejected.push({ lv: candidate.lv, reason: `çok nadir (sıra ${freqRank})` });
      continue;
    }
    kept.push({ ...candidate, freqRank });
  }

  return { kept, rejected };
}
```

- [ ] **Step 3: Testi ekle**

`tools/check-latvian-pack.mjs` import bloğuna ekle:

```javascript
import { filterByFrequency, parseFrequencyList } from '../src/learning-lv/frequency.ts';
```

`if (failures > 0)` bloğunun üstüne ekle:

```javascript
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
```

- [ ] **Step 4: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: `=== Frekans süzgeci ===` altında sekiz `✓`, çıkış kodu 0.

- [ ] **Step 5: Commit**

```bash
git add src/learning-lv/frequency.ts data/lv-frequency-top5000.txt tools/check-latvian-pack.mjs
git commit -m "feat: add Latvian frequency filter with MIT frequency list"
```

---

### Task 4: Üretim istemleri ve yanıt çözümleme

**Files:**
- Create: `src/learning-lv/generate-prompts.ts`
- Modify: `tools/check-latvian-pack.mjs`

**Interfaces:**
- Consumes: `ScenePlan` (Görev 2), `ExerciseKind` (Görev 1)
- Produces: `buildSceneRequest(scene: ScenePlan, model: string): OpenRouterChatRequest`; `parseSceneResponse(raw: string): SceneDraft`; `interface SceneDraft { words: DraftWord[]; sentences: DraftSentence[] }`; `interface OpenRouterChatRequest { model: string; messages: Array<{ role: string; content: string }>; response_format: unknown; temperature: number }`.

- [ ] **Step 1: İstem kurucuyu yaz**

`src/learning-lv/generate-prompts.ts`:

```typescript
import { EXERCISE_KINDS, type ExerciseKind, type LatvianCase } from './pack-schema.ts';
import type { ScenePlan } from './scenes.ts';

export interface DraftWord {
  lv: string;
  tr: string;
  lemma: string;
  icon?: string;
  caseForm?: {
    base: string;
    form: string;
    case: LatvianCase;
    suffix: string;
    distractorSuffixes: string[];
  };
}

export interface DraftSentence {
  lv: string;
  tr: string;
  usesWords: string[];
  supports: ExerciseKind[];
}

export interface SceneDraft {
  words: DraftWord[];
  sentences: DraftSentence[];
}

export interface OpenRouterChatRequest {
  model: string;
  messages: Array<{ role: 'system' | 'user'; content: string }>;
  response_format: { type: 'json_object' };
  temperature: number;
}

const SYSTEM_PROMPT = [
  'Sen Letonca öğreten bir müfredat tasarımcısısın.',
  'Türkçe konuşan, Letonya\'ya karavanla seyahat eden bir yetişkin için A1 seviyesinde içerik üretiyorsun.',
  'Yalnızca gerçek, günlük hayatta kullanılan Letonca üret. Kitabi veya arkaik ifade kullanma.',
  'Letonca diakritikleri (ā ē ī ū č ģ ķ ļ ņ š ž) her zaman doğru yaz.',
  'Türkçe karşılıklar doğal Türkçe olsun, birebir çeviri değil.',
  'Yanıtını yalnızca JSON olarak ver, açıklama ekleme.',
].join(' ');

export function buildSceneRequest(scene: ScenePlan, model: string): OpenRouterChatRequest {
  const userPrompt = [
    `Sahne: ${scene.title}`,
    `Kapsam: ${scene.brief}`,
    `Bu kelimeler mutlaka bulunsun: ${scene.seedWords.join(', ')}`,
    '',
    'Şu JSON yapısını üret:',
    '{',
    '  "words": [{"lv":"","tr":"","lemma":"","icon":"","caseForm":null}],',
    '  "sentences": [{"lv":"","tr":"","usesWords":[""],"supports":[""]}]',
    '}',
    '',
    'Kurallar:',
    '- 25 kelime üret. Her birinin lemma alanı yalın hâli olsun.',
    '- icon alanı yalnızca somut nesneler için tek emoji; soyut kelimelerde boş bırak.',
    '- caseForm alanını yalnızca çekimin öğretici olduğu kelimelerde doldur.',
    '  Doldurursan: base yalın hâl, form bağlamıyla çekimli hâl, suffix beklenen ek,',
    '  distractorSuffixes en az iki yanlış ek, case alanı hâlin adı.',
    '- 20 cümle üret. Her cümle en fazla 7 kelime olsun.',
    '- usesWords, cümlede geçen kelimelerin lv değerleri olsun.',
    `- supports şu değerlerden seçilsin: ${EXERCISE_KINDS.join(', ')}.`,
    '- Bir cümleyi yalnızca gerçekten uygunsa bir soru tipine ata.',
    '  order ve tr_to_lv için cümle en az üç kelime olmalı.',
    '  fill_blank için cümlede çıkarılabilecek anlamlı bir kelime olmalı.',
    '  case_drill yalnızca caseForm tanımlı bir kelime içeren cümlelere verilsin.',
  ].join('\n');

  return {
    model,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    response_format: { type: 'json_object' },
    temperature: 0.4,
  };
}

export function parseSceneResponse(raw: string): SceneDraft {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stripCodeFence(raw));
  } catch {
    throw new Error('Model yanıtı JSON değil');
  }
  const draft = parsed as SceneDraft;
  if (!Array.isArray(draft.words) || draft.words.length === 0) {
    throw new Error('Model yanıtında kelime yok');
  }
  if (!Array.isArray(draft.sentences) || draft.sentences.length === 0) {
    throw new Error('Model yanıtında cümle yok');
  }

  const words = draft.words
    .filter(word => typeof word?.lv === 'string' && word.lv.trim() && typeof word.tr === 'string' && word.tr.trim())
    .map(word => ({
      lv: word.lv.trim(),
      tr: word.tr.trim(),
      lemma: (word.lemma ?? word.lv).trim(),
      icon: word.icon?.trim() || undefined,
      caseForm: normalizeCaseForm(word.caseForm),
    }));

  const known = new Set(words.map(word => word.lv.toLowerCase()));
  const sentences = draft.sentences
    .filter(sentence => typeof sentence?.lv === 'string' && sentence.lv.trim())
    .filter(sentence => typeof sentence.tr === 'string' && sentence.tr.trim())
    .map(sentence => ({
      lv: sentence.lv.trim(),
      tr: sentence.tr.trim(),
      usesWords: (sentence.usesWords ?? [])
        .map(entry => String(entry).trim())
        .filter(entry => known.has(entry.toLowerCase())),
      supports: (sentence.supports ?? []).filter((kind): kind is ExerciseKind =>
        EXERCISE_KINDS.includes(kind as ExerciseKind),
      ),
    }))
    .filter(sentence => sentence.usesWords.length > 0 && sentence.supports.length > 0);

  if (words.length === 0) throw new Error('Kullanılabilir kelime kalmadı');
  if (sentences.length === 0) throw new Error('Kullanılabilir cümle kalmadı');

  return { words, sentences };
}

function normalizeCaseForm(input: DraftWord['caseForm']): DraftWord['caseForm'] {
  if (!input || !input.base || !input.form || !input.suffix) return undefined;
  const distractors = (input.distractorSuffixes ?? [])
    .map(entry => String(entry).trim())
    .filter(entry => entry && entry !== input.suffix);
  if (distractors.length < 2) return undefined;
  return { ...input, distractorSuffixes: [...new Set(distractors)].slice(0, 3) };
}

function stripCodeFence(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  return trimmed.replace(/^```[a-z]*\n?/i, '').replace(/```$/, '').trim();
}
```

- [ ] **Step 2: Testi ekle**

`tools/check-latvian-pack.mjs` import bloğuna ekle:

```javascript
import { buildSceneRequest, parseSceneResponse } from '../src/learning-lv/generate-prompts.ts';
```

`if (failures > 0)` bloğunun üstüne ekle:

```javascript
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
```

- [ ] **Step 3: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: `=== Üretim istemi ===` altında on `✓`, çıkış kodu 0.

- [ ] **Step 4: Commit**

```bash
git add src/learning-lv/generate-prompts.ts tools/check-latvian-pack.mjs
git commit -m "feat: add Latvian scene generation prompt and response parser"
```

---

### Task 5: Denetim geçişi

Üretilen içeriği ikinci bir modele doğrulatan katman. Bu, tasarımın "hata pahalı" gerekçesinin uygulaması.

**Files:**
- Modify: `src/learning-lv/generate-prompts.ts`
- Modify: `tools/check-latvian-pack.mjs`

**Interfaces:**
- Consumes: `SceneDraft`, `DraftWord`, `DraftSentence` (Görev 4)
- Produces: `buildReviewRequest(draft: SceneDraft, scene: ScenePlan, model: string): OpenRouterChatRequest`; `applyReview(draft: SceneDraft, verdicts: ReviewVerdict[]): { accepted: SceneDraft; dropped: Array<{ lv: string; reason: string }> }`; `parseReviewResponse(raw: string): ReviewVerdict[]`; `interface ReviewVerdict { lv: string; ok: boolean; reason?: string }`.

- [ ] **Step 1: Denetim katmanını ekle**

`src/learning-lv/generate-prompts.ts` dosyasının sonuna ekle:

```typescript
export interface ReviewVerdict {
  lv: string;
  ok: boolean;
  reason?: string;
}

const REVIEW_SYSTEM_PROMPT = [
  'Sen Letonca anadili düzeyinde bir dil denetçisisin.',
  'Sana verilen Letonca madde listesini tek tek denetleyeceksin.',
  'Bir maddeyi yalnızca şu durumlarda reddet: Letoncası hatalı, Türkçe karşılığı yanlış,',
  'hâl çekimi hatalı, ya da madde sahnenin kapsamıyla ilgisiz.',
  'Doğru maddeleri reddetme. Yanıtını yalnızca JSON olarak ver.',
].join(' ');

export function buildReviewRequest(
  draft: SceneDraft,
  scene: ScenePlan,
  model: string,
): OpenRouterChatRequest {
  const items = [
    ...draft.words.map(word => ({
      lv: word.lv,
      tr: word.tr,
      cekim: word.caseForm ? `${word.caseForm.form} (${word.caseForm.case})` : null,
    })),
    ...draft.sentences.map(sentence => ({ lv: sentence.lv, tr: sentence.tr, cekim: null })),
  ];

  const userPrompt = [
    `Sahne: ${scene.title}`,
    `Kapsam: ${scene.brief}`,
    '',
    'Denetlenecek maddeler:',
    JSON.stringify(items, null, 2),
    '',
    'Şu JSON yapısını üret:',
    '{"verdicts":[{"lv":"","ok":true,"reason":""}]}',
    '',
    'Her madde için tam bir karar ver. lv alanı sana verilenle birebir aynı olsun.',
    'ok false ise reason alanına tek cümlelik Türkçe gerekçe yaz.',
  ].join('\n');

  return {
    model,
    messages: [
      { role: 'system', content: REVIEW_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    response_format: { type: 'json_object' },
    temperature: 0,
  };
}

export function parseReviewResponse(raw: string): ReviewVerdict[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stripCodeFence(raw));
  } catch {
    throw new Error('Denetim yanıtı JSON değil');
  }
  const verdicts = (parsed as { verdicts?: unknown }).verdicts;
  if (!Array.isArray(verdicts)) throw new Error('Denetim yanıtında verdicts dizisi yok');
  return verdicts
    .filter(entry => typeof (entry as ReviewVerdict)?.lv === 'string')
    .map(entry => {
      const verdict = entry as ReviewVerdict;
      return {
        lv: verdict.lv.trim(),
        ok: verdict.ok !== false,
        reason: verdict.reason?.trim() || undefined,
      };
    });
}

export function applyReview(
  draft: SceneDraft,
  verdicts: readonly ReviewVerdict[],
): { accepted: SceneDraft; dropped: Array<{ lv: string; reason: string }> } {
  const rejectedBy = new Map<string, string>();
  for (const verdict of verdicts) {
    if (!verdict.ok) rejectedBy.set(verdict.lv.toLowerCase(), verdict.reason ?? 'denetim reddetti');
  }

  const dropped: Array<{ lv: string; reason: string }> = [];
  const keepWord = (lv: string): boolean => {
    const reason = rejectedBy.get(lv.toLowerCase());
    if (reason) {
      dropped.push({ lv, reason });
      return false;
    }
    return true;
  };

  const words = draft.words.filter(word => keepWord(word.lv));
  const survivingWords = new Set(words.map(word => word.lv.toLowerCase()));

  // Elenen bir kelimeye bağlı cümle de düşer: o kelime artık pakette yok.
  const sentences = draft.sentences.filter(sentence => {
    if (!keepWord(sentence.lv)) return false;
    const orphaned = sentence.usesWords.filter(lv => !survivingWords.has(lv.toLowerCase()));
    if (orphaned.length === sentence.usesWords.length) {
      dropped.push({ lv: sentence.lv, reason: `bağlı olduğu kelimeler elendi: ${orphaned.join(', ')}` });
      return false;
    }
    return true;
  }).map(sentence => ({
    ...sentence,
    usesWords: sentence.usesWords.filter(lv => survivingWords.has(lv.toLowerCase())),
  }));

  return { accepted: { words, sentences }, dropped };
}
```

- [ ] **Step 2: Testi ekle**

`tools/check-latvian-pack.mjs` import satırını güncelle (Görev 4'te eklenen satırın yerine):

```javascript
import {
  applyReview,
  buildReviewRequest,
  buildSceneRequest,
  parseReviewResponse,
  parseSceneResponse,
} from '../src/learning-lv/generate-prompts.ts';
```

`if (failures > 0)` bloğunun üstüne ekle:

```javascript
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
```

- [ ] **Step 3: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: `=== Denetim geçişi ===` altında yedi `✓`, çıkış kodu 0.

- [ ] **Step 4: Commit**

```bash
git add src/learning-lv/generate-prompts.ts tools/check-latvian-pack.mjs
git commit -m "feat: add second-pass content review for Latvian generation"
```

---

### Task 6: Ses üretimi ve doğrulama

Mevcut `openrouter-tts.ts`'in en büyük eksiği burada kapanıyor: gelen sesin gerçekten ses olduğunu doğrulamak.

**Files:**
- Create: `src/learning-lv/audio.ts`
- Modify: `tools/check-latvian-pack.mjs`

**Interfaces:**
- Consumes: yok
- Produces: `audioIdFor(text: string): string`; `buildSpeechRequest(input: SpeechInput): { url: string; init: RequestInit }`; `extractAudioFromStream(body: string): Uint8Array`; `assertUsableAudio(pcm: Uint8Array, text: string): void`; `interface SpeechInput { apiKey: string; text: string; model: string; voice: string }`.

Ses akışı `openai/gpt-audio-mini`'den chat-completions üzerinden PCM16 olarak gelir. `assertUsableAudio` iki şeyi kontrol eder: yeterli uzunluk (metin başına en az 40 ms) ve gerçek sinyal (tamamen sessiz değil). Bu ikisi, modelin konuşmak yerine metin döndürdüğü hata durumunu yakalar.

- [ ] **Step 1: Ses modülünü yaz**

`src/learning-lv/audio.ts`:

```typescript
import { createHash } from 'node:crypto';

export const SPEECH_URL = 'https://openrouter.ai/api/v1/chat/completions';
export const SPEECH_SAMPLE_RATE = 24_000;

export interface SpeechInput {
  apiKey: string;
  text: string;
  model: string;
  voice: string;
}

export function audioIdFor(text: string): string {
  return createHash('sha1').update(text.normalize('NFC'), 'utf8').digest('hex').slice(0, 12);
}

export function buildSpeechRequest(input: SpeechInput): { url: string; init: RequestInit } {
  return {
    url: SPEECH_URL,
    init: {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${input.apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://istanbul-letonya-karavan-astro.vercel.app',
        'X-Title': 'Kuzey Letonca',
      },
      body: JSON.stringify({
        model: input.model,
        modalities: ['text', 'audio'],
        audio: { voice: input.voice, format: 'pcm16' },
        messages: [
          {
            role: 'system',
            content: [
              'You read Latvian text aloud for a language course.',
              'Speak the user text exactly once, in Latvian, at a calm classroom pace.',
              'Never add words, translations, explanations, or punctuation names.',
            ].join(' '),
          },
          { role: 'user', content: input.text },
        ],
        stream: true,
      }),
    },
  };
}

export function extractAudioFromStream(body: string): Uint8Array {
  const chunks: Uint8Array[] = [];
  for (const line of body.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) continue;
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === '[DONE]') continue;
    let parsed: { choices?: Array<{ delta?: { audio?: { data?: string } } }> };
    try {
      parsed = JSON.parse(payload);
    } catch {
      continue;
    }
    const data = parsed.choices?.[0]?.delta?.audio?.data;
    if (data) chunks.push(Buffer.from(data, 'base64'));
  }
  const total = chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0);
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

/** Modelin konuşmak yerine metin döndürdüğü durumu yakalar. */
export function assertUsableAudio(pcm: Uint8Array, text: string): void {
  const durationMs = (pcm.byteLength / 2 / SPEECH_SAMPLE_RATE) * 1000;
  const minimumMs = Math.max(250, text.length * 40);
  if (durationMs < minimumMs) {
    throw new Error(
      `"${text}" için ses çok kısa: ${Math.round(durationMs)} ms, en az ${minimumMs} ms bekleniyordu`,
    );
  }

  const samples = new Int16Array(pcm.buffer, pcm.byteOffset, Math.floor(pcm.byteLength / 2));
  let peak = 0;
  for (let index = 0; index < samples.length; index += 1) {
    const magnitude = Math.abs(samples[index]);
    if (magnitude > peak) peak = magnitude;
  }
  if (peak < 500) {
    throw new Error(`"${text}" için ses sessiz (tepe değeri ${peak})`);
  }
}

export function wrapPcm16AsWav(pcm: Uint8Array, sampleRate = SPEECH_SAMPLE_RATE): Buffer {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0, 'ascii');
  header.writeUInt32LE(36 + pcm.byteLength, 4);
  header.write('WAVE', 8, 'ascii');
  header.write('fmt ', 12, 'ascii');
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36, 'ascii');
  header.writeUInt32LE(pcm.byteLength, 40);
  return Buffer.concat([header, Buffer.from(pcm)]);
}
```

- [ ] **Step 2: Testi ekle**

`tools/check-latvian-pack.mjs` import bloğuna ekle:

```javascript
import {
  assertUsableAudio,
  audioIdFor,
  buildSpeechRequest,
  extractAudioFromStream,
  SPEECH_SAMPLE_RATE,
  wrapPcm16AsWav,
} from '../src/learning-lv/audio.ts';
```

`if (failures > 0)` bloğunun üstüne ekle:

```javascript
console.log('\n=== Ses üretimi ===');

expect(audioIdFor('paldies').length === 12, 'ses id 12 karakter');
expect(audioIdFor('paldies') === audioIdFor('paldies'), 'aynı metin aynı id');
expect(audioIdFor('paldies') !== audioIdFor('lūdzu'), 'farklı metin farklı id');

const speechRequest = buildSpeechRequest({
  apiKey: 'test-key',
  text: 'Labdien',
  model: 'openai/gpt-audio-mini',
  voice: 'nova',
});
const speechBody = JSON.parse(speechRequest.init.body);
expect(speechBody.modalities.includes('audio'), 'ses modalitesi isteniyor');
expect(speechBody.audio.format === 'pcm16', 'pcm16 biçimi isteniyor');
expect(speechBody.messages[1].content === 'Labdien', 'metin doğrudan geçiyor');

function fakeStream(samples) {
  const buffer = Buffer.alloc(samples.length * 2);
  samples.forEach((value, index) => buffer.writeInt16LE(value, index * 2));
  const half = Math.floor(buffer.length / 2);
  const first = buffer.subarray(0, half).toString('base64');
  const second = buffer.subarray(half).toString('base64');
  return [
    `data: ${JSON.stringify({ choices: [{ delta: { audio: { data: first } } }] })}`,
    'data: bozuk-json',
    `data: ${JSON.stringify({ choices: [{ delta: { audio: { data: second } } }] })}`,
    'data: [DONE]',
    '',
  ].join('\n');
}

const loudSamples = Array.from({ length: SPEECH_SAMPLE_RATE }, (unused, index) =>
  Math.round(8000 * Math.sin(index / 12)),
);
const loudPcm = extractAudioFromStream(fakeStream(loudSamples));
expect(loudPcm.byteLength === loudSamples.length * 2, 'akıştan tüm ses parçaları birleşiyor');

try {
  assertUsableAudio(loudPcm, 'Labdien');
  expect(true, 'gerçek ses kabul ediliyor');
} catch (error) {
  expect(false, `gerçek ses kabul ediliyor (${error.message})`);
}

try {
  assertUsableAudio(extractAudioFromStream(fakeStream(new Array(400).fill(6000))), 'Labdien');
  expect(false, 'çok kısa ses reddediliyor');
} catch (error) {
  expect(error.message.includes('çok kısa'), 'çok kısa ses reddediliyor');
}

try {
  assertUsableAudio(extractAudioFromStream(fakeStream(new Array(SPEECH_SAMPLE_RATE).fill(3))), 'Labdien');
  expect(false, 'sessiz ses reddediliyor');
} catch (error) {
  expect(error.message.includes('sessiz'), 'sessiz ses reddediliyor');
}

const wav = wrapPcm16AsWav(loudPcm);
expect(wav.subarray(0, 4).toString('ascii') === 'RIFF', 'WAV başlığı yazılıyor');
expect(wav.readUInt32LE(40) === loudPcm.byteLength, 'WAV veri uzunluğu doğru');
```

- [ ] **Step 3: Testi çalıştır**

```bash
npm run check:latvian-pack
```

Beklenen: `=== Ses üretimi ===` altında on üç `✓`, çıkış kodu 0.

- [ ] **Step 4: Commit**

```bash
git add src/learning-lv/audio.ts tools/check-latvian-pack.mjs
git commit -m "feat: add Latvian speech synthesis with audio validation"
```

---

### Task 7: Üretim CLI'ı — metin aşaması

**Files:**
- Create: `tools/generate-latvian-pack.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: Görev 1-6'daki her şey
- Produces: `node tools/generate-latvian-pack.mjs --text` komutu; ara çıktı `data/lv-pack-draft.json` (sahne sahne biriken taslak); nihai çıktı yok (Görev 8'de tamamlanır).

Betik her sahneyi ayrı işler ve her sahne bitince taslağı diske yazar. Yeniden çalıştırıldığında taslakta zaten bulunan sahneleri atlar — bu, kesinti dayanıklılığı gereksinimini karşılar.

- [ ] **Step 1: CLI'ın metin aşamasını yaz**

`tools/generate-latvian-pack.mjs`:

```javascript
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
const CONTENT_MODEL = process.env.OPENROUTER_CONTENT_MODEL ?? 'google/gemini-3.1-flash';
const REVIEW_MODEL = process.env.OPENROUTER_REVIEW_MODEL ?? 'google/gemini-3.1-flash';
const MAX_FREQ_RANK = 5000;
const ALLOW_LIST = ['Turcija', 'no Turcijas', 'Latvija', 'Rīga', 'eiro', 'kempings'];

const args = process.argv.slice(2);
const flagValue = name => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const hasFlag = name => args.includes(name);

const root = process.cwd();
const draftPath = path.join(root, 'data/lv-pack-draft.json');
const frequencyPath = path.join(root, 'data/lv-frequency-top5000.txt');

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
  const { accepted, dropped } = applyReview(generated, verdicts);
  for (const entry of dropped) console.log(`  ✗ ${entry.lv} — ${entry.reason}`);

  const wordFilter = filterByFrequency(accepted.words, ranks, {
    maxRank: MAX_FREQ_RANK,
    allowList: ALLOW_LIST,
  });
  for (const entry of wordFilter.rejected) console.log(`  ✗ ${entry.lv} — ${entry.reason}`);

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
```

- [ ] **Step 2: `package.json`'a betiği ekle**

`scripts` bölümünde `generate:learning-lv` satırını şununla değiştir:

```json
    "generate:latvian": "node --experimental-strip-types tools/generate-latvian-pack.mjs",
```

- [ ] **Step 3: Kuru çalıştırmayla doğrula**

```bash
npm run generate:latvian -- --text --scene lv-s03-markette --dry-run
```

Beklenen: `▸ 3. Markette` başlığı ve altında "Markette", "kafija", "case_drill" geçen bir istem metni. Hiçbir ağ çağrısı yapılmaz, `data/lv-pack-draft.json` oluşmaz.

- [ ] **Step 4: Gerçek üretimi tek sahnede dene**

```bash
OPENROUTER_API_KEY=<anahtar> npm run generate:latvian -- --text --scene lv-s03-markette
```

Beklenen: üretim ve denetim satırları, sonda `✓ kaydedildi: N kelime, M cümle` (N en az 15, M en az 10). `data/lv-pack-draft.json` oluşur. Elenen maddeler `✗` ile listelenir.

Üretilen kelimeleri gözle kontrol et: Letonca diakritikler yerinde mi, Türkçe karşılıklar doğru mu. Değilse `CONTENT_MODEL`'i güçlü bir modelle değiştirip tekrar dene.

- [ ] **Step 5: Commit**

```bash
git add tools/generate-latvian-pack.mjs package.json
git commit -m "feat: add Latvian content generation CLI text stage"
```

---

### Task 8: Üretim CLI'ı — ses aşaması ve paket birleştirme

**Files:**
- Modify: `tools/generate-latvian-pack.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `data/lv-pack-draft.json` (Görev 7), Görev 6'daki ses modülü
- Produces: `--audio` bayrağı; ses dosyaları `data/lv-audio/<audioId>.wav`; `--pack` bayrağı; nihai paket `ios/Karavan/Resources/latvian-pack.json`; `--upload` bayrağı; Blob'a yükleme ve `audioBaseUrl` yazımı.

- [ ] **Step 1: Kullanım kontrolünü genişlet**

`tools/generate-latvian-pack.mjs` içinde `if (!hasFlag('--text'))` bloğunu şununla değiştir:

```javascript
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
```

Ardından metin döngüsünü `if (stages.text) { ... }` bloğunun içine al ve `console.log('\nMetin aşaması tamam.')` satırını o bloğun sonuna taşı.

- [ ] **Step 2: Ses aşamasını ekle**

Metin bloğunun ardına, dosyanın yardımcı fonksiyonlarından önce ekle:

```javascript
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
      await fs.writeFile(filePath, wav);
      produced += 1;
      console.log(`  ✓ ${target.audioId} "${target.text}" (${Math.round(wav.length / 1024)} KB)`);
    } catch (error) {
      console.error(`  ✗ ${target.audioId} "${target.text}" — ${error.message}`);
    }
  }
  console.log(`Ses aşaması tamam: ${produced} üretildi, ${skipped} atlandı.`);
}

if (stages.pack) {
  const audioBaseUrl = process.env.LV_AUDIO_BASE_URL ?? draft.audioBaseUrl;
  if (!audioBaseUrl) {
    console.error('LV_AUDIO_BASE_URL tanımlı değil ve taslakta kayıtlı değil. Önce --upload çalıştır.');
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
  const files = (await fs.readdir(audioDir)).filter(name => name.endsWith('.wav'));
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
```

- [ ] **Step 3: Yardımcı fonksiyonları ekle**

Dosyanın sonuna ekle:

```javascript
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
```

Import bloğuna ekle:

```javascript
import {
  assertUsableAudio,
  audioIdFor,
  buildSpeechRequest,
  extractAudioFromStream,
  wrapPcm16AsWav,
} from '../src/learning-lv/audio.ts';
import { PACK_VERSION, validatePack } from '../src/learning-lv/pack-schema.ts';
```

(`audioIdFor` için var olan tekil import satırını sil; yukarıdaki blok onu kapsıyor.)

- [ ] **Step 4: `.gitignore`'a ara çıktıları ekle**

`.gitignore` sonuna ekle:

```
data/lv-pack-draft.json
data/lv-audio/
```

Gerekçe: taslak ve ham WAV dosyaları ara üründür; depoya giren yalnızca nihai `latvian-pack.json` ve Blob'daki sesler.

- [ ] **Step 5: Tüm sahneleri üret**

```bash
OPENROUTER_API_KEY=<anahtar> npm run generate:latvian -- --text
```

Beklenen: 12 sahne sırayla üretilir (zaten üretilmiş olan atlanır), her birinde `✓ kaydedildi` satırı. Süre yaklaşık 5-10 dakika.

- [ ] **Step 6: Sesleri üret ve ilk beşini dinle**

```bash
OPENROUTER_API_KEY=<anahtar> npm run generate:latvian -- --audio
```

Beklenen: her ses için `✓ <id> "<metin>" (N KB)` satırı. Başarısız olanlar `✗` ile listelenir ve betik devam eder; aynı komut tekrar çalıştırılınca yalnızca eksikler üretilir.

Ardından kaliteyi doğrula:

```bash
ls data/lv-audio/*.wav | head -5 | xargs -n1 afplay
```

Letonca telaffuz kabul edilebilir değilse `OPENROUTER_TTS_MODEL` ve `OPENROUTER_TTS_VOICE` değerlerini değiştirip `data/lv-audio/` klasörünü silerek tekrar dene.

- [ ] **Step 7: Yükle ve paketi yaz**

```bash
BLOB_READ_WRITE_TOKEN=<jeton> npm run generate:latvian -- --upload
npm run generate:latvian -- --pack
```

Beklenen: yükleme sonunda `audioBaseUrl: https://...`, ardından `Paket yazıldı: 12 sahne, N kelime, M cümle` ve `ios/Karavan/Resources/latvian-pack.json` oluşur. N en az 200, M en az 150 olmalı; altındaysa eksik sahneleri `--scene` ile yeniden üret.

- [ ] **Step 8: Commit**

```bash
git add tools/generate-latvian-pack.mjs package.json .gitignore ios/Karavan/Resources/latvian-pack.json
git commit -m "feat: add Latvian audio synthesis, blob upload, and pack assembly"
```

---

### Task 9: Eski learning-os hattını kaldır

Yeni hat çalışır paket ürettikten sonra yapılır — daha önce değil.

**Files:**
- Delete: `src/learning-os/` (tüm klasör), `src/pages/api/learning-os/` (tüm klasör), `tools/generate-latvian-learning-os.mjs`, `tools/check-learning-os.mjs`, `public/assets/learning-os/`, `ios/Karavan/Resources/learning-lv-tr-starter.json`
- Modify: `package.json`

**Interfaces:**
- Consumes: yok
- Produces: yok (temizlik görevi)

- [ ] **Step 1: Kalan referansları bul**

```bash
grep -rn "learning-os\|learning-lv-tr-starter" --include="*.ts" --include="*.mjs" --include="*.astro" --include="*.swift" --include="*.json" --include="*.pbxproj" . | grep -v node_modules | grep -v "^./docs"
```

Çıkan her satır Adım 2 ve 3'te ele alınacak. iOS proje dosyasındaki (`project.pbxproj`) referanslar Xcode'da kaynak silinerek temizlenir.

- [ ] **Step 2: Dosyaları sil**

```bash
git rm -r src/learning-os src/pages/api/learning-os public/assets/learning-os
git rm tools/generate-latvian-learning-os.mjs tools/check-learning-os.mjs
git rm ios/Karavan/Resources/learning-lv-tr-starter.json
```

- [ ] **Step 3: `package.json`'dan ölü betiği kaldır**

`scripts` bölümünden şu satırı sil:

```json
    "check:learning-os": "node --experimental-strip-types tools/check-learning-os.mjs",
```

- [ ] **Step 4: Doğrula**

```bash
npm run check && npm run lint && npm run check:latvian-pack && npm run build
```

Beklenen: dördü de hatasız. `astro check` eksik modül hatası verirse Adım 1'deki grep çıktısında kalan bir referans var demektir; onu temizle.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove legacy learning-os pipeline"
```

---

## Tamamlanma ölçütü

Bu plan tamamlandığında:

- `ios/Karavan/Resources/latvian-pack.json` var, `validatePack` süzgecinden geçiyor, en az 200 kelime ve 150 cümle içeriyor.
- Her kelime ve cümle için Blob'da bir WAV dosyası var, hepsi `assertUsableAudio` doğrulamasından geçmiş.
- `npm run check:latvian-pack` yeşil.
- `npm run check`, `npm run lint`, `npm run build` yeşil.
- Eski `learning-os` kodu depoda yok.

Bir sonraki plan: `2026-07-27-letonca-ogrenme-motoru.md` (iOS tarafı, bu paketi tüketir).

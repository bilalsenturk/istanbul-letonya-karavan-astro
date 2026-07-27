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

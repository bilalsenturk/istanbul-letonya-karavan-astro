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
  const distractors = [
    ...new Set(
      (input.distractorSuffixes ?? [])
        .map(entry => String(entry).trim())
        .filter(entry => entry && entry !== input.suffix),
    ),
  ];
  if (distractors.length < 2) return undefined;
  return { ...input, distractorSuffixes: distractors.slice(0, 3) };
}

function stripCodeFence(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  const withoutOpening = trimmed.replace(/^```[a-z]*\n?/i, '');
  const closingIndex = withoutOpening.indexOf('```');
  const content = closingIndex === -1 ? withoutOpening : withoutOpening.slice(0, closingIndex);
  return content.trim();
}

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

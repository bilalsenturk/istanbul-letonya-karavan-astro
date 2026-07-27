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

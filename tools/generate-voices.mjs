#!/usr/bin/env node
// Kuzey anonslarını OpenRouter (openai/gpt-audio) ile seslendirir.
//
//   OPENROUTER_API_KEY=... node tools/generate-voices.mjs                # hepsi, onyx
//   OPENROUTER_API_KEY=... node tools/generate-voices.mjs --voice nova   # ikinci ses (app rastgele çalar)
//   ... --only captain      # yalnızca bir kategori
//   ... --limit 5           # ilk N tanesi (deneme)
//   ... --dry-run           # istek atmadan istemi göster
//
// Var olan dosyayı atlar → yarıda kalırsa aynı komutla kaldığı yerden devam eder.
// Manifest her adımda kaydedilir: public/audio/manifest.json (anahtar → [dosyalar])
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
const flag = (name, fallback) => (args.includes(name) ? args[args.indexOf(name) + 1] : fallback);
const has = (name) => args.includes(name);

const KEY = process.env.OPENROUTER_API_KEY;
const voice = flag('--voice', 'onyx');
const model = flag('--model', 'openai/gpt-audio');
const only = flag('--only', null);
const limit = Number(flag('--limit', 0)) || 0;
const dryRun = has('--dry-run');

if (!KEY && !dryRun) {
  console.error('OPENROUTER_API_KEY gerekli (veya --dry-run kullan)');
  process.exit(1);
}

const catalog = JSON.parse(fs.readFileSync('public/assets/announcements.json', 'utf8'));
const outDir = 'public/audio';
fs.mkdirSync(outDir, { recursive: true });

// --- Dil ------------------------------------------------------------------
const LANGS = { bg: 'Bulgarca', ro: 'Rumence', hu: 'Macarca', pl: 'Lehçe', lv: 'Letonca' };
const langOf = (key) => {
  const m = key.match(/-(bg|ro|hu|pl|lv)$/);
  return m ? LANGS[m[1]] : 'Türkçe';
};

const category = (key) => key.replace(/-\d+$/, '');

// --- Kategoriye göre ton yönergesi (kalitenin asıl kaldıracı) --------------
const TONE = {
  captain:
    'Bir havayolu kaptanının anons tonu: sakin, sıcak, özgüvenli, hafif esprili. ' +
    'Mikrofona konuşuyormuş gibi; acele etme, cümle sonlarında hafif gülümseme hissi olsun.',
  ready: 'Enerjik ama telaşsız; yola çıkış öncesi toparlayıcı, motive edici.',
  morning: 'Sabah tonu: yumuşak başlayıp canlanan, güler yüzlü.',
  'rest-reminder': 'Sakin, şefkatli öneri tonu; emir değil, iyi niyetli hatırlatma.',
  'border-ahead': 'Pratik ve derli toplu; hafif ciddiyet, sonunda küçük bir gülümseme.',
  deviation: 'Sakin ve güven verici; panik yok, hafif şakacı.',
  'rain-start': 'ÖNCE net ve sakin sürüş talimatı; SONRAKİ cümlede hafif espri. Aceleci olma.',
  storm: 'Ciddi ama panik yaratmayan net uyarı; son cümlede yumuşak espri.',
  crosswind: 'Net, sakin güvenlik talimatı; sonda hafif espri.',
  'rough-road': 'Uyarıcı ama rahat; sonda esprili.',
  'speed-warning': 'Yumuşak ama kararlı uyarı; azarlamadan.',
  focus: 'Kısa, net, dikkat çekici; ciddi ama sert değil.',
  traffic: 'Sabırlı, olgun, hafif mizahlı.',
  'fuel-low': 'Pratik hatırlatma; hafif şakacı.',
  'camp-ahead': 'Günün sonu rahatlaması; sıcak, neşeli.',
  'eta-60': 'Bilgilendirici, keyifli.',
  'eta-30': 'Bilgilendirici, keyifli.',
  'eta-10': 'Heyecanlı, varış havası.',
  snack: 'Kabin görevlisi neşesi; oyuncu.',
  karaoke: 'Coşkulu, eğlenceli, davetkâr.',
  silence: 'Fısıltıya yakın, sakin, esprili.',
  'family-council': 'Yarı resmî, komik bir toplantı duyurusu tonu.',
  rare: 'Beklenmedik, kuru mizah; hafif ironik.',
};

// Güvenlik anonsları: talimat önce, net ve gülmesiz. Gülme yalnızca sonda.
const CRITICAL = new Set([
  'rain-start', 'storm', 'crosswind', 'speed-warning', 'focus',
  'rough-road', 'fuel-low', 'border-ahead', 'deviation',
]);

/** Her anonsta doğal bir gülümseme/kıkırdama — kritiklerde yalnızca son cümlede. */
const laughFor = (key) =>
  CRITICAL.has(category(key))
    ? '\nGÜLME: İlk cümleyi (güvenlik talimatını) net, sakin ve GÜLMEDEN söyle. ' +
      'Gülme yalnızca EN SON cümlede, kısa ve hafif bir kıkırdama olarak gelsin.'
    : '\nGÜLME: Anons boyunca gülümseyerek konuş; sonunda kısa, doğal bir kıkırdama ' +
      '(hafif "heh" / gülümseme nefesi) olsun. Abartma, kahkaha atma, 1 saniyeyi geçmesin.';

const toneFor = (key) => {
  const cat = category(key);
  if (cat.startsWith('arrive-')) {
    return 'Sıcak, samimi bir "hoş geldiniz" tonu; varış sevinci hissedilsin.';
  }
  return TONE[cat] ?? 'Sakin, sıcak, doğal bir anons tonu.';
};

// Sistem mesajı ön-sözü ("Tabii, hemen okuyorum:") engeller — kullanıcı mesajı
// SADECE seslendirilecek metin olur.
const buildSystem = (key) => {
  const lang = langOf(key);
  const native = lang !== 'Türkçe'
    ? `Metin ${lang} dilinde; ${lang} telaffuzuna sadık, ana dili konuşanı gibi oku. `
    : '';
  return (
    `Sen bir karavan yolculuğunun araç içi anons sesisin. Şakacı, neşeli, ` +
    `gülümseyerek konuşan bir kaptan gibisin. ${native}` +
    `Ton: ${toneFor(key)}` +
    laughFor(key) + '\n' +
    `Kullanıcının mesajı SESLENDİRİLECEK METİNDİR. Onu aynen, kelimesi kelimesine oku. ` +
    `Asla giriş cümlesi (Tabii, elbette, hemen okuyorum gibi), onay, açıklama, yorum ` +
    `veya ek kelime ekleme. Yanıtın SADECE metnin seslendirilmesi olsun.`
  );
};

// --- Çalıştır -------------------------------------------------------------
let entries = Object.entries(catalog)
  .filter(([k]) => !only || category(k) === only || k.startsWith(only));
if (limit) entries = entries.slice(0, limit);

const manifestPath = path.join(outDir, 'manifest.json');
const manifest = fs.existsSync(manifestPath)
  ? JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  : {};

console.log(`${entries.length} anons · ses: ${voice} · model: ${model}${dryRun ? ' · DRY RUN' : ''}`);

if (dryRun) {
  const [k, t] = entries[0];
  console.log('\nSistem (' + k + '):\n---\n' + buildSystem(k) + '\n---\nMetin: ' + t);
  const cats = [...new Set(entries.map(([key]) => category(key)))];
  console.log(`\n${cats.length} kategori: ${cats.join(', ')}`);
  process.exit(0);
}

/** 24 kHz mono 16-bit PCM → WAV (afconvert/lame için başlık gerekiyor). */
function wavFromPcm(pcm, sampleRate = 24000) {
  const h = Buffer.alloc(44);
  const ch = 1, bps = 16;
  h.write('RIFF', 0);
  h.writeUInt32LE(36 + pcm.length, 4);
  h.write('WAVE', 8);
  h.write('fmt ', 12);
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(ch, 22);
  h.writeUInt32LE(sampleRate, 24);
  h.writeUInt32LE((sampleRate * ch * bps) / 8, 28);
  h.writeUInt16LE((ch * bps) / 8, 32);
  h.writeUInt16LE(bps, 34);
  h.write('data', 36);
  h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

/** Transkript, hedef metne sadık mı? (model bazen metni okumak yerine uyduruyor) */
const normalize = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

function isFaithful(transcript, text) {
  if (!transcript) return true;                 // transkript gelmediyse ses üzerinden yargılama
  const t = normalize(transcript), target = normalize(text);
  if (t.includes(target)) return true;
  // Kelime örtüşmesi: hedefin kelimelerinin en az %75'i transkriptte geçmeli
  const words = [...new Set(target.split(' ').filter((w) => w.length > 3))];
  if (!words.length) return true;
  const hits = words.filter((w) => t.includes(w)).length;
  return hits / words.length >= 0.75;
}

/** Akıştan ses (pcm16) + transkript topla. Akış zorunlu: mp3 stream'de desteklenmiyor. */
async function synthesize(key, text, strict = false) {
  const system = strict
    ? buildSystem(key) +
      '\nÇOK ÖNEMLİ: Metni yorumlama, özetleme veya yeniden yazma. ' +
      'Verilen cümleleri birebir, aynı kelimelerle seslendir.'
    : buildSystem(key);

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: true,
      modalities: ['text', 'audio'],
      audio: { voice, format: 'pcm16' },
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: text },
      ],
    }),
  });

  const raw = await res.text();
  let b64 = '', transcript = '', apiError = null;
  for (const line of raw.split('\n')) {
    if (!line.startsWith('data: ')) {
      if (line.trim().startsWith('{')) {
        try { apiError = JSON.parse(line).error ?? apiError; } catch {}
      }
      continue;
    }
    const payload = line.slice(6).trim();
    if (payload === '[DONE]') continue;
    try {
      const j = JSON.parse(payload);
      if (j.error) { apiError = j.error; continue; }
      const a = j.choices?.[0]?.delta?.audio;
      if (a?.data) b64 += a.data;
      if (a?.transcript) transcript += a.transcript;
    } catch {}
  }
  if (apiError) throw new Error(apiError.message || JSON.stringify(apiError));
  if (!b64) throw new Error('yanıtta ses yok');
  return { pcm: Buffer.from(b64, 'base64'), transcript: transcript.trim() };
}

let done = 0, skipped = 0, failed = 0, drifted = 0;
for (const [key, text] of entries) {
  const file = `${key}-${voice}.m4a`;
  const dest = path.join(outDir, file);
  if (fs.existsSync(dest)) { skipped++; continue; }

  const tmpWav = path.join(os.tmpdir(), `kuzey-${key}-${Date.now()}.wav`);
  try {
    // Metne sadık kalana kadar en fazla 3 deneme (2. denemeden sonra katı istem)
    let pcm, transcript, faithful = false;
    for (let attempt = 0; attempt < 3 && !faithful; attempt++) {
      ({ pcm, transcript } = await synthesize(key, text, attempt > 0));
      faithful = isFaithful(transcript, text);
      if (!faithful && attempt < 2) {
        process.stdout.write(`\r  ↻ ${key}: sapma, yeniden deneniyor (${attempt + 2}/3)`.padEnd(72));
        await new Promise((r) => setTimeout(r, 400));
      }
    }
    const seconds = pcm.length / (24000 * 2);
    if (seconds < 0.4) throw new Error(`ses çok kısa (${seconds.toFixed(1)} sn)`);
    if (!faithful) {
      drifted++;
      console.log(`\n  ! ${key}: 3 denemede de metne sadık kalmadı → "${transcript.slice(0, 60)}…"`);
    }

    fs.writeFileSync(tmpWav, wavFromPcm(pcm));
    execFileSync('afconvert', ['-f', 'm4af', '-d', 'aac', '-b', '64000', tmpWav, dest]);

    manifest[key] = [...new Set([...(manifest[key] || []), file])];
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    done++;
    process.stdout.write(`\r  ✓ ${done}/${entries.length} (${key}, ${seconds.toFixed(1)}sn)`.padEnd(72));
  } catch (e) {
    failed++;
    console.log(`\n  ✗ ${key}: ${String(e.message).slice(0, 90)}`);
    if (/Insufficient credits|402/.test(String(e.message))) {
      console.log('  → kredi bitti. Kredi ekleyip AYNI komutu çalıştır; kaldığı yerden devam eder.');
      break;
    }
  } finally {
    try { fs.unlinkSync(tmpWav); } catch {}
  }
  await new Promise((r) => setTimeout(r, 150));
}
if (drifted) console.log(`\n  (${drifted} kliple transkript sapması bildirildi — dinleyip gerekirse sil)`);

console.log(`\n\nbitti: ${done} üretildi · ${skipped} atlandı (zaten vardı) · ${failed} hata`);
console.log(`manifest: ${Object.keys(manifest).length} anahtar → ${manifestPath}`);

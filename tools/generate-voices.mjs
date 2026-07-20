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

const toneFor = (key) => {
  const cat = category(key);
  if (cat.startsWith('arrive-')) {
    return 'Sıcak, samimi bir "hoş geldiniz" tonu; varış sevinci hissedilsin.';
  }
  return TONE[cat] ?? 'Sakin, sıcak, doğal bir anons tonu.';
};

const buildPrompt = (key, text) => {
  const lang = langOf(key);
  const native = lang !== 'Türkçe'
    ? `Metin ${lang}. ${lang} telaffuzuna sadık, ana dili konuşanı gibi oku. `
    : '';
  return (
    `Sen bir karavan yolculuğunun araç içi anons sesisin. ${native}` +
    `Ton: ${toneFor(key)}\n\n` +
    `Aşağıdaki metni AYNEN, kelimesi kelimesine seslendir. ` +
    `Hiçbir selamlama, açıklama, özet veya ek cümle ekleme. Sadece metni oku:\n\n` +
    text
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
  console.log('\nÖrnek istem (' + k + '):\n---\n' + buildPrompt(k, t) + '\n---');
  const cats = [...new Set(entries.map(([key]) => category(key)))];
  console.log(`\n${cats.length} kategori: ${cats.join(', ')}`);
  process.exit(0);
}

let done = 0, skipped = 0, failed = 0;
for (const [key, text] of entries) {
  const file = `${key}-${voice}.mp3`;
  const dest = path.join(outDir, file);
  if (fs.existsSync(dest)) { skipped++; continue; }

  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        modalities: ['text', 'audio'],
        audio: { voice, format: 'mp3' },
        messages: [{ role: 'user', content: buildPrompt(key, text) }],
      }),
    });
    const j = await res.json();
    if (j.error) throw new Error(j.error.message || JSON.stringify(j.error));
    const b64 = j.choices?.[0]?.message?.audio?.data;
    if (!b64) throw new Error('yanıtta ses yok');

    const buf = Buffer.from(b64, 'base64');
    if (buf.length < 2000) throw new Error('ses çok kısa (' + buf.length + ' bayt)');
    fs.writeFileSync(dest, buf);
    manifest[key] = [...new Set([...(manifest[key] || []), file])];
    fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    done++;
    process.stdout.write(`\r  ✓ ${done} üretildi (${key})`.padEnd(72));
  } catch (e) {
    failed++;
    console.log(`\n  ✗ ${key}: ${String(e.message).slice(0, 90)}`);
    if (/Insufficient credits|402/.test(String(e.message))) {
      console.log('  → kredi bitti. Kredi ekleyip AYNI komutu çalıştır; kaldığı yerden devam eder.');
      break;
    }
  }
  await new Promise((r) => setTimeout(r, 200));
}

console.log(`\n\nbitti: ${done} üretildi · ${skipped} atlandı (zaten vardı) · ${failed} hata`);
console.log(`manifest: ${Object.keys(manifest).length} anahtar → ${manifestPath}`);

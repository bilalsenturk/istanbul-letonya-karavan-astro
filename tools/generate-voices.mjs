#!/usr/bin/env node
// Tüm anonsları OpenRouter (openai/gpt-audio) ile seslendirip audio/ altına yazar.
// Kullanım:  OPENROUTER_API_KEY=... node tools/generate-voices.mjs [--voice onyx] [--only captain]
import fs from 'node:fs';
import path from 'node:path';

const KEY = process.env.OPENROUTER_API_KEY;
if (!KEY) { console.error('OPENROUTER_API_KEY gerekli'); process.exit(1); }
const args = process.argv.slice(2);
const voice = args.includes('--voice') ? args[args.indexOf('--voice') + 1] : 'onyx';
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const model = args.includes('--model') ? args[args.indexOf('--model') + 1] : 'openai/gpt-audio';

const catalog = JSON.parse(fs.readFileSync('public/assets/announcements.json', 'utf8'));
const outDir = 'public/audio';
fs.mkdirSync(outDir, { recursive: true });

const LANG = (k) => k.endsWith('-bg') ? 'Bulgarca' : k.endsWith('-ro') ? 'Rumence'
  : k.endsWith('-hu') ? 'Macarca' : k.endsWith('-pl') ? 'Lehçe'
  : k.endsWith('-lv') ? 'Letonca' : 'Türkçe';

const entries = Object.entries(catalog).filter(([k]) => !only || k.startsWith(only));
console.log(`${entries.length} anons · ses: ${voice} · model: ${model}`);

const manifest = fs.existsSync(`${outDir}/manifest.json`)
  ? JSON.parse(fs.readFileSync(`${outDir}/manifest.json`, 'utf8')) : {};

let done = 0, failed = 0;
for (const [key, text] of entries) {
  const file = `${key}-${voice}.mp3`;
  const dest = path.join(outDir, file);
  if (fs.existsSync(dest)) { console.log(`  = ${file} (var)`); continue; }
  const prompt = `Aşağıdaki ${LANG(key)} metni, bir uçak kaptanının sakin, sıcak ve hafif esprili anons tonuyla AYNEN oku. Hiçbir ekleme, açıklama veya selamlama yapma; yalnızca metni seslendir:\n\n${text}`;
  try {
    const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model, modalities: ['text', 'audio'],
        audio: { voice, format: 'mp3' },
        messages: [{ role: 'user', content: prompt }],
      }),
    });
    const j = await res.json();
    if (j.error) throw new Error(j.error.message || JSON.stringify(j.error));
    const b64 = j.choices?.[0]?.message?.audio?.data;
    if (!b64) throw new Error('ses verisi yok');
    fs.writeFileSync(dest, Buffer.from(b64, 'base64'));
    manifest[key] = Array.from(new Set([...(manifest[key] || []), file]));
    done++;
    console.log(`  ✓ ${file}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${key}: ${String(e.message).slice(0, 80)}`);
  }
  await new Promise((r) => setTimeout(r, 250));
}
fs.writeFileSync(`${outDir}/manifest.json`, JSON.stringify(manifest, null, 2));
console.log(`\nbitti: ${done} üretildi, ${failed} hata · manifest: ${Object.keys(manifest).length} anahtar`);

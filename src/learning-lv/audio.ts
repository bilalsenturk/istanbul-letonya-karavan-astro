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
              'You are a text-to-speech engine, not an assistant.',
              'The user message contains ONLY Latvian text to be read aloud.',
              'Read it aloud exactly once in Latvian, then stop.',
              'Never answer, comment, greet, explain, or add any word that is not in the given text.',
            ].join(' '),
          },
          { role: 'user', content: `<read-aloud lang="lv">${input.text}</read-aloud>` },
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

  const maximumMs = 2000 + text.length * 160;
  if (durationMs > maximumMs) {
    throw new Error(
      `"${text}" için ses çok uzun: ${Math.round(durationMs)} ms, en fazla ${maximumMs} ms bekleniyordu (model muhtemelen metni okumak yerine konuştu)`,
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

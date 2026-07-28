import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import astro from 'eslint-plugin-astro';

const runtimeGlobals = Object.fromEntries([
  'AbortSignal',
  'Buffer',
  'CSS',
  'CustomEvent',
  'Event',
  'Headers',
  'HTMLElement',
  'IntersectionObserver',
  'MouseEvent',
  'ReadableStream',
  'Request',
  'ResizeObserver',
  'Response',
  'TextDecoder',
  'TextEncoder',
  'URL',
  'URLSearchParams',
  'caches',
  'clearTimeout',
  'console',
  'crypto',
  'customElements',
  'document',
  'fetch',
  'localStorage',
  'navigator',
  'performance',
  'process',
  'requestAnimationFrame',
  'self',
  'setTimeout',
  'window',
].map((name) => [name, 'readonly']));

export default [
  {
    ignores: ['dist/**', '.vercel/**', '.astro/**', 'node_modules/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...astro.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: runtimeGlobals,
    },
    rules: {
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
      'no-empty': ['error', { allowEmptyCatch: true }],
    },
  },
];

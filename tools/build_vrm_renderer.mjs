/**
 * Bundle assets/web/yoga_vrm_renderer.js + npm deps into a single IIFE
 * so WKWebView/Android WebView can run fully offline (no CDN).
 *
 * Usage: npm run build:renderer
 */
import * as esbuild from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const entry = path.join(root, 'Assets/web/yoga_vrm_renderer.js');
const outfile = path.join(root, 'Assets/web/yoga_vrm_renderer.bundle.js');

await esbuild.build({
  entryPoints: [entry],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['es2020'],
  outfile,
  logLevel: 'info',
  // Prefer ESM builds of three / three-vrm
  mainFields: ['module', 'browser', 'main'],
  // Keep console logs for device debugging
  drop: [],
  legalComments: 'none',
});

console.log(`[build_vrm_renderer] wrote ${path.relative(root, outfile)}`);

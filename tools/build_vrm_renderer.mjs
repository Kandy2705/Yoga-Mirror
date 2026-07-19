
import * as esbuild from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const entry = path.join(root, 'assets/web/yoga_vrm_renderer.js');
const outfile = path.join(root, 'assets/web/yoga_vrm_renderer.bundle.js');

await esbuild.build({
  entryPoints: [entry],
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: ['es2020'],
  outfile,
  logLevel: 'info',
  
  mainFields: ['module', 'browser', 'main'],
  
  drop: [],
  legalComments: 'none',
});

console.log(`[build_vrm_renderer] wrote ${path.relative(root, outfile)}`);

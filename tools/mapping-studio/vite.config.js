import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Repo assets: assets/models, assets/poses (case on disk is lowercase)
const assetsRoot = path.resolve(__dirname, '../../assets');

export default defineConfig({
  root: __dirname,
  server: {
    host: '0.0.0.0',
    port: 5173,
    fs: {
      allow: [path.resolve(__dirname, '../..')],
    },
  },
  // Serve project assets under both /Assets and /assets
  publicDir: false,
  plugins: [
    {
      name: 'serve-yoga-assets',
      configureServer(server) {
        server.middlewares.use((req, res, next) => {
          const url = req.url?.split('?')[0] || '';
          if (!url.startsWith('/Assets/') && !url.startsWith('/assets/')) {
            return next();
          }
          const rel = decodeURIComponent(url.replace(/^\/[Aa]ssets\//, ''));
          const filePath = path.join(assetsRoot, rel);
          if (!filePath.startsWith(assetsRoot)) {
            res.statusCode = 403;
            res.end('Forbidden');
            return;
          }
          // Let Vite / sirv-like send via fs
          import('node:fs').then((fs) => {
            fs.readFile(filePath, (err, data) => {
              if (err) {
                res.statusCode = 404;
                res.end(`Not found: ${url}`);
                return;
              }
              if (filePath.endsWith('.json')) res.setHeader('Content-Type', 'application/json');
              else if (filePath.endsWith('.vrm')) res.setHeader('Content-Type', 'model/gltf-binary');
              else if (filePath.endsWith('.js')) res.setHeader('Content-Type', 'application/javascript');
              res.end(data);
            });
          });
        });
      },
    },
  ],
});

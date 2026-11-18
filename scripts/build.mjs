// Dependency-free build: copies src/ to dist/ (the web bundle Capacitor packages into the APK).
import { cpSync, rmSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'src');
const dist = join(root, 'dist');

if (!existsSync(join(src, 'index.html'))) {
  console.error('src/index.html not found');
  process.exit(1);
}
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
cpSync(src, dist, { recursive: true });
console.log('Built dist/:', readdirSync(dist).join(', '));

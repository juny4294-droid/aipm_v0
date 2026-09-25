import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.join(__dirname, 'Product部門方針-summary-detailed-3teams.html');
const pngPath = path.join(__dirname, 'Product部門方針-summary-detailed-3teams.png');

const WIDTH = 1536;
const HEIGHT = 1024;

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: WIDTH, height: HEIGHT },
  deviceScaleFactor: 1,
});
await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
await page.screenshot({
  path: pngPath,
  clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT },
});
await browser.close();
console.log(`Wrote ${pngPath} (${WIDTH}x${HEIGHT})`);

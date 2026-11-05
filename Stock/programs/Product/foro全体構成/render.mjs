import { chromium } from '../projects/Product部門方針/documents/3_planning/node_modules/playwright/index.mjs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const stem = process.argv[2] ?? '20261014_全体構成';
const htmlPath = path.join(__dirname, `${stem}.html`);
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({
  viewport: { width: 1480, height: 1800 },
  deviceScaleFactor: 2,
});
await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
const el = page.locator('#sheet');
const box = await el.boundingBox();
const png = path.join(__dirname, `${stem}.png`);
await el.screenshot({ path: png });
console.log(`Wrote ${png} (${Math.round(box.width)}x${Math.round(box.height)})`);
await browser.close();

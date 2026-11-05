import { chromium } from '../../../../Stock/programs/Product/projects/Product部門方針/documents/3_planning/node_modules/playwright/index.mjs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.join(__dirname, '20261013_組織図.html');
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({
  viewport: { width: 1536, height: 1024 },
  deviceScaleFactor: 2,
});
await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
for (const id of ['y202701', 'y202707_p1', 'y202707_p2']) {
  const el = page.locator('#' + id);
  const box = await el.boundingBox();
  const png = path.join(__dirname, `20261013_組織図_${id}.png`);
  await el.screenshot({ path: png });
  console.log(`Wrote ${png} (${Math.round(box.width)}x${Math.round(box.height)})`);
}
await browser.close();

import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.join(__dirname, 'Product部門方針-mission-mapping.html');
const pngPath = path.join(__dirname, 'Product部門方針-mission-mapping.png');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
await page.goto(`file://${htmlPath}`, { waitUntil: 'networkidle' });
const body = page.locator('body');
const box = await body.boundingBox();
await page.setViewportSize({
  width: Math.ceil(box.width),
  height: Math.ceil(box.height + 20),
});
await page.screenshot({ path: pngPath, fullPage: true });
await browser.close();
console.log(`Wrote ${pngPath}`);

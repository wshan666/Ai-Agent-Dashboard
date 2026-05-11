// render-frames.js — HTML → PNG frames for FFmpeg
// Usage: node scripts/render-frames.js <html-file> <output-dir> <duration-sec> [fps]

const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

(async () => {
  const htmlFile = path.resolve(process.argv[2]);
  const outDir = path.resolve(process.argv[3] || 'frames');
  const duration = parseFloat(process.argv[4] || '30');
  const fps = parseInt(process.argv[5] || '2');
  const totalFrames = Math.ceil(duration * fps);

  if (!htmlFile || !fs.existsSync(htmlFile)) {
    console.error('Usage: node render-frames.js <html-file> <output-dir> <duration-sec> [fps]');
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });
  console.log(`Rendering ${totalFrames} frames (${fps}fps, ${duration}s) from ${htmlFile}`);

  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1080, height: 1920, deviceScaleFactor: 1 });
  await page.goto('file://' + htmlFile, { waitUntil: 'networkidle0', timeout: 15000 });

  // Wait for initial render
  await new Promise(r => setTimeout(r, 1500));

  const intervalMs = Math.round((duration * 1000) / totalFrames);
  const startTime = Date.now();

  for (let i = 0; i < totalFrames; i++) {
    const framePath = path.join(outDir, `frame_${String(i + 1).padStart(4, '0')}.png`);
    await page.screenshot({ path: framePath, type: 'png' });

    // Wait for real time to let JS animations progress naturally
    const elapsed = Date.now() - startTime;
    const nextTarget = (i + 1) * intervalMs;
    const wait = Math.max(50, nextTarget - elapsed);
    await new Promise(r => setTimeout(r, wait));

    process.stdout.write(`\r  Frame ${i + 1}/${totalFrames} (${Math.round(elapsed/1000)}s elapsed)`);
  }

  console.log('\nDone. Frames saved to ' + outDir);
  await browser.close();
})();

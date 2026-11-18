const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const base = new URL(process.env.ICON_BASE_URL || 'http://127.0.0.1:18741');
const root = path.resolve(process.env.SMARTKEYS_SCREENSHOT_DIR || 'build/ui_screenshots');
const reportPath = path.resolve(process.env.WEB_REVIEW_REPORT || path.join(path.dirname(root), 'web-icon-browser-report.json'));

function validatePng(bytes) {
  assert.ok(bytes.length <= 64 * 1024 && bytes.length >= 24);
  assert.deepEqual(bytes.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  assert.ok(bytes.readUInt32BE(16) > 0 && bytes.readUInt32BE(16) <= 512);
  assert.ok(bytes.readUInt32BE(20) > 0 && bytes.readUInt32BE(20) <= 512);
}

(async () => {
  await fs.mkdir(path.join(root, 'web'), {recursive: true});
  const response = await fetch(new URL('/v1/icons/catalog', base));
  assert.equal(response.status, 200);
  const catalog = await response.json();
  assert.equal(catalog.icons.length, 17);
  assert.equal(new Set(catalog.icons.map(icon => icon.canonical_id)).size, 16);
  assert.equal(catalog.icons.filter(icon => icon.available).length, 17);
  const bodies = new Map();
  for (const icon of catalog.icons) {
    assert.equal(icon.mime_type, 'image/png');
    const download = await fetch(new URL(icon.download_url, base));
    assert.equal(download.status, 200, icon.app_id);
    assert.equal(download.headers.get('content-type'), 'image/png');
    assert.equal(download.headers.get('x-content-type-options'), 'nosniff');
    const bytes = Buffer.from(await download.arrayBuffer());
    validatePng(bytes);
    bodies.set(icon.app_id, bytes);
  }
  assert.deepEqual(bodies.get('codex'), bodies.get('chatgpt'));
  for (const id of ['unknown-brand', '..%2Fchrome', 'https%3A%2F%2Fexample.com%2Fimage']) {
    assert.equal((await fetch(new URL('/v1/icons/' + id, base))).status, 404);
  }

  const launch = {headless: true};
  if (process.env.BROWSER_EXECUTABLE_PATH) launch.executablePath = process.env.BROWSER_EXECUTABLE_PATH;
  const browser = await chromium.launch(launch);
  const shots = [];
  const errors = [];
  try {
    const page = await browser.newPage({viewport: {width: 1200, height: 900}, deviceScaleFactor: 1});
    page.on('pageerror', error => errors.push(error.message));
    const capture = async (id, title, orientation, notes) => {
      const bytes = await page.screenshot({fullPage: true});
      const metadata = {id, title, platform: 'Web browser', orientation,
        width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20),
        fileName: 'web/' + id + '.png', notes: notes + ' Real headless browser render; injected failures are identified.'};
      await fs.writeFile(path.join(root, metadata.fileName), bytes);
      await fs.writeFile(path.join(root, 'web', id + '.json'), JSON.stringify(metadata, null, 2) + '\n');
      shots.push(metadata.fileName);
    };
    await page.goto(new URL('/icons', base).href);
    await page.waitForFunction(() => document.querySelectorAll('.icon-card').length === 17);
    await page.locator('.icon-preview img').evaluateAll(async images => {
      for (const image of images) image.loading = 'eager';
      await Promise.all(images.map(image => image.decode()));
    });
    assert.ok((await page.locator('#status').innerText()).includes('16'));
    assert.ok((await page.locator('[data-app-id="solidworks"]').innerText()).includes('favicon'));
    await capture('web-icons-catalog', 'Application icon catalog', 'landscape', 'Seventeen IDs represent sixteen distinct brand fallbacks, with actual source links.');

    await page.locator('#search').fill('vscode');
    assert.equal(await page.locator('.icon-card').count(), 1);
    const [download] = await Promise.all([page.waitForEvent('download'), page.locator('.download').filter({hasText: '下载 PNG'}).click()]);
    assert.equal(download.suggestedFilename(), 'vscode.png');
    validatePng(await fs.readFile(await download.path()));
    await capture('web-icons-search', 'Search and PNG download', 'landscape', 'Search by canonical ID and a real PNG download both succeeded.');

    await page.locator('#search').fill('not-a-registered-app');
    assert.equal(await page.locator('.icon-card').count(), 0);
    assert.ok(await page.locator('#empty').isVisible());
    await capture('web-icons-unknown', 'Unknown icon ID', 'landscape', 'Unknown IDs produce a clear empty state without an external download proxy.');

    await page.locator('#search').fill('');
    await page.setViewportSize({width: 390, height: 844});
    await page.locator('.icon-preview img').evaluateAll(async images => {
      for (const image of images) image.loading = 'eager';
      await Promise.all(images.map(image => image.decode()));
    });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, '390px page must not overflow horizontally');
    await capture('web-icons-mobile', 'Icon catalog at 390 pixels', 'portrait', 'Real 390-pixel viewport; horizontal overflow assertion passed.');

    await page.route('**/v1/icons/catalog', route => route.fulfill({status: 503, contentType: 'application/json', body: '{"error":"temporarily_unavailable"}'}));
    await page.reload();
    await page.locator('#retry').waitFor({state: 'visible'});
    assert.equal(await page.locator('.icon-card').count(), 0);
    assert.ok((await page.locator('#status').innerText()).includes('暂时无法访问'));
    await capture('web-icons-error', 'Catalog error and retry', 'portrait', 'Injected HTTP 503 displays a recoverable error; the retry action is visible.');
    await page.unroute('**/v1/icons/catalog');
    await page.locator('#retry').click();
    await page.waitForFunction(() => document.querySelectorAll('.icon-card').length === 17);
    assert.equal(await page.locator('#retry').isVisible(), false);
    assert.equal(await page.locator('#status').getAttribute('class'), '');
    assert.deepEqual(errors, []);

    const report = {passed: true, ids: 17, canonicalBrands: 16,
      checks: ['bounded PNG downloads', 'source links', 'legacy alias', 'unknown IDs', 'search', 'actual download', '390px no overflow', 'HTTP 503 retry recovery', 'no JavaScript errors'], screenshots: shots};
    await fs.mkdir(path.dirname(reportPath), {recursive: true});
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const base = new URL(process.env.ICON_BASE_URL || 'http://127.0.0.1:18741');
const root = path.resolve(process.env.SMARTKEYS_SCREENSHOT_DIR || 'build/ui_screenshots');
const reportPath = path.resolve(process.env.WEB_REVIEW_REPORT || path.join(path.dirname(root), 'web-icon-browser-report.json'));
function validatePng(bytes) {
  assert.ok(bytes.length <= 65536 && bytes.length >= 24);
  assert.deepEqual(bytes.subarray(0, 8), Buffer.from([137,80,78,71,13,10,26,10]));
  assert.equal(bytes.readUInt32BE(16),256); assert.equal(bytes.readUInt32BE(20),256);
}
(async () => {
  await fs.mkdir(path.join(root,'web'),{recursive:true});
  const response=await fetch(new URL('/v1/icons/catalog',base)); assert.equal(response.status,200);
  const catalog=await response.json(); assert.equal(catalog.schema_version,1); assert.equal(catalog.icons.length,60);
  assert.equal(catalog.icons.filter(icon=>icon.bundled).length,50); assert.equal(catalog.icons.filter(icon=>!icon.bundled).length,10);
  assert.equal(new Set(catalog.icons.map(icon=>icon.sha256)).size,60); assert.ok(!catalog.icons.some(icon=>icon.app_id==='codex'||icon.aliases.includes('codex')));
  const bodies=new Map();
  for(const icon of catalog.icons){
    assert.equal(icon.canonical_id,icon.app_id); assert.equal(icon.mime_type,'image/png'); assert.ok(icon.source_page_url.startsWith('https://')); assert.ok(icon.terms_url.startsWith('https://'));
    const download=await fetch(new URL(icon.download_url,base)); assert.equal(download.status,200,icon.app_id); assert.equal(download.headers.get('content-type'),'image/png'); assert.equal(download.headers.get('x-content-type-options'),'nosniff');
    const bytes=Buffer.from(await download.arrayBuffer()); validatePng(bytes); assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),icon.sha256); bodies.set(icon.app_id,bytes);
    const etag=download.headers.get('etag'); assert.equal(etag,'"'+icon.sha256+'"'); assert.equal((await fetch(new URL(icon.download_url,base),{headers:{'If-None-Match':etag}})).status,304);
  }
  const legacy=await fetch(new URL('/v1/icons/codex',base)); assert.ok(legacy.headers.get('x-lumiakey-legacy-icon').includes('historical')); assert.deepEqual(Buffer.from(await legacy.arrayBuffer()),bodies.get('chatgpt'));
  assert.deepEqual(Buffer.from(await (await fetch(new URL('/v1/icons/vs-code',base))).arrayBuffer()),bodies.get('vscode'));
  for(const id of ['unknown-brand','..%2Fchrome','https%3A%2F%2Fexample.com%2Fimage']) assert.equal((await fetch(new URL('/v1/icons/'+id,base))).status,404);
  const launch={headless:true};if(process.env.BROWSER_EXECUTABLE_PATH)launch.executablePath=process.env.BROWSER_EXECUTABLE_PATH;
  const browser=await chromium.launch(launch); const shots=[];const errors=[];
  try{
    const context=await browser.newContext({viewport:{width:1200,height:900},deviceScaleFactor:1,permissions:['clipboard-read','clipboard-write']});const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
    const capture=async(id,title,orientation,notes)=>{const bytes=await page.screenshot({fullPage:true});const metadata={id,title,platform:'Web browser',orientation,width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20),fileName:'web/'+id+'.png',notes:notes+' Real headless Chromium render; injected failures identified.'};await fs.writeFile(path.join(root,metadata.fileName),bytes);await fs.writeFile(path.join(root,'web',id+'.json'),JSON.stringify(metadata,null,2)+'\n');shots.push(metadata.fileName);};
    const ready=()=>page.waitForFunction(()=>document.querySelectorAll('.icon-card').length===60);
    const loadImages=()=>page.locator('.icon-preview img').evaluateAll(async images=>{for(const image of images)image.loading='eager';await Promise.all(images.map(image=>image.decode()));});
    await page.goto(new URL('/icons',base).href);await ready();await loadImages();assert.ok((await page.locator('#status').innerText()).includes('50'));assert.equal(await page.locator('.badge.online').count(),10);
    await capture('web-icons-catalog','Fifty bundled and ten online icons','landscape','All sixty original resources, source/terms links and built-in/online badges.');
    await page.locator('#search').fill('vs-code');assert.equal(await page.locator('.icon-card').count(),1);
    await page.locator('.copy-id').click();assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'vscode');
    const [download]=await Promise.all([page.waitForEvent('download'),page.locator('.icon-card .download').filter({hasText:'下载 PNG'}).click()]);assert.equal(download.suggestedFilename(),'vscode.png');assert.deepEqual(await fs.readFile(await download.path()),bodies.get('vscode'));
    await capture('web-icons-search','Alias search, copied ID and verified download','landscape','Alias vs-code resolves to vscode; clipboard and actual byte-identical PNG download passed.');
    await page.locator('#search').fill('not-a-registered-app');assert.equal(await page.locator('.icon-card').count(),0);assert.ok(await page.locator('#empty').isVisible());await capture('web-icons-unknown','Unknown application empty state','landscape','No proxy or generic substitute is offered for unknown IDs.');
    await page.goto(new URL('/icons?app_id=brave',base).href);await page.locator('[data-app-id="brave"]').waitFor();assert.equal(await page.locator('.icon-card').count(),1);assert.equal(await page.locator('.badge.online').count(),1);
    await capture('web-icons-extra','Online resource outside the fifty built-ins','landscape','Brave is downloadable from the server catalog and absent from the fifty-app bundle.');
    await page.route('**/v1/icons/brave',route=>route.fulfill({status:503,body:'unavailable'}));await page.locator('.icon-card .download').click();await page.getByText('下载暂时不可用。',{exact:true}).waitFor();await capture('web-icons-download-error','Download failure with retry','landscape','Injected PNG HTTP503; explicit retry remains usable.');
    await page.unroute('**/v1/icons/brave');const [recovered]=await Promise.all([page.waitForEvent('download'),page.locator('.icon-card .download').click()]);assert.deepEqual(await fs.readFile(await recovered.path()),bodies.get('brave'));
    await page.goto(new URL('/icons?app_id=codex',base).href);await page.locator('[data-app-id="chatgpt"]').waitFor();assert.ok((await page.locator('#legacy-notice').innerText()).includes('不代表 Codex'));await page.locator('#search').fill('codex');assert.equal(await page.locator('.icon-card').count(),0);
    await page.goto(new URL('/icons',base).href);await ready();await page.setViewportSize({width:390,height:844});await loadImages();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    await page.locator('#search').focus();await page.keyboard.press('Tab');assert.equal(await page.evaluate(()=>document.activeElement.className),'source-link');await capture('web-icons-mobile','Icon library at 390 pixels','portrait','All sixty icons decode; keyboard navigation and no horizontal overflow.');
    await page.route('**/v1/icons/catalog',route=>route.fulfill({status:503,contentType:'application/json',body:'{"error":"temporarily_unavailable"}'}));await page.reload();await page.locator('#retry').waitFor({state:'visible'});assert.equal(await page.locator('.icon-card').count(),0);await capture('web-icons-error','Catalog error and recovery','portrait','Injected catalog HTTP503 with visible retry.');await page.unroute('**/v1/icons/catalog');await page.locator('#retry').click();await ready();assert.equal(await page.locator('#retry').isVisible(),false);
    let heldRoute;await page.route('**/v1/icons/catalog',route=>{heldRoute=route;});await page.reload();await page.getByText('正在加载图标目录…',{exact:true}).waitFor();await capture('web-icons-loading','Catalog loading state','portrait','Catalog response deliberately held; the loading state remains explicit.');await heldRoute.fulfill({status:200,contentType:'application/json',body:JSON.stringify(catalog)});await ready();await page.unroute('**/v1/icons/catalog');
    assert.deepEqual(errors,[]);const report={passed:true,uniqueProducts:60,builtins:50,webOnly:10,checks:['sixty PNG hashes/dimensions','ETag304','ordinary aliases','separate legacy URL','unknown IDs','copied App ID','real download','online-only extra','download503 recovery','390px no overflow','keyboard focus','catalog503 retry','loading','no JavaScript errors'],screenshots:shots};await fs.mkdir(path.dirname(reportPath),{recursive:true});await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1});

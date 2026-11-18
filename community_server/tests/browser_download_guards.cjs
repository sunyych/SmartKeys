const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const base = new URL(process.env.APP_BASE_URL || process.env.ICON_BASE_URL || 'http://127.0.0.1:18742');
const reportPath = path.resolve(process.env.DOWNLOAD_GUARD_REPORT || 'build/web-download-guards.json');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

(async () => {
  const appBytes = Buffer.from(await (await fetch(new URL('/v1/apps/chrome/bundle',base))).arrayBuffer());
  const iconBytes = Buffer.from(await (await fetch(new URL('/v1/icons/chrome',base))).arrayBuffer());
  const bundle = JSON.parse(appBytes);
  const changed = update => { const value=JSON.parse(appBytes); update(value); return Buffer.from(JSON.stringify(value)); };
  const brokenPng = Buffer.from(iconBytes); brokenPng[brokenPng.length-8] ^= 1;
  const appCases = [
    {name:'mismatched registered icon ID',body:changed(value => {value.icon.id='firefox';})},
    {name:'mismatched registered icon hash',body:changed(value => {value.icon.sha256='0'.repeat(64);})},
    {name:'corrupt PNG bytes with otherwise valid bundle transport hash',body:changed(value => {value.icon.pngBase64=brokenPng.toString('base64');})},
    {name:'invalid base64 alphabet',body:changed(value => {value.icon.pngBase64='@@@=';})},
    {name:'noncanonical whitespace in base64',body:changed(value => {value.icon.pngBase64+='\n';})},
    {name:'wrong bundle MIME',body:appBytes,mime:'text/plain'},
    {name:'over 128 KiB body',body:Buffer.alloc(128*1024+1,32)},
    {name:'invalid UTF-8',body:Buffer.from([255,254,253])},
    {name:'wrong whole-bundle ETag',body:appBytes,etag:'"'+'0'.repeat(64)+'"'},
    {name:'wrong immutable content location',body:appBytes,location:'/v1/apps/chrome/bundles/'+ '0'.repeat(64)+'.json'},
    {name:'redirect is not followed',redirect:true},
    {name:'bounded download timeout',timeout:true},
  ];
  const iconCases = [
    {name:'corrupt PNG hash',body:brokenPng},
    {name:'wrong icon MIME',body:iconBytes,mime:'image/jpeg'},
    {name:'over 64 KiB icon',body:Buffer.concat([iconBytes,Buffer.alloc(65537)])},
    {name:'non-PNG content',body:Buffer.from('<svg>not an image/png resource</svg>')},
    {name:'icon redirect is not followed',redirect:true},
  ];
  const launch={headless:true}; if(process.env.BROWSER_EXECUTABLE_PATH)launch.executablePath=process.env.BROWSER_EXECUTABLE_PATH;
  const browser=await chromium.launch(launch), passed=[];
  try {
    const context=await browser.newContext({viewport:{width:1100,height:900}}), page=await context.newPage();
    let downloads=0, redirectedRequests=0;
    page.on('download',()=>downloads++);
    await page.route('**/rejected-download-target',route=>{redirectedRequests++;return route.fulfill({status:500,body:'must not follow redirects'});});
    await page.goto(new URL('/apps?app_id=chrome',base).href);
    await page.locator('[data-app-id="chrome"]').waitFor();
    const appButton=page.locator('.app-card .download'), appFeedback=page.locator('.app-card .feedback');
    for(const test of appCases) {
      let held;
      const before=downloads;
      await page.route('**/v1/apps/chrome/bundle',route=>{
        if(test.timeout){held=route;return;}
        if(test.redirect)return route.fulfill({status:302,headers:{location:'/rejected-download-target'},body:''});
        const body=test.body, digest=hash(body);
        return route.fulfill({status:200,headers:{'content-type':test.mime||'application/json',etag:test.etag||`"${digest}"`,'content-location':test.location||`/v1/apps/chrome/bundles/${digest}.json`},body});
      });
      await appButton.click();
      await page.waitForFunction(()=>{const button=document.querySelector('.app-card .download'),feedback=document.querySelector('.app-card .feedback');return !button.disabled&&feedback.textContent.length>0;},null,{timeout:15000});
      assert.equal(downloads,before,test.name);
      assert.ok(!(await appFeedback.innerText()).includes('下载已开始'),test.name);
      if(test.timeout){assert.ok((await appFeedback.innerText()).includes('下载超时'));await held.abort().catch(()=>{});}
      await page.unroute('**/v1/apps/chrome/bundle'); passed.push(test.name);
    }
    const [appDownload]=await Promise.all([page.waitForEvent('download'),appButton.click()]);
    assert.deepEqual(await fs.readFile(await appDownload.path()),appBytes);
    assert.equal(JSON.parse(await fs.readFile(await appDownload.path())).app.id,bundle.app.id);
    assert.equal(redirectedRequests,0);

    await page.goto(new URL('/icons?app_id=chrome',base).href);
    await page.locator('[data-app-id="chrome"]').waitFor();
    await page.locator('.icon-preview img').evaluate(image=>image.decode());
    const iconButton=page.locator('.icon-card .download'), iconFeedback=page.locator('.icon-card .feedback');
    for(const test of iconCases) {
      const before=downloads;
      await page.route('**/v1/icons/chrome',route=>test.redirect
        ? route.fulfill({status:302,headers:{location:'/rejected-download-target'},body:''})
        : route.fulfill({status:200,contentType:test.mime||'image/png',body:test.body}));
      await iconButton.click();
      await page.waitForFunction(()=>{const button=document.querySelector('.icon-card .download'),feedback=document.querySelector('.icon-card .feedback');return !button.disabled&&feedback.textContent.length>0;});
      assert.equal(downloads,before,test.name);
      assert.ok(!(await iconFeedback.innerText()).includes('下载已开始'),test.name);
      await page.unroute('**/v1/icons/chrome');passed.push(test.name);
    }
    const [iconDownload]=await Promise.all([page.waitForEvent('download'),iconButton.click()]);
    assert.deepEqual(await fs.readFile(await iconDownload.path()),iconBytes);
    assert.equal(redirectedRequests,0);
    const report={passed:true,rejectedCases:passed.length,checks:passed,verifiedRecoveryDownloads:2,redirectTargetsRequested:redirectedRequests};
    await fs.mkdir(path.dirname(reportPath),{recursive:true});await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

(() => {
  const grid = document.getElementById('apps'), status = document.getElementById('status'), search = document.getElementById('search'), os = document.getElementById('os'), retry = document.getElementById('retry'), empty = document.getElementById('empty');
  let apps = [], icons = new Map(), generation = 0;
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$/.test(value) && !value.startsWith('installed.');
  const safeText = value => typeof value === 'string' && value.trim().length > 0 && value === value.trim() && value.length <= 120 && !/[\x00-\x1f\x7f]/.test(value);
  const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
  const unique = values => new Set(values).size === values.length;
  const httpsLink = value => { try { const url = new URL(value); return typeof value === 'string' && value === value.trim() && value.length <= 2048 && url.protocol === 'https:' && !url.username && !url.password; } catch (_) { return false; } };
  const https = value => httpsLink(value) && !new URL(value).hash;
  const systems = values => Array.isArray(values) && values.length > 0 && values.length <= 3 && unique(values) && values.every(value => ['macos','windows','linux'].includes(value));
  const key = value => typeof value === 'string' && /^(?:[A-Z0-9]|F(?:[1-9]|1[0-2])|ENTER|ESC|BACKSPACE|TAB|SPACE|LEFT|RIGHT|UP|DOWN|DELETE|HOME|END|PAGE_UP|PAGE_DOWN|MINUS|EQUAL|LEFT_BRACKET|RIGHT_BRACKET|BACKSLASH|SEMICOLON|QUOTE|BACKTICK|COMMA|PERIOD|SLASH)$/.test(value);
  const action = value => exact(value,['id','title','keys','requiresConfiguration']) && validId(value.id) && safeText(value.title) && value.title.length <= 80 && Array.isArray(value.keys) && typeof value.requiresConfiguration === 'boolean' && (value.requiresConfiguration ? value.keys.length === 0 : value.keys.length > 0 && value.keys.length <= 5 && key(value.keys.at(-1)) && unique(value.keys.slice(0,-1)) && value.keys.slice(0,-1).every(value => ['CTRL','ALT','SHIFT','META'].includes(value)));
  function validApp(app) {
    if (!exact(app,['id','iconId','name','aliases','bundled','supportedOS','libraries']) || !validId(app.id) || app.id !== app.iconId || app.id.toLowerCase() === 'codex' || !safeText(app.name) || !Array.isArray(app.aliases) || app.aliases.length > 16 || !app.aliases.every(value => validId(value) && value.toLowerCase() !== 'codex') || typeof app.bundled !== 'boolean' || !systems(app.supportedOS) || !Array.isArray(app.libraries) || app.libraries.length < 1 || app.libraries.length > 2) return false;
    if (!unique(app.libraries.map(value => value.id)) || !unique(app.libraries.map(value => value.family))) return false;
    const union = new Set();
    for (const library of app.libraries) {
      if (!exact(library,['id','family','supportedOS','version','sourceUrls','context','actions']) || !validId(library.id) || !library.id.startsWith(app.id+'.') || !safeText(library.version) || library.version.length > 80 || !systems(library.supportedOS) || !['native','web','terminal'].includes(library.context) || !Array.isArray(library.sourceUrls) || library.sourceUrls.length < 1 || library.sourceUrls.length > 12 || !library.sourceUrls.every(https) || !unique(library.sourceUrls) || !Array.isArray(library.actions) || library.actions.length < 1 || library.actions.length > 12 || !library.actions.every(action) || !unique(library.actions.map(value => value.id))) return false;
      if (!(library.family === 'macos' && library.supportedOS.every(value => value === 'macos') || library.family === 'windowsLinux' && library.supportedOS.every(value => ['windows','linux'].includes(value)))) return false;
      library.supportedOS.forEach(value => union.add(value));
    }
    return union.size === app.supportedOS.length && app.supportedOS.every(value => union.has(value));
  }
  const sha256 = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)), value => value.toString(16).padStart(2,'0')).join('');
  const stable = value => JSON.stringify(value, (_, item) => item && typeof item === 'object' && !Array.isArray(item) ? Object.fromEntries(Object.keys(item).sort().map(key => [key,item[key]])) : item);
  async function bytes(response, maximum) {
    if (Number(response.headers.get('content-length')) > maximum) throw Error('下载资源超出大小限制。');
    const reader = response.body.getReader(), chunks = []; let length = 0;
    try { while (true) { const result = await reader.read(); if (result.done) break; length += result.value.length; if (length > maximum) throw Error('下载资源超出大小限制。'); chunks.push(result.value); } }
    finally { await reader.cancel(); }
    const output = new Uint8Array(length); let offset = 0; for (const chunk of chunks) { output.set(chunk,offset); offset += chunk.length; } return output;
  }
  async function request(path, maximum, signal) {
    const url = new URL(path,location.origin), response = await fetch(url,{signal,redirect:'error',cache:'no-store',headers:{Accept:'application/json'}});
    if (!response.ok || response.url !== url.href || response.headers.get('content-type')?.split(';')[0] !== 'application/json') throw Error('服务暂时不可用，请重试。');
    const payload = await bytes(response,maximum), data = JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(payload)); return {response,payload,data};
  }
  async function download(app, button, feedback) {
    button.disabled = true; feedback.textContent = '正在校验下载包…';
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(),10000);
    try {
      const {response,payload,data} = await request(`/v1/apps/${encodeURIComponent(app.id)}/bundle`,128*1024,controller.signal), hash = await sha256(payload);
      if (!exact(data,['schemaVersion','app','icon']) || data.schemaVersion !== 1 || !validApp(data.app) || stable(data.app) !== stable(app) || !exact(data.icon,['id','sha256','pngBase64']) || data.icon.id !== app.iconId || data.icon.sha256 !== icons.get(app.iconId).sha256 || response.headers.get('etag') !== `"${hash}"` || response.headers.get('content-location') !== `/v1/apps/${encodeURIComponent(app.id)}/bundles/${hash}.json`) throw Error('下载包与目录不一致，请重新加载。');
      if (typeof data.icon.pngBase64 !== 'string' || data.icon.pngBase64.length > 87384 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data.icon.pngBase64)) throw Error('下载包图标格式无效。');
      const binary = atob(data.icon.pngBase64); if (btoa(binary) !== data.icon.pngBase64) throw Error('下载包图标编码无效。');
      const png = Uint8Array.from(binary,value => value.charCodeAt(0));
      if (png.length < 24 || png.length > 65536 || ![137,80,78,71,13,10,26,10].every((value,index) => png[index] === value) || await sha256(png) !== data.icon.sha256) throw Error('下载包图标校验失败。');
      const image = await createImageBitmap(new Blob([png],{type:'image/png'})); try { if (image.width !== 256 || image.height !== 256) throw Error('下载包图标尺寸无效。'); } finally { image.close(); }
      const href = URL.createObjectURL(new Blob([payload],{type:'application/json'})), link = document.createElement('a'); link.href = href; link.download = `${app.id}.lumia-app.json`; link.click(); setTimeout(() => URL.revokeObjectURL(href),1000);
      feedback.textContent = '下载已开始；导入前仍可预览。';
    } catch (error) { feedback.textContent = error.name === 'AbortError' ? '下载超时，请重试。' : error.message; }
    finally { clearTimeout(timeout); button.disabled = false; }
  }
  function element(tag, text, className) { const node = document.createElement(tag); if (text) node.textContent = text; if (className) node.className = className; return node; }
  const osName = value => ({macos:'macOS',windows:'Windows',linux:'Linux'})[value];
  function displayKeys(keys, library, selectedOS = 'all') {
    const named = {CTRL:'Ctrl',SHIFT:'Shift',ENTER:'Enter',ESC:'Esc',BACKSPACE:'Backspace',TAB:'Tab',SPACE:'Space',LEFT:'←',RIGHT:'→',UP:'↑',DOWN:'↓',DELETE:'Delete',HOME:'Home',END:'End',PAGE_UP:'Page Up',PAGE_DOWN:'Page Down',MINUS:'-',EQUAL:'=',LEFT_BRACKET:'[',RIGHT_BRACKET:']',BACKSLASH:'\\',SEMICOLON:';',QUOTE:"'",BACKTICK:'`',COMMA:',',PERIOD:'.',SLASH:'/'};
    const mac = library.family === 'macos';
    const target = selectedOS !== 'all' ? selectedOS : library.supportedOS.length === 1 ? library.supportedOS[0] : 'shared';
    const meta = mac ? 'Command' : target === 'windows' ? 'Windows' : target === 'linux' ? 'Super' : 'Windows / Super';
    return keys.map(value => value === 'META' ? meta : value === 'ALT' ? mac ? 'Option' : 'Alt' : named[value] ?? value).join(' + ');
  }
  function sourceLink(title,url) { const link = element('a',title); link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer'; return link; }
  function render() {
    grid.replaceChildren(); const query = search.value.trim().toLowerCase(), selected = os.value;
    const shown = apps.filter(app => (selected === 'all' || app.supportedOS.includes(selected)) && [app.id,app.name,...app.aliases].some(value => value.toLowerCase().includes(query)));
    empty.hidden = shown.length !== 0;
    for (const app of shown) {
      const icon = icons.get(app.iconId), card = element('article',null,'app-card'); card.dataset.appId = app.id;
      const heading = element('div',null,'app-heading'), image = element('img',null,'app-icon'); image.src = `/v1/icons/${encodeURIComponent(app.iconId)}`; image.alt = `${app.name} icon`; image.loading = 'lazy';
      const title = element('div'); title.append(element('h2',app.name),element('code',app.id,'app-id')); heading.append(image,title); card.append(heading);
      const badges = element('div',null,'badges'); for (const value of app.supportedOS) badges.append(element('span',osName(value),'badge')); badges.append(element('span',app.bundled ? '离线内置' : '在线扩展','badge')); card.append(badges);
      for (const library of app.libraries.filter(value => selected === 'all' || value.supportedOS.includes(selected))) {
        const details = element('details',null,'library'); details.dataset.family = library.family;
        details.append(element('summary',`${library.supportedOS.map(osName).join(' / ')} · ${{native:'桌面应用',web:'网页应用',terminal:'终端'}[library.context]} · ${library.actions.length} 项`));
        const list = element('ol',null,'actions'); for (const action of library.actions) { const row = element('li',action.title); row.append(element('span',action.requiresConfiguration ? '未分配 · 需要配置' : displayKeys(action.keys,library,selected),action.requiresConfiguration ? 'keys unassigned' : 'keys')); list.append(row); } details.append(list);
        const sources = element('div',null,'source-links'); library.sourceUrls.forEach((url,index) => sources.append(sourceLink(`快捷键来源 ${index+1}`,url))); details.append(sources); card.append(details);
      }
      const provenance = element('div',null,'source-links'); provenance.append(sourceLink('图标来源',icon.source_page_url),sourceLink('品牌条款',icon.terms_url)); card.append(provenance);
      const feedback = element('p',null,'feedback'); feedback.setAttribute('role','status'); const button = element('button','下载 App 包','download'); button.setAttribute('aria-label',`下载 ${app.name} App 包`); button.addEventListener('click',() => download(app,button,feedback)); card.append(button,feedback); grid.append(card);
    }
    status.textContent = `${shown.length} / ${apps.length} 个 App · 预览快捷键库和支持系统`;
  }
  async function load() {
    const current = ++generation; apps = []; icons = new Map(); grid.replaceChildren(); retry.hidden = true; empty.hidden = true; status.textContent = '正在加载 App 目录…'; status.className = '';
    const controller = new AbortController(), timeout = setTimeout(() => controller.abort(),10000);
    try {
      const [catalog,artwork] = await Promise.all([request('/v1/apps/catalog',512*1024,controller.signal),request('/v1/icons/catalog',512*1024,controller.signal)]);
      if (!exact(catalog.data,['schemaVersion','version','apps']) || catalog.data.schemaVersion !== 1 || !safeText(catalog.data.version) || catalog.data.version.length > 80 || !Array.isArray(catalog.data.apps) || catalog.data.apps.length < 1 || catalog.data.apps.length > 256 || !catalog.data.apps.every(validApp) || !unique(catalog.data.apps.map(app => app.id.toLowerCase()))) throw Error('App 目录格式无效。');
      if (artwork.data.schema_version !== 1 || !Array.isArray(artwork.data.icons)) throw Error('图标目录格式无效。');
      const map = new Map(artwork.data.icons.filter(icon => validId(icon.app_id) && icon.canonical_id === icon.app_id && /^[a-f0-9]{64}$/.test(icon.sha256) && httpsLink(icon.source_page_url) && httpsLink(icon.terms_url)).map(icon => [icon.app_id,icon]));
      if (!unique(catalog.data.apps.flatMap(app => [app.id,...app.aliases]).map(value => value.toLowerCase())) || !unique(catalog.data.apps.flatMap(app => app.libraries.map(library => library.id))) || !catalog.data.apps.every(app => map.has(app.iconId))) throw Error('App 与图标目录不一致。');
      if (current !== generation) return; apps = catalog.data.apps; icons = map; render();
    } catch (error) { if (current === generation) { status.textContent = error.name === 'AbortError' ? '目录加载超时，请重试。' : error.message; status.className = 'error'; retry.hidden = false; } }
    finally { clearTimeout(timeout); }
  }
  search.addEventListener('input',render); os.addEventListener('change',render); retry.addEventListener('click',load);
  const appId = new URLSearchParams(location.search).get('app_id'); if (appId) search.value = appId;
  load();
})();

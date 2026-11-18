(() => {
  const grid = document.getElementById('grid');
  const search = document.getElementById('search');
  const status = document.getElementById('status');
  const empty = document.getElementById('empty');
  const retry = document.getElementById('retry');
  let icons = [];
  let loaded = false;
  let generation = 0;
  const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(value);
  const https = value => { try { return new URL(value).protocol === 'https:'; } catch (_) { return false; } };

  async function boundedBytes(response, maximum) {
    if (Number(response.headers.get('content-length')) > maximum) throw Error('资源大小超出限制。');
    const reader = response.body.getReader(); const chunks = []; let total = 0;
    try {
      while (true) {
        const {done, value} = await reader.read(); if (done) break;
        total += value.length; if (total > maximum) throw Error('资源大小超出限制。');
        chunks.push(value);
      }
    } finally { await reader.cancel(); }
    const bytes = new Uint8Array(total); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return bytes;
  }

  async function downloadIcon(icon, button, feedback) {
    button.disabled = true; feedback.textContent = '正在下载…';
    const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 10000);
    try {
      const url = new URL(`/v1/icons/${encodeURIComponent(icon.app_id)}`, location.origin);
      const response = await fetch(url, {signal: controller.signal, redirect: 'error'});
      if (!response.ok || response.url !== url.href || response.headers.get('content-type') !== 'image/png') throw Error('下载暂时不可用。');
      const bytes = await boundedBytes(response, 65536);
      if (bytes.length < 24 || ![137,80,78,71,13,10,26,10].every((byte, index) => bytes[index] === byte)) throw Error('图片格式无法识别。');
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), byte => byte.toString(16).padStart(2, '0')).join('');
      if (hash !== icon.sha256) throw Error('图标已更新，请重新加载目录。');
      const blob = new Blob([bytes], {type:'image/png'}); const image = await createImageBitmap(blob);
      try { if (image.width !== icon.width || image.height !== icon.height || image.width > 512 || image.height > 512) throw Error('图片尺寸无法识别。'); } finally { image.close(); }
      const href = URL.createObjectURL(blob); const anchor = document.createElement('a'); anchor.href = href; anchor.download = `${icon.app_id}.png`; anchor.click(); setTimeout(() => URL.revokeObjectURL(href), 1000);
      feedback.textContent = '下载已开始。'; button.textContent = '再次下载';
    } catch (error) {
      feedback.textContent = error.name === 'AbortError' ? '下载超时，请重试。' : error.message;
      button.textContent = '重试下载';
    } finally { clearTimeout(timer); button.disabled = false; }
  }

  function render() {
    if (!loaded) return;
    grid.replaceChildren();
    const query = search.value.trim().toLocaleLowerCase();
    const shown = icons.filter(icon => `${icon.app_id} ${icon.name} ${icon.aliases.join(' ')}`.toLocaleLowerCase().includes(query));
    empty.hidden = shown.length > 0;
    for (const icon of shown) {
      const card = document.createElement('article'); card.className = 'icon-card'; card.dataset.appId = icon.app_id;
      const preview = document.createElement('div'); preview.className = 'icon-preview';
      const loadPreview = () => {
        const image = document.createElement('img'); image.src = `/v1/icons/${encodeURIComponent(icon.app_id)}`; image.alt = `${icon.name} icon`; image.loading = 'lazy';
        image.addEventListener('error', () => {
          const fallback = document.createElement('button'); fallback.type = 'button'; fallback.className = 'preview-fallback'; fallback.textContent = '重试预览'; fallback.setAttribute('aria-label', `重试 ${icon.name} 预览`); fallback.addEventListener('click', loadPreview); preview.replaceChildren(fallback);
        }, {once:true}); preview.replaceChildren(image);
      }; loadPreview();
      const details = document.createElement('div'); details.className = 'icon-details';
      const name = document.createElement('h2'); name.textContent = icon.name;
      const id = document.createElement('code'); id.className = 'app-id'; id.textContent = icon.app_id;
      const badge = document.createElement('span'); badge.className = `badge ${icon.bundled ? 'bundled' : 'online'}`; badge.textContent = icon.bundled ? 'App 内置' : '在线扩展';
      details.append(name, id, badge);
      const meta = document.createElement('div'); meta.className = 'meta'; meta.textContent = `PNG · ${icon.width} × ${icon.height}`;
      const source = document.createElement('div'); source.className = 'source';
      for (const [title, url] of [['来源', icon.source_page_url], ['使用条款', icon.terms_url]]) {
        const link = document.createElement('a'); link.className = 'source-link'; link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer'; link.textContent = title; source.append(link);
      }
      const actions = document.createElement('div'); actions.className = 'actions';
      const feedback = document.createElement('p'); feedback.className = 'feedback'; feedback.setAttribute('role','status');
      const copy = document.createElement('button'); copy.type = 'button'; copy.className = 'copy-id'; copy.textContent = '复制 ID'; copy.setAttribute('aria-label', `复制 ${icon.app_id} App ID`);
      copy.addEventListener('click', async () => { try { await navigator.clipboard.writeText(icon.app_id); feedback.textContent = `已复制 ${icon.app_id}`; } catch (_) { feedback.textContent = `复制不可用，请手动复制：${icon.app_id}`; } });
      const download = document.createElement('button'); download.type = 'button'; download.className = 'download'; download.textContent = '下载 PNG'; download.setAttribute('aria-label', `下载 ${icon.name} PNG`); download.addEventListener('click', () => downloadIcon(icon, download, feedback));
      actions.append(copy, download); card.append(preview, details, meta, source, actions, feedback); grid.append(card);
    }
    status.textContent = `${shown.length} / ${icons.length} 个应用 · ${icons.filter(icon => icon.bundled).length} 个 App 内置 · ${icons.filter(icon => !icon.bundled).length} 个在线扩展`;
  }

  function validRecord(icon) {
    if (!icon || !validId(icon.app_id) || icon.canonical_id !== icon.app_id || typeof icon.name !== 'string' || typeof icon.bundled !== 'boolean' || icon.available !== true || !Array.isArray(icon.aliases) || !icon.aliases.every(validId)) return false;
    if (typeof icon.version !== 'string' || !/^[a-f0-9]{64}$/.test(icon.sha256) || !Number.isInteger(icon.width) || !Number.isInteger(icon.height) || icon.width < 1 || icon.height < 1 || icon.width > 512 || icon.height > 512) return false;
    if (!https(icon.source_page_url) || !https(icon.terms_url) || typeof icon.license !== 'string') return false;
    return icon.download_url === `/v1/icons/${encodeURIComponent(icon.app_id)}` && icon.mime_type === 'image/png';
  }

  async function loadCatalog() {
    const request = ++generation; loaded = false; icons = []; grid.replaceChildren(); empty.hidden = true; retry.hidden = true; retry.disabled = true;
    status.className = ''; status.textContent = '正在加载图标目录…';
    const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch('/v1/icons/catalog', {headers:{Accept:'application/json'}, cache:'no-store', signal:controller.signal, redirect:'error'});
      if (!response.ok || response.headers.get('content-type')?.split(';')[0] !== 'application/json') throw Error('目录暂时无法访问，请稍后重试。');
      const bytes = await boundedBytes(response, 512 * 1024); const data = JSON.parse(new TextDecoder().decode(bytes));
      if (data?.schema_version !== 1 || !Array.isArray(data.icons) || data.icons.length > 1000 || !data.icons.every(validRecord) || new Set(data.icons.map(icon => icon.app_id)).size !== data.icons.length) throw Error('目录数据格式无法识别。');
      if (request !== generation) return;
      icons = data.icons; loaded = true; render();
    } catch (error) {
      if (request !== generation) return;
      status.className = 'error'; status.textContent = error.name === 'AbortError' ? '加载超时，请重试。' : error.message; retry.hidden = false;
    } finally { clearTimeout(timeout); if (request === generation) retry.disabled = false; }
  }
  search.addEventListener('input', render); retry.addEventListener('click', loadCatalog);
  const requestedId = new URLSearchParams(location.search).get('app_id');
  if (requestedId?.toLowerCase() === 'codex') {
    search.value = 'chatgpt'; const notice = document.getElementById('legacy-notice'); notice.hidden = false; notice.textContent = '这是历史 LumiaKey 配置的 codex ID，兼容显示 ChatGPT 图标；不代表 Codex 产品图标。';
  } else if (requestedId) search.value = requestedId;
  loadCatalog();
})();

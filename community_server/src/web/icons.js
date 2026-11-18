(() => {
  const grid = document.getElementById('grid');
  const search = document.getElementById('search');
  const status = document.getElementById('status');
  const empty = document.getElementById('empty');
  const retry = document.getElementById('retry');
  let icons = [];
  let loaded = false;
  let generation = 0;

  function render() {
    if (!loaded) return;
    grid.replaceChildren();
    const query = search.value.trim().toLocaleLowerCase();
    const shown = icons.filter(icon => `${icon.app_id} ${icon.name} ${icon.canonical_id}`.toLocaleLowerCase().includes(query));
    empty.hidden = shown.length > 0;
    for (const icon of shown) {
      const card = document.createElement('article'); card.className = 'icon-card'; card.dataset.appId = icon.app_id;
      const preview = document.createElement('div'); preview.className = 'icon-preview';
      if (icon.available) {
        const image = document.createElement('img');
        image.src = icon.download_url; image.alt = `${icon.name} icon`; image.loading = 'lazy';
        image.addEventListener('error', () => { preview.replaceChildren(); const fallback = document.createElement('span'); fallback.className = 'preview-fallback'; fallback.textContent = '预览不可用'; preview.append(fallback); }, {once:true});
        preview.append(image);
      } else { preview.textContent = '暂无图标'; }
      const details = document.createElement('div'); details.className = 'icon-details';
      const name = document.createElement('h2'); name.textContent = icon.name;
      const id = document.createElement('code'); id.className = 'app-id'; id.textContent = icon.app_id;
      details.append(name, id);
      const meta = document.createElement('div'); meta.className = 'meta';
      meta.textContent = icon.available ? `格式：PNG · ${icon.license}` : '暂未登记可下载图标。请使用电脑上已安装应用的原生图标。';
      if (icon.app_id !== icon.canonical_id) { const alias = document.createElement('p'); alias.className = 'alias-note'; alias.textContent = `兼容旧 ID → ${icon.canonical_id}，不计为另一品牌。`; meta.append(alias); }
      if (icon.app_id === 'solidworks') { const quality = document.createElement('p'); quality.className = 'alias-note'; quality.textContent = '16×16 官方网站 favicon 降级图；优先使用已安装应用的原生图标。'; meta.append(quality); }
      const source = document.createElement('div'); source.className = 'source';
      if (icon.source) { const attribution = document.createElement('a'); attribution.className = 'source-link'; attribution.href = icon.source; attribution.target = '_blank'; attribution.rel = 'noopener noreferrer'; attribution.textContent = `来源：${new URL(icon.source).hostname}`; source.append(attribution); }
      if (icon.available) { const download = document.createElement('a'); download.className = 'download'; download.href = icon.download_url; download.download = `${icon.canonical_id}.png`; download.textContent = '下载 PNG'; download.setAttribute('aria-label', `下载 ${icon.name} PNG`); source.append(download); }
      card.append(preview, details, meta, source); grid.append(card);
    }
    const brands = new Set(icons.filter(icon => icon.available).map(icon => icon.canonical_id));
    status.textContent = `${shown.length} / ${icons.length} 个 App ID · ${brands.size} 种可下载图标`;
  }

  function validRecord(icon) {
    if (!icon || typeof icon.app_id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(icon.app_id) || typeof icon.name !== 'string' || typeof icon.canonical_id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(icon.canonical_id) || typeof icon.available !== 'boolean' || typeof icon.source !== 'string' || typeof icon.license !== 'string') return false;
    if (icon.source) { try { if (new URL(icon.source).protocol !== 'https:') return false; } catch (_) { return false; } }
    return icon.available ? icon.download_url === `/v1/icons/${encodeURIComponent(icon.app_id)}` && icon.mime_type === 'image/png' : icon.download_url === null && icon.mime_type === null;
  }

  async function loadCatalog() {
    const request = ++generation;
    loaded = false; icons = []; grid.replaceChildren(); empty.hidden = true; retry.hidden = true; retry.disabled = true;
    status.className = ''; status.textContent = '正在加载图标目录…';
    const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch('/v1/icons/catalog', {headers:{Accept:'application/json'}, cache:'no-store', signal:controller.signal});
      if (!response.ok) throw new Error('目录暂时无法访问，请稍后重试。');
      const data = await response.json();
      if (data?.schema_version !== 1 || !Array.isArray(data.icons) || data.icons.length > 1000 || !data.icons.every(validRecord) || new Set(data.icons.map(icon => icon.app_id)).size !== data.icons.length || !data.icons.every(icon => data.icons.some(canonical => canonical.app_id === icon.canonical_id))) throw new Error('目录数据格式无法识别。');
      if (request !== generation) return;
      icons = data.icons; loaded = true; render();
    } catch (error) {
      if (request !== generation) return;
      status.className = 'error'; status.textContent = error.name === 'AbortError' ? '加载超时，请重试。' : error.message;
      retry.hidden = false;
    } finally { clearTimeout(timeout); if (request === generation) retry.disabled = false; }
  }
  search.addEventListener('input', render); retry.addEventListener('click', loadCatalog);
  const requestedId = new URLSearchParams(location.search).get('app_id');
  if (requestedId) search.value = requestedId;
  loadCatalog();
})();
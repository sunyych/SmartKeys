(() => {
  const grid = document.getElementById('grid');
  const search = document.getElementById('search');
  const status = document.getElementById('status');
  const empty = document.getElementById('empty');
  let icons = [];

  function render() {
    grid.replaceChildren();
    const query = search.value.trim().toLocaleLowerCase();
    const shown = icons.filter(icon =>
      `${icon.app_id} ${icon.name}`.toLocaleLowerCase().includes(query));
    empty.hidden = shown.length > 0;
    for (const icon of shown) {
      const card = document.createElement('article');
      card.className = 'icon-card';
      const preview = document.createElement('div'); preview.className = 'icon-preview';
      const image = document.createElement('img');
      image.src = icon.download_url; image.alt = `${icon.name} icon`; image.loading = 'lazy';
      preview.append(image);
      const details = document.createElement('div'); details.className = 'icon-details';
      const name = document.createElement('h2'); name.textContent = icon.name;
      const id = document.createElement('code'); id.className = 'app-id'; id.textContent = icon.app_id;
      details.append(name, id);
      const meta = document.createElement('div'); meta.className = 'meta'; meta.textContent = `格式：${icon.mime_type} · ${icon.license}`;
      const source = document.createElement('div'); source.className = 'source';
      const attribution = document.createElement('span'); attribution.textContent = '来源：Simple Icons';
      const download = document.createElement('a'); download.className = 'download';
      download.href = icon.download_url; download.download = `${icon.app_id}.png`;
      download.textContent = '下载 PNG'; download.setAttribute('aria-label', `下载 ${icon.name} PNG`);
      source.append(attribution, download);
      card.append(preview, details, meta, source); grid.append(card);
    }
    status.textContent = `${shown.length} / ${icons.length} 个图标`;
  }

  search.addEventListener('input', render);
  const requestedId = new URLSearchParams(location.search).get('app_id');
  if (requestedId) search.value = requestedId;
  fetch('/v1/icons/catalog', {headers: {Accept: 'application/json'}, cache: 'no-store'})
    .then(response => {
      if (!response.ok) throw new Error('目录暂时无法访问，请稍后重试。');
      return response.json();
    })
    .then(data => {
      if (data?.schema_version !== 1 || !Array.isArray(data.icons) ||
          !data.icons.every(icon => typeof icon.app_id === 'string' &&
            typeof icon.name === 'string' && typeof icon.download_url === 'string' &&
            icon.download_url === `/v1/icons/${encodeURIComponent(icon.app_id)}` &&
            icon.mime_type === 'image/png')) {
        throw new Error('目录数据格式无法识别。');
      }
      icons = data.icons; render();
    })
    .catch(error => { status.className = 'error'; status.textContent = error.message; });
})();

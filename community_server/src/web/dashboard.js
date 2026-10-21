(() => {
  const ids = ["copy", "paste", "cut", "undo", "redo", "select_all", "save", "find", "new", "open", "print", "new_tab", "close_tab", "bold", "italic"];
  const labels = {copy:"复制",paste:"粘贴",cut:"剪切",undo:"撤销",redo:"重做",select_all:"全选",save:"保存",find:"查找",new:"新建",open:"打开",print:"打印",new_tab:"新建标签页",close_tab:"关闭标签页",bold:"粗体",italic:"斜体"};
  const period = document.getElementById("period"), tag = document.getElementById("tag"), experience = document.getElementById("experience");
  const status = document.getElementById("status"), updated = document.getElementById("updated"), rows = document.getElementById("rows"), chart = document.getElementById("chart");
  let controller = null, generation = 0;
  function clearResults() {
    for (const node of [rows, chart]) while (node.firstChild) node.removeChild(node.firstChild);
    document.getElementById("total-count").textContent = "—";
    document.getElementById("category-count").textContent = "—";
    document.getElementById("leader").textContent = "—";
    document.getElementById("leader-count").textContent = "按汇总计数排序";
  }
  function cell(row, text, className) {
    const td = document.createElement("td");
    if (className) td.className = className;
    td.textContent = text;
    row.appendChild(td);
  }
  function render(items) {
    const total = items.reduce((sum, item) => sum + item.count, 0);
    document.getElementById("total-count").textContent = total.toLocaleString("zh-CN");
    document.getElementById("category-count").textContent = items.length.toLocaleString("zh-CN");
    if (items.length) {
      document.getElementById("leader").textContent = labels[items[0].shortcut_id] || items[0].shortcut_id;
      document.getElementById("leader-count").textContent = `${items[0].count.toLocaleString("zh-CN")} 次汇总计数`;
    }
    const max = Math.max(1, ...items.map(item => item.count));
    items.forEach((item, index) => {
      const row = document.createElement("tr");
      cell(row, String(index + 1));
      cell(row, labels[item.shortcut_id] || item.shortcut_id);
      cell(row, item.count.toLocaleString("zh-CN"));
      cell(row, item.contributions.toLocaleString("zh-CN"));
      rows.appendChild(row);
      const barItem = document.createElement("div"); barItem.className = "bar-item";
      const value = document.createElement("span"); value.className = "bar-value"; value.textContent = item.count.toLocaleString("zh-CN");
      const track = document.createElement("div"); track.className = "bar-track";
      const bar = document.createElement("div"); bar.className = "bar"; bar.style.height = `${Math.max(3, Math.round(item.count / max * 100))}%`; bar.setAttribute("aria-label", `${labels[item.shortcut_id] || item.shortcut_id} ${item.count}`);
      const label = document.createElement("span"); label.className = "bar-label"; label.textContent = labels[item.shortcut_id] || item.shortcut_id;
      track.appendChild(bar); barItem.append(value, track, label); chart.appendChild(barItem);
    });
  }
  async function load() {
    const run = ++generation;
    if (controller) controller.abort();
    controller = new AbortController();
    clearResults();
    status.className = "status"; status.textContent = "正在加载排行榜…";
    const params = new URLSearchParams({period: period.value});
    if (tag.value) params.set("tag", tag.value);
    if (experience.value) params.set("experience", experience.value);
    try {
      const response = await fetch(`/v1/rankings?${params}`, {signal: controller.signal, headers: {Accept: "application/json"}, cache: "no-store"});
      const data = await response.json();
      if (run !== generation) return;
      if (response.status === 429) throw new Error("请求较频繁，请稍后再刷新。");
      if (!response.ok) throw new Error(response.status >= 500 ? "服务暂时无法访问，请稍后重试。" : "筛选条件无效，请调整后重试。");
      if (!Array.isArray(data.rankings)) throw new Error("服务返回了无法识别的数据。");
      render(data.rankings);
      const now = new Date();
      updated.textContent = `更新于 ${now.toLocaleTimeString("zh-CN", {hour:"2-digit", minute:"2-digit", second:"2-digit"})}`;
      status.className = data.rankings.length ? "status success" : "status";
      status.textContent = data.rankings.length ? "排行榜已更新。" : "当前筛选下暂无达到发布门槛的类别。";
    } catch (error) {
      if (error.name === "AbortError" || run !== generation) return;
      status.className = "status error";
      status.textContent = error.message || "网络连接失败，请检查服务后重试。";
    }
  }
  for (const control of [period, tag, experience]) control.addEventListener("change", load);
  document.getElementById("refresh").addEventListener("click", load);
  load();
})();

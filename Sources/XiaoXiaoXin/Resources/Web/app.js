const stocks = {
  "600183": { name: "生益科技", code: "600183.SH", price: 132.24, prev: 131.95 },
  "600519": { name: "贵州茅台", code: "600519.SH", price: 1428.50, prev: 1410.70 },
  "000001": { name: "平安银行", code: "000001.SZ", price: 11.72, prev: 11.61 },
  "300750": { name: "宁德时代", code: "300750.SZ", price: 205.36, prev: 207.10 },
};

const $ = (id) => document.getElementById(id);
const petWindow = $("petWindow");
const nativeBridge = window.webkit?.messageHandlers?.desktop;
let active = { ...stocks["600183"] };
let realPoints = null;
let timer;
let hasLivePrice = false;
let petClickTimer;
let idleTimer;

if (nativeBridge) {
  document.body.classList.add("native-app");
  petWindow.classList.add("collapsed");
}

function fmt(n) { return Number(n || 0).toLocaleString("zh-CN", { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }

function demoValues(rising) {
  const shape = [0, -.18, .06, -.12, .24, .41, .32, .58, .49, .74, .67, .91, .78, 1];
  return shape.map((v, i) => active.price + v * (rising ? 8 : -6) + Math.sin(i * 1.8));
}

function renderChart(values, rising) {
  const source = values?.length ? values : demoValues(rising);
  const min = Math.min(...source);
  const max = Math.max(...source);
  const spread = Math.max(max - min, Math.abs(active.price) * .001, .01);
  const points = source.map((value, index) => ({
    x: source.length === 1 ? 0 : index / (source.length - 1) * 520,
    y: 142 - (value - min) / spread * 108,
  }));
  const d = points.map((p, i) => `${i ? "L" : "M"}${p.x.toFixed(2)},${p.y.toFixed(2)}`).join(" ");
  $("linePath").setAttribute("d", d);
  $("areaPath").setAttribute("d", `${d} L520,155 L0,155 Z`);
  $("linePath").style.stroke = rising ? "#e85d54" : "#2a9c68";
  $("lastPoint").style.stroke = rising ? "#e85d54" : "#2a9c68";
  const last = points.at(-1);
  $("lastPoint").setAttribute("cx", last.x);
  $("lastPoint").setAttribute("cy", last.y);
}

function render(demoRefresh = false) {
  if (demoRefresh && !realPoints) active.price = Math.max(.01, active.price + (Math.random() - .42) * active.price * .0015);
  const delta = active.price - active.prev;
  const pct = active.prev ? delta / active.prev * 100 : 0;
  const rising = delta >= 0;
  $("stockName").textContent = active.name;
  $("stockCode").textContent = active.code;
  $("currentPrice").textContent = fmt(active.price);
  $("change").textContent = `${delta >= 0 ? "+" : ""}${fmt(delta)}  ${pct >= 0 ? "+" : ""}${pct.toFixed(2)}%`;
  $("change").className = rising ? "up" : "down";
  $("prevPrice").textContent = fmt(active.prev);
  $("speech").textContent = rising ? "今天也稳稳向前！" : "先喝口水，慢慢来。";
  renderChart(realPoints, rising);
  $("updateText").textContent = `${new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" })} 更新 · 自动刷新 20 秒`;
}

function requestMarketData() {
  const code = $("stockInput").value.trim().replace(/\D/g, "");
  if (!/^\d{6}$/.test(code)) {
    $("speech").textContent = "请输入六位股票代码～";
    return;
  }
  $("marketLabel").textContent = "A股 · 正在更新";
  $("miniStatus").textContent = "刷新中…";
  $("refreshButton").classList.add("spinning");
  nativeBridge.postMessage({ type: "quote", code });
}

function restartTimer() {
  clearInterval(timer);
  timer = setInterval(() => nativeBridge ? requestMarketData() : render(true), 20000);
}

function refresh() {
  $("refreshButton").classList.add("spinning");
  nativeBridge ? requestMarketData() : render(true);
  if (!nativeBridge) setTimeout(() => $("refreshButton").classList.remove("spinning"), 450);
  restartTimer();
}

function selectStock() {
  if (nativeBridge) {
    const query = $("stockInput").value.trim();
    if (/^\d{6}(\.(SH|SZ))?$/i.test(query)) requestMarketData();
    else if (query) {
      $("miniStatus").textContent = "搜索中…";
      nativeBridge.postMessage({ type: "search", query });
    }
    return;
  }
  const query = $("stockInput").value.trim().toUpperCase().replace(/\.(SH|SZ)$/, "");
  const found = stocks[query] || Object.values(stocks).find((item) => item.name.includes(query));
  if (!found) {
    $("speech").textContent = "浏览器原型暂时只准备了三个演示代码～";
    return;
  }
  active = { ...found };
  realPoints = null;
  render();
}

function toggleBoss() {
  if (nativeBridge) return nativeBridge.postMessage("boss");
  petWindow.classList.toggle("boss-hidden");
  document.querySelector(".notes").classList.toggle("boss-hidden");
}

function setCollapsed(collapsed) {
  petWindow.classList.toggle("collapsed", collapsed);
  nativeBridge?.postMessage(collapsed ? "collapse" : "expand");
}

window.applyMarketData = (data) => {
  const previousDisplayedPrice = active.price;
  active = { name: data.name, code: data.displayCode, price: data.price, prev: data.previousClose };
  if (data.points?.length) realPoints = data.points;
  render();
  $("openPrice").textContent = fmt(data.open);
  $("highPrice").textContent = fmt(data.high);
  $("lowPrice").textContent = fmt(data.low);
  $("marketLabel").textContent = `A股 · ${data.source || "延迟行情"}`;
  $("marketStatus").style.background = "#59a875";
  const time = new Date().toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  $("miniStatus").textContent = `${time} · ${data.source || "已更新"}`;
  $("refreshButton").classList.remove("spinning");
  if (hasLivePrice && data.price !== previousDisplayedPrice) reactToMarket(data.price > previousDisplayedPrice);
  hasLivePrice = true;
};

window.applyMarketError = (message) => {
  $("marketLabel").textContent = "A股 · 暂时失联";
  $("marketStatus").style.background = "#d59a45";
  $("speech").textContent = message || "行情暂时没有回应，再试一次吧。";
  $("miniStatus").textContent = "刷新失败 · 请重试";
  $("refreshButton").classList.remove("spinning");
};

window.applySearchResults = (results) => {
  const panel = $("searchResults");
  panel.replaceChildren();
  if (!results?.length) {
    $("miniStatus").textContent = "没有找到匹配股票";
    panel.classList.remove("open");
    return;
  }
  results.forEach((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("role", "option");
    const name = document.createElement("span");
    name.textContent = item.name;
    const code = document.createElement("small");
    code.textContent = item.displayCode;
    button.append(name, code);
    button.addEventListener("click", () => {
      $("stockInput").value = item.code;
      panel.classList.remove("open");
      requestMarketData();
    });
    panel.appendChild(button);
  });
  panel.classList.add("open");
  $("miniStatus").textContent = `找到 ${results.length} 个结果`;
};

function showPetSpeech(line, duration = 900) {
  const speech = $("speech");
  speech.textContent = line;
  speech.classList.add("interaction");
  setTimeout(() => speech.classList.remove("interaction"), duration);
}

function clearPetMotion() {
  document.querySelector(".pet").classList.remove("interacting", "concert", "market-up", "market-down");
}

function interactWithPet() {
  if (petWindow.classList.contains("collapsed")) return;
  const pet = document.querySelector(".pet");
  const lines = ["嗨！", "今天也加油～", "别忘了喝水", "行情我帮你看着", "摸鱼一下也没关系"];
  clearPetMotion();
  void pet.offsetWidth;
  pet.classList.add("interacting");
  showPetSpeech(lines[Math.floor(Math.random() * lines.length)]);
  setTimeout(clearPetMotion, 900);
}

function startConcert() {
  if (petWindow.classList.contains("collapsed")) return;
  const pet = document.querySelector(".pet");
  const band = $("concertBand");
  clearPetMotion();
  pet.style.opacity = "0";
  band.classList.remove("show");
  void band.offsetWidth;
  band.classList.add("show");
  showPetSpeech("五月天时间，来一小段～", 1800);
  const notes = ["♪", "♫", "♬", "♪"];
  notes.forEach((symbol, index) => {
    setTimeout(() => {
      const note = document.createElement("span");
      note.className = "note";
      note.textContent = symbol;
      note.style.setProperty("--drift", `${index % 2 ? 18 : -14}px`);
      note.style.right = `${10 + index * 7}px`;
      $("petEffects").appendChild(note);
      setTimeout(() => note.remove(), 1400);
    }, index * 260);
  });
  setTimeout(() => {
    band.classList.remove("show");
    pet.style.opacity = "";
    clearPetMotion();
  }, 2100);
}

function reactToMarket(isUp) {
  if (petWindow.classList.contains("collapsed")) return;
  const pet = document.querySelector(".pet");
  clearPetMotion();
  void pet.offsetWidth;
  pet.classList.add(isUp ? "market-up" : "market-down");
  const badge = document.createElement("span");
  badge.className = `move-badge ${isUp ? "up-move" : "down-move"}`;
  badge.textContent = isUp ? "↑" : "↓";
  $("petEffects").appendChild(badge);
  setTimeout(() => { clearPetMotion(); badge.remove(); }, 950);
}

function scheduleIdleMotion() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (!petWindow.classList.contains("collapsed")) interactWithPet();
    scheduleIdleMotion();
  }, 45000 + Math.random() * 30000);
}

$("refreshButton").addEventListener("click", refresh);
$("searchButton").addEventListener("click", selectStock);
$("stockInput").addEventListener("keydown", (event) => { if (event.key === "Enter") selectStock(); });
$("collapseButton").addEventListener("click", () => setCollapsed(true));
$("compactExpand").addEventListener("click", () => setCollapsed(false));
document.querySelector(".price-row").addEventListener("click", () => {
  if (nativeBridge && petWindow.classList.contains("collapsed")) setCollapsed(false);
});
document.querySelector(".pet").addEventListener("click", () => {
  clearTimeout(petClickTimer);
  petClickTimer = setTimeout(interactWithPet, 220);
});
document.querySelector(".pet").addEventListener("dblclick", () => {
  clearTimeout(petClickTimer);
  startConcert();
});
$("bossButton").addEventListener("click", toggleBoss);
document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.shiftKey && event.key.toLowerCase() === "h") {
    event.preventDefault();
    toggleBoss();
  }
});

render();
restartTimer();
if (nativeBridge) requestMarketData();
scheduleIdleMotion();

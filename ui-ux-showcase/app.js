const schemes = {
  tactical: {
    tabTitle: "方案 A · 战术协同",
    index: "01 / 03",
    label: "首选方向",
    title: "战术协同",
    score: "92",
    summary: "把“建队、分享口令、确认、匹配”压缩为一条清晰任务流，让队长始终知道下一步。",
    speed: "预估 +38%",
    coverage: "约 18%",
    cost: "中",
    audience: "固定队 / 高频玩家",
    kicker: "远征整备",
    problemTitle: "字段完整，但阅读层级不清",
    problemCopy: "完整保留模式、玩家、BOB、登录、AID、队伍、人数、匹配、启动和副本口令，仅用分行与色彩建立阅读顺序。",
    changes: ["状态与聊天分区并保持字段完整", "口令、反馈和聊天操作集中到同一面板", "返回与退出保持独立且可预期"],
    risk: "信息密度仍然偏高，需要用真实 1920×1080 战斗截图继续验证遮挡。",
    colors: { accent: "#d9b568", accent2: "#57b69f", page: "#0b0d0c" },
    world: { floor: "#14221b", stone: "#293a2f", path: "#4a543f", water: "#173c3a", light: "#d0a85b" }
  },
  immersive: {
    tabTitle: "方案 B · 沉浸远征",
    index: "02 / 03",
    label: "品牌升级方向",
    title: "沉浸远征",
    score: "86",
    summary: "让副本世界成为第一视觉层，将完整测试状态收进轻量侧页，兼顾信息浓度与场景可见度。",
    speed: "预估 +21%",
    coverage: "约 18%",
    cost: "高",
    audience: "剧情玩家 / 新玩家",
    kicker: "遗迹回响",
    problemTitle: "功能完整，但缺少游戏世界感",
    problemCopy: "不删减任何测试字段，通过更轻的边框、透明度和边缘布局降低面板存在感。",
    changes: ["中心画面优先，测试信息沿边缘分布", "状态字段仍按原有四行语义组织", "口令、五条聊天和操作结果完整保留"],
    risk: "需要更多高质量场景和任务素材，并重做较多动效与状态过渡，制作成本最高。",
    colors: { accent: "#d6a84e", accent2: "#75aa9c", page: "#0d0c09" },
    world: { floor: "#251e15", stone: "#443726", path: "#6b5a3d", water: "#254843", light: "#dfa84a" }
  },
  precision: {
    tabTitle: "方案 C · 竞技极简",
    index: "03 / 03",
    label: "低风险方向",
    title: "竞技极简",
    score: "89",
    summary: "用紧凑状态条和单一主操作减少视觉噪音，优先保证战斗中心净空与高频操作效率。",
    speed: "预估 +44%",
    coverage: "约 18%",
    cost: "低",
    audience: "竞技 / 高频 / 低配置",
    kicker: "快速部署",
    problemTitle: "高频玩家需要更快、更少干扰",
    problemCopy: "保持与另外两案完全相同的字段和五条聊天容量，只压缩留白并增强对齐，不隐藏详情。",
    changes: ["单色结构配合青色交互焦点", "完整测试状态压缩为边缘栅格", "聊天、反馈、返回与退出流程全部保留"],
    risk: "品牌表现较弱，对首次玩家的引导也更少，需要通过新手提示和首局渐进披露补足。",
    colors: { accent: "#eef2ef", accent2: "#52b8d0", page: "#0b0d0e" },
    world: { floor: "#182022", stone: "#303a3c", path: "#4e595b", water: "#19414a", light: "#75c5d7" }
  }
};

const partyMembers = [
  { avatar: "岚", name: "岚锋", role: "队长 · 近战", state: "已就绪" },
  { avatar: "拾", name: "拾光者", role: "恢复 · 辅助", state: "已就绪" },
  { avatar: "云", name: "云间客", role: "控制 · 远程", state: "已就绪" },
  { avatar: "+", name: "等待队员", role: "可通过口令加入", state: "空缺", waiting: true }
];

const state = {
  scheme: "immersive",
  mode: "battle",
  matching: false,
  elapsed: 0,
  timer: null,
  toastTimer: null
};

const stage = document.getElementById("game-stage");
const canvas = document.getElementById("world-canvas");
const context = canvas.getContext("2d", { alpha: false });
const partyList = document.getElementById("party-list");
const activityList = document.getElementById("activity-list");
const battleChatList = document.getElementById("battle-chat-list");
const toast = document.getElementById("toast");
const matchButton = document.getElementById("match-button");
const exitOverlay = document.getElementById("exit-confirm-overlay");
let exitTrigger = null;

function renderParty() {
  partyList.replaceChildren();
  partyMembers.forEach((member) => {
    const row = document.createElement("div");
    row.className = "party-member";

    const avatar = document.createElement("span");
    avatar.className = "member-avatar";
    avatar.textContent = member.avatar;

    const copy = document.createElement("div");
    const name = document.createElement("strong");
    const role = document.createElement("small");
    name.textContent = member.name;
    role.textContent = member.role;
    copy.append(name, role);

    const memberState = document.createElement("span");
    memberState.className = `member-state${member.waiting ? " wait" : ""}`;
    memberState.textContent = member.state;
    row.append(avatar, copy, memberState);
    partyList.append(row);
  });
}

function setText(id, value) {
  document.getElementById(id).textContent = value;
}

function renderScheme() {
  const scheme = schemes[state.scheme];
  stage.dataset.scheme = state.scheme;
  document.documentElement.style.setProperty("--accent", scheme.colors.accent);
  document.documentElement.style.setProperty("--accent-2", scheme.colors.accent2);
  document.documentElement.style.setProperty("--page", scheme.colors.page);

  setText("preview-title", scheme.tabTitle);
  setText("scheme-label", scheme.label);
  setText("evaluation-title", scheme.title);
  setText("scheme-summary", scheme.summary);
  setText("scheme-score", scheme.score);
  setText("metric-speed", scheme.speed);
  setText("metric-coverage", scheme.coverage);
  setText("metric-cost", scheme.cost);
  setText("metric-audience", scheme.audience);
  setText("game-kicker", scheme.kicker);
  setText("problem-title", scheme.problemTitle);
  setText("problem-copy", scheme.problemCopy);
  setText("risk-copy", scheme.risk);
  document.querySelector(".section-index").textContent = scheme.index;

  const changeList = document.getElementById("change-list");
  changeList.replaceChildren();
  scheme.changes.forEach((change) => {
    const item = document.createElement("li");
    item.textContent = change;
    changeList.append(item);
  });

  document.querySelectorAll(".scheme-tab").forEach((tab) => {
    tab.setAttribute("aria-selected", String(tab.dataset.scheme === state.scheme));
  });
  drawWorld();
}

function renderMode() {
  stage.dataset.mode = state.mode;
  const battle = state.mode === "battle";
  document.querySelectorAll(".mode-switch [data-mode]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.mode === state.mode));
  });

  setText("game-title", battle ? "暮潮遗迹 · 深层回廊" : "暮潮遗迹 · 私有副本");
  setText("objective-label", battle ? "当前作战目标" : "远征目标");
  setText("objective-text", battle ? "突破回廊并关闭潮汐阀" : "集结队员并确认挑战配置");
  setText("objective-progress", battle ? "02:47" : "准备阶段");
  drawWorld();
}

function formatTime(seconds) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, "0");
  const remainder = (seconds % 60).toString().padStart(2, "0");
  return `${minutes}:${remainder}`;
}

function updateMatchButton() {
  const label = document.getElementById("match-label");
  const hint = document.getElementById("match-hint");
  matchButton.classList.toggle("matching", state.matching);
  label.textContent = state.matching ? `取消匹配 · ${formatTime(state.elapsed)}` : "开始匹配";
  hint.textContent = state.matching ? "正在寻找 1 名合适队员" : "缺少 1 人时将自动补位";
  document.getElementById("battle-match-value").textContent = state.matching ? "匹配中" : "未匹配";
}

function toggleMatch() {
  state.matching = !state.matching;
  clearInterval(state.timer);
  state.timer = null;

  if (state.matching) {
    state.elapsed = 0;
    state.timer = window.setInterval(() => {
      state.elapsed += 1;
      updateMatchButton();
    }, 1000);
    announce("已进入匹配队列，可随时取消");
  } else {
    announce("匹配已取消，队伍保持不变");
  }
  updateMatchButton();
}

function announce(message) {
  clearTimeout(state.toastTimer);
  toast.textContent = message;
  toast.classList.add("show");
  state.toastTimer = window.setTimeout(() => toast.classList.remove("show"), 2600);
}

async function copyValue(value) {
  const isDungeonToken = value.includes("DNG-");
  try {
    await navigator.clipboard.writeText(value);
    announce(isDungeonToken ? `副本口令 ${value} 已复制` : "队伍口令 482 719 已复制");
  } catch {
    announce(isDungeonToken ? `副本口令：${value}` : "队伍口令：482 719");
  }
}

function resetDemo() {
  clearInterval(state.timer);
  state.matching = false;
  state.elapsed = 0;
  state.timer = null;
  state.scheme = "immersive";
  state.mode = "battle";
  document.getElementById("chat-input").value = "";
  document.getElementById("battle-chat-input").value = "";
  document.getElementById("lobby-notice-text").textContent = "等待消息";
  document.getElementById("battle-notice-text").textContent = "等待消息";
  exitOverlay.hidden = true;
  updateMatchButton();
  renderScheme();
  renderMode();
  announce("演示状态已重置");
}

function submitChat({ channel, inputId, list, noticeId }) {
  const input = document.getElementById(inputId);
  const notice = document.getElementById(noticeId);
  const message = input.value.trim();
  if (!message) {
    notice.textContent = `${channel}聊天：请输入消息`;
    announce("请输入测试消息");
    input.focus();
    return;
  }

  const item = document.createElement("li");
  const label = document.createElement("b");
  const content = document.createElement("span");
  label.textContent = channel;
  content.textContent = `岚锋：${message}`;
  item.append(label, content);
  list.append(item);
  while (list.children.length > 5) {
    list.firstElementChild.remove();
  }
  input.value = "";
  notice.textContent = `${channel}消息已发送`;
  announce(`${channel}消息已发送`);
}

function openExitConfirm(trigger) {
  exitTrigger = trigger;
  exitOverlay.hidden = false;
  exitOverlay.querySelector('[data-action="exit-cancel"]').focus();
}

function closeExitConfirm() {
  exitOverlay.hidden = true;
  if (exitTrigger) exitTrigger.focus();
}

function drawWorld() {
  const rect = stage.getBoundingClientRect();
  if (!rect.width || !rect.height) return;

  const scale = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.round(rect.width * scale);
  const height = Math.round(rect.height * scale);
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  context.setTransform(scale, 0, 0, scale, 0, 0);

  const palette = schemes[state.scheme].world;
  context.fillStyle = palette.floor;
  context.fillRect(0, 0, rect.width, rect.height);

  const tile = Math.max(44, rect.width / 22);
  context.lineWidth = 1;
  for (let y = -tile; y < rect.height + tile; y += tile) {
    for (let x = -tile; x < rect.width + tile; x += tile) {
      const offset = (Math.floor(y / tile) % 2) * tile * 0.5;
      const tone = 0.05 + ((Math.sin(x * 0.017 + y * 0.013) + 1) * 0.025);
      context.fillStyle = `rgba(220, 225, 211, ${tone})`;
      context.fillRect(x + offset + 1, y + 1, tile - 3, tile - 3);
      context.strokeStyle = "rgba(0, 0, 0, 0.16)";
      context.strokeRect(x + offset, y, tile, tile);
    }
  }

  context.save();
  context.translate(rect.width * 0.5, rect.height * 0.52);
  context.rotate(-0.08);
  context.fillStyle = palette.path;
  context.globalAlpha = 0.72;
  context.fillRect(-rect.width * 0.45, -58, rect.width * 0.9, 116);
  context.fillRect(-55, -rect.height * 0.42, 110, rect.height * 0.84);
  context.restore();

  const pools = [
    [0.12, 0.22, 0.12], [0.83, 0.24, 0.1], [0.18, 0.78, 0.14], [0.78, 0.76, 0.15]
  ];
  pools.forEach(([px, py, radius], index) => {
    const x = rect.width * px;
    const y = rect.height * py;
    const r = rect.width * radius;
    const gradient = context.createRadialGradient(x, y, r * 0.12, x, y, r);
    gradient.addColorStop(0, palette.water);
    gradient.addColorStop(0.68, `${palette.water}cc`);
    gradient.addColorStop(1, "rgba(0,0,0,0)");
    context.fillStyle = gradient;
    context.beginPath();
    context.ellipse(x, y, r, r * (0.46 + index * 0.03), index * 0.28, 0, Math.PI * 2);
    context.fill();
  });

  context.fillStyle = palette.stone;
  for (let i = 0; i < 38; i += 1) {
    const angle = i * 2.399;
    const distance = 80 + ((i * 73) % Math.max(120, rect.width * 0.42));
    const x = rect.width * 0.5 + Math.cos(angle) * distance;
    const y = rect.height * 0.5 + Math.sin(angle) * distance * 0.52;
    const size = 8 + (i % 5) * 3;
    context.beginPath();
    context.arc(x, y, size, 0, Math.PI * 2);
    context.fill();
  }

  const light = context.createRadialGradient(rect.width * 0.5, rect.height * 0.48, 0, rect.width * 0.5, rect.height * 0.48, rect.width * 0.28);
  light.addColorStop(0, `${palette.light}44`);
  light.addColorStop(1, "rgba(0,0,0,0)");
  context.fillStyle = light;
  context.fillRect(0, 0, rect.width, rect.height);

  const units = state.mode === "battle"
    ? [[0.46, 0.53, "#d7b85e"], [0.51, 0.49, "#62b8a0"], [0.55, 0.56, "#77a9c9"], [0.6, 0.43, "#b96359"], [0.64, 0.47, "#b96359"]]
    : [[0.47, 0.54, "#d7b85e"], [0.51, 0.51, "#62b8a0"], [0.54, 0.56, "#77a9c9"]];

  units.forEach(([px, py, color], index) => {
    const x = rect.width * px;
    const y = rect.height * py;
    context.fillStyle = "rgba(0,0,0,0.34)";
    context.beginPath();
    context.ellipse(x + 3, y + 8, 14, 7, 0, 0, Math.PI * 2);
    context.fill();
    context.fillStyle = color;
    context.beginPath();
    context.arc(x, y, index > 2 ? 9 : 11, 0, Math.PI * 2);
    context.fill();
    context.strokeStyle = "rgba(255,255,255,0.7)";
    context.lineWidth = 1.5;
    context.stroke();
  });
}

document.querySelectorAll(".scheme-tab").forEach((tab, index, tabs) => {
  tab.addEventListener("click", () => {
    state.scheme = tab.dataset.scheme;
    renderScheme();
  });
  tab.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    const offset = event.key === "ArrowRight" ? 1 : -1;
    const next = tabs[(index + offset + tabs.length) % tabs.length];
    next.focus();
    next.click();
  });
});

document.querySelectorAll(".mode-switch [data-mode]").forEach((button) => {
  button.addEventListener("click", () => {
    state.mode = button.dataset.mode;
    renderMode();
  });
});

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => {
    const action = button.dataset.action;
    if (action === "match") toggleMatch();
    if (action === "copy") copyValue(button.dataset.copyValue || "482719");
    if (action === "settings") announce("设置应采用侧边抽屉，避免离开当前任务");
    if (action === "ai") announce("已选择 AI 练习：正式产品应在按钮旁说明奖励差异");
    if (action === "lobby-team-chat") submitChat({ channel: "队伍", inputId: "chat-input", list: activityList, noticeId: "lobby-notice-text" });
    if (action === "lobby-world-chat") submitChat({ channel: "世界", inputId: "chat-input", list: activityList, noticeId: "lobby-notice-text" });
    if (action === "battle-team-chat") submitChat({ channel: "队伍", inputId: "battle-chat-input", list: battleChatList, noticeId: "battle-notice-text" });
    if (action === "battle-world-chat") submitChat({ channel: "世界", inputId: "battle-chat-input", list: battleChatList, noticeId: "battle-notice-text" });
    if (action === "return-lobby") announce("返回初始关卡请求已发送");
    if (action === "exit") openExitConfirm(button);
    if (action === "exit-cancel") closeExitConfirm();
    if (action === "exit-confirm") {
      closeExitConfirm();
      announce("退出请求已发送，匹配和组队状态将被清理");
    }
  });
});

document.getElementById("chat-form").addEventListener("submit", (event) => {
  event.preventDefault();
  submitChat({ channel: "队伍", inputId: "chat-input", list: activityList, noticeId: "lobby-notice-text" });
});

document.getElementById("battle-chat-form").addEventListener("submit", (event) => {
  event.preventDefault();
  submitChat({ channel: "队伍", inputId: "battle-chat-input", list: battleChatList, noticeId: "battle-notice-text" });
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !exitOverlay.hidden) {
    closeExitConfirm();
  }
});

document.getElementById("reset-demo").addEventListener("click", resetDemo);
new ResizeObserver(drawWorld).observe(stage);

renderParty();
renderScheme();
renderMode();
updateMatchButton();

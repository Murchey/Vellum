/* Vellum · 背景工作室 + 双击听书机制演示
   全部本地运行：图片仅用 FileReader 读进内存，不发任何网络请求。 */

// ---------- 背景工作室 ----------
const presets = {
  white: '#D7D7DB',
  sepia: '#F7E4CF',
  mint: '#C9DECB',
  blue: '#C2DEF0',
  charcoal: '#1A1A1A',
  night: '#262626',
};
const toneInk = {
  light: '#1c1917',
  dark: '#b7b7b7',
  standard: '#8c8c8c',
};

const screen = document.getElementById('bg-screen');
const ink = document.getElementById('bg-ink');
const dimmer = document.getElementById('bg-dimmer');
const eyeLayer = document.getElementById('bg-eyecare');
const stateOut = document.getElementById('bg-state');

const bgState = {
  kind: 'preset',
  presetId: 'sepia',
  colorValue: null,
  imageFileName: null,
  tone: 'light',
  brightness: -1,
  eyeCare: false,
};
let imageUrl = null;

function luminanceOf(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

function suggestTone() {
  if (bgState.kind === 'preset') {
    return bgState.presetId === 'night' || bgState.presetId === 'charcoal'
      ? 'dark'
      : 'light';
  }
  if (bgState.kind === 'color') {
    return luminanceOf(bgState.colorValue || '#ffffff') < 0.45 ? 'dark' : 'light';
  }
  return bgState.tone; // 图片由用户定槽位（番茄 ReaderBgColorType 同思路）
}

function render() {
  // 背景层：纯色或本地图（cover）
  if (bgState.kind === 'image' && imageUrl) {
    screen.style.background = `#000 url("${imageUrl}") center/cover no-repeat`;
  } else if (bgState.kind === 'color') {
    screen.style.background = bgState.colorValue;
  } else {
    screen.style.background = presets[bgState.presetId];
  }
  // 墨色槽位
  ink.style.color = toneInk[bgState.tone];
  // 亮度：窗口级覆盖的等价模拟（-1 跟随系统 → 无遮罩）
  dimmer.style.opacity = bgState.brightness < 0 ? 0 : (1 - bgState.brightness) * 0.8;
  // 护眼：alpha 0.15 覆盖层（番茄 getEyeProtectedView）
  eyeLayer.style.opacity = bgState.eyeCare ? 0.15 : 0;
  // 配置回显（与 ReaderBackground.toJson 同构）
  stateOut.textContent = [
    `kind: ${bgState.kind}`,
    `presetId: ${bgState.kind === 'preset' ? bgState.presetId : '—'}`,
    `colorValue: ${bgState.colorValue ?? '—'}`,
    `imageFileName: ${bgState.imageFileName ?? '—'}`,
    `tone: ${bgState.tone}`,
    `brightness: ${bgState.brightness < 0 ? '-1 (跟随系统)' : bgState.brightness.toFixed(2)}`,
    `eyeCare: ${bgState.eyeCare}`,
  ].join('\n');
}

document.querySelectorAll('#preset-dots .dot').forEach((dot) => {
  dot.addEventListener('click', () => {
    document.querySelectorAll('#preset-dots .dot').forEach((d) => d.classList.remove('on'));
    dot.classList.add('on');
    bgState.kind = 'preset';
    bgState.presetId = dot.dataset.preset;
    bgState.imageFileName = null;
    bgState.tone = suggestTone();
    document.getElementById('tone-select').value = bgState.tone;
    render();
  });
});

document.getElementById('custom-color').addEventListener('input', (e) => {
  bgState.kind = 'color';
  bgState.colorValue = e.target.value;
  bgState.imageFileName = null;
  document.querySelectorAll('#preset-dots .dot').forEach((d) => d.classList.remove('on'));
  bgState.tone = suggestTone();
  document.getElementById('tone-select').value = bgState.tone;
  render();
});

document.getElementById('custom-image').addEventListener('change', (e) => {
  const file = e.target.files && e.target.files[0];
  if (!file) return;
  // 本地读取，不上传（对应建议：复制进应用私有 backgrounds/ 目录）
  const reader = new FileReader();
  reader.onload = () => {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    imageUrl = reader.result;
    bgState.kind = 'image';
    bgState.imageFileName = file.name;
    document.querySelectorAll('#preset-dots .dot').forEach((d) => d.classList.remove('on'));
    render();
  };
  reader.readAsDataURL(file);
});

document.getElementById('tone-select').addEventListener('change', (e) => {
  bgState.tone = e.target.value;
  render();
});

document.getElementById('brightness').addEventListener('input', (e) => {
  const v = Number(e.target.value);
  bgState.brightness = v >= 100 ? -1 : v / 100;
  render();
});

document.getElementById('eyecare').addEventListener('change', (e) => {
  bgState.eyeCare = e.target.checked;
  render();
});

document.querySelector('#preset-dots .dot[data-preset="sepia"]').classList.add('on');
render();

// ---------- 双击听书机制演示 ----------
const source = document.getElementById('tts-source');
const subtitle = document.getElementById('tts-subtitle');
const posOut = document.getElementById('tts-pos');
const playBtn = document.getElementById('tts-play');
const speedBtn = document.getElementById('tts-speed');
const hint = document.querySelector('#tts-phone .hint');

const rawText = source.textContent.trim();
// 句界断句 ≈ 番茄 libtokenizer.so 的 Dart 近似（中文句末标点 + 收尾引号）
const sentences = rawText
  .split(/(?<=[。！？!?…；;][”’"')\]]?)/)
  .map((s) => s.trim())
  .filter(Boolean);

source.innerHTML = '';
const spans = sentences.map((sentence, index) => {
  const span = document.createElement('span');
  span.textContent = sentence;
  span.dataset.index = String(index);
  source.appendChild(span);
  source.appendChild(document.createTextNode(' '));
  return span;
});

const tts = {
  index: -1,
  playing: false,
  rate: 1,
  timer: null,
};
const speeds = [0.75, 1, 1.25, 1.5, 2];
const synth = window.speechSynthesis || null;

function highlight(i) {
  spans.forEach((s) => s.classList.remove('spoken'));
  if (i < 0 || i >= spans.length) return;
  spans[i].classList.add('spoken');
  subtitle.textContent = sentences[i];
  posOut.textContent = `${i + 1} / ${spans.length}`;
}

function speak(i) {
  stopSpeech();
  if (i < 0 || i >= spans.length) return;
  tts.index = i;
  tts.playing = true;
  playBtn.textContent = '⏸';
  highlight(i);
  const text = sentences[i];
  if (synth) {
    const u = new SpeechSynthesisUtterance(text);
    u.lang = 'zh-CN';
    u.rate = tts.rate;
    u.onend = () => {
      if (!tts.playing) return;
      if (tts.index + 1 < spans.length) speak(tts.index + 1);
      else closeTts();
    };
    synth.speak(u);
  } else {
    // 降级：定时模拟（无 speechSynthesis 的浏览器）
    tts.timer = setTimeout(() => {
      if (!tts.playing) return;
      if (tts.index + 1 < spans.length) speak(tts.index + 1);
      else closeTts();
    }, Math.max(1200, text.length * 180 / tts.rate));
  }
}

function stopSpeech() {
  if (synth) synth.cancel();
  if (tts.timer) { clearTimeout(tts.timer); tts.timer = null; }
}

function pauseTts() {
  tts.playing = false;
  playBtn.textContent = '▶';
  stopSpeech();
  subtitle.textContent = '已暂停 · ' + (sentences[tts.index] || '');
}

function closeTts() {
  tts.playing = false;
  stopSpeech();
  playBtn.textContent = '▶';
  spans.forEach((s) => s.classList.remove('spoken'));
  tts.index = -1;
  subtitle.textContent = '字幕行 · 当前句显示在这里';
  posOut.textContent = '— / —';
  if (hint) hint.textContent = '双击句子开始听书';
}

playBtn.addEventListener('click', () => {
  if (tts.playing) { pauseTts(); return; }
  speak(tts.index < 0 ? 0 : tts.index);
  if (hint) hint.textContent = '播放中 · 单击动作延迟 200ms 分派';
});
document.getElementById('tts-prev').addEventListener('click', () => {
  if (tts.index > 0) speak(tts.index - 1);
});
document.getElementById('tts-next').addEventListener('click', () => {
  if (tts.index + 1 < spans.length) speak(tts.index + 1);
});
document.getElementById('tts-close').addEventListener('click', closeTts);
speedBtn.addEventListener('click', () => {
  const next = speeds[(speeds.indexOf(tts.rate) + 1) % speeds.length];
  tts.rate = next;
  speedBtn.textContent = '×' + next.toFixed(2);
  if (tts.playing) speak(tts.index);
});

// 双击窗口分派（番茄：200ms 窗口，单击延迟到窗口结束）
const DOUBLE_MS = 200;
const DOUBLE_SLOP = 24;
let clickTimer = null;
let lastClickAt = 0;
let lastX = 0, lastY = 0;

function sentenceIndexFrom(target) {
  let node = target;
  while (node && node !== source) {
    if (node.dataset && node.dataset.index != null) return Number(node.dataset.index);
    node = node.parentNode;
  }
  return -1;
}

source.addEventListener('click', (e) => {
  const now = Date.now();
  const near = Math.abs(e.clientX - lastX) < DOUBLE_SLOP && Math.abs(e.clientY - lastY) < DOUBLE_SLOP;
  const index = sentenceIndexFrom(e.target);
  lastClickAt = now;
  lastX = e.clientX; lastY = e.clientY;
  if (clickTimer && near) {
    // 窗口内第二次命中 → 取消单击，执行双击听书
    clearTimeout(clickTimer);
    clickTimer = null;
    if (index >= 0) {
      if (hint) hint.textContent = '双击 → 朗读该句（200ms 窗口命中）';
      speak(index);
    }
    return;
  }
  // 单击延迟到窗口结束再分派（翻页 / 呼出菜单的等价动作）
  clearTimeout(clickTimer);
  clickTimer = setTimeout(() => {
    clickTimer = null;
    if (hint) hint.textContent = '单击已延迟 200ms 分派 · 双击句子开始听书';
  }, DOUBLE_MS);
});
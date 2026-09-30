/**
 * 小说模式：段首两格缩进 + 段落之间空一行。
 * 与 Flutter 侧 applyNovelFormatting 规则一致。
 */

const SAMPLE = `他走进旧书店的时候，雨刚停。
玻璃上的水痕把街灯揉成一团模糊的光。

老板娘从账本后面抬起头，只说了三个字：“在楼下。”
他道了谢，顺着吱呀作响的木梯往下。

角落里那本书没有书名。
他翻开第一页，上面只写了一行字：\n「别在雨停之后回头看。」`;

const editor = document.getElementById('editor');
const preview = document.getElementById('preview');
const stat = document.getElementById('stat');

function isSkipLine(line) {
  return /^(#{1,6}\s|>|[-*+]\s|\d+[.、)]\s|```|~~~)/.test(line) ||
    line.startsWith('　') ||
    /^ {2,}/.test(line) ||
    line.startsWith('\t');
}

function applyNovelFormatting(source) {
  const normalized = source.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const lines = normalized.split('\n');
  const out = [];
  let inFence = false;
  let buffer = [];

  const flush = () => {
    if (!buffer.length) return;
    const first = buffer[0];
    const body = buffer.join('\n');
    buffer = [];
    const isProse =
      first.trim().length > 0 &&
      !isSkipLine(first);
    out.push(isProse ? '　　' + body : body);
    out.push('');
  };

  for (const line of lines) {
    if (line.trim().startsWith('```')) {
      flush();
      inFence = !inFence;
      out.push(line);
      continue;
    }
    if (inFence) {
      out.push(line);
      continue;
    }
    if (!line.trim()) {
      flush();
      continue;
    }
    buffer.push(line);
  }
  flush();

  return out
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function renderPreview(text) {
  const blocks = text.split(/\n{2,}/);
  preview.innerHTML = blocks
    .map((block) => {
      const flush = /^(#{1,6}\s|>|[-*+]|\d+[.、)])/m.test(block.trim()) ||
        block.trim().startsWith('　　') === false && /^(#{1,6}\s|>)/.test(block.trim());
      const cls = isSkipLine(block.split('\n')[0] || '') ? 'flush' : '';
      return `<p class="${cls}">${escapeHtml(block)}</p>`;
    })
    .join('');
}

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function refresh(source) {
  renderPreview(source);
  const paras = source.split(/\n{2,}/).filter((p) => p.trim()).length;
  stat.textContent = `${paras} 段 · ${source.length} 字`;
}

function applyNovel() {
  const next = applyNovelFormatting(editor.value);
  editor.value = next;
  refresh(next);
  stat.textContent = '已套用小说模式';
}

function resetSample() {
  editor.value = SAMPLE;
  refresh(SAMPLE);
  stat.textContent = '已恢复示例';
}

document.getElementById('btn-novel').addEventListener('click', applyNovel);
document.getElementById('btn-reset').addEventListener('click', resetSample);
editor.addEventListener('input', () => refresh(editor.value));

editor.value = SAMPLE;
refresh(SAMPLE);

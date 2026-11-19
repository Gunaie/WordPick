/**
 * 词库数据构建脚本
 *
 * 输入：有道考神词书 JSONL（每行一个单词对象）
 * 输出：assets/data/words.json（合并去重后的词库）
 *
 * 用法：
 *   node scripts/build_word_assets.js <输入目录> [输出目录]
 *   输入目录需包含：CET4_3.json / CET6_3.json / KaoYan_3.json
 */

const fs = require('fs');
const path = require('path');

const BOOKS = [
  { file: 'CET4_3.json', tag: 'cet4' },
  { file: 'CET6_3.json', tag: 'cet6' },
  { file: 'KaoYan_3.json', tag: 'kaoyan' },
];

const inputDir = process.argv[2];
const outputDir = process.argv[3] || path.join(__dirname, '..', 'assets', 'data');

if (!inputDir) {
  console.error('用法: node scripts/build_word_assets.js <输入目录> [输出目录]');
  process.exit(1);
}

const merged = new Map();

function pick(obj, keys) {
  if (!obj) return undefined;
  for (const k of keys) {
    if (obj[k] !== undefined && obj[k] !== null && obj[k] !== '') return obj[k];
  }
  return undefined;
}

for (const book of BOOKS) {
  const filePath = path.join(inputDir, book.file);
  if (!fs.existsSync(filePath)) {
    console.warn(`[跳过] 未找到 ${book.file}`);
    continue;
  }

  const lines = fs.readFileSync(filePath, 'utf8').split('\n').filter((l) => l.trim());
  let ok = 0;

  for (const line of lines) {
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue;
    }

    const head = rec.headWord || rec.content?.word?.wordHead;
    const c = rec.content?.word?.content;
    if (!head || !c) continue;

    const key = head.toLowerCase();
    let item = merged.get(key);
    if (!item) {
      item = {
        w: head,
        uk: c.ukphone || '',
        us: c.usphone || '',
        defs: [],
        ex: [],
        phr: [],
        rel: [],
        syn: [],
        quiz: [],
        tags: [],
      };
      merged.set(key, item);
    }

    if (!item.uk && c.ukphone) item.uk = c.ukphone;
    if (!item.us && c.usphone) item.us = c.usphone;
    if (!item.tags.includes(book.tag)) item.tags.push(book.tag);

    // 释义：中文 + 英文解释
    for (const t of c.trans || []) {
      const def = {
        pos: t.pos || '',
        cn: (t.tranCn || '').trim(),
        en: (t.tranOther || '').trim(),
      };
      if (!def.cn && !def.en) continue;
      const dup = item.defs.some((d) => d.cn === def.cn && d.pos === def.pos);
      if (!dup) item.defs.push(def);
    }

    // 例句
    for (const s of c.sentence?.sentences || []) {
      const en = (s.sContent || '').trim();
      const cn = (s.sCn || '').trim();
      if (!en) continue;
      if (!item.ex.some((e) => e.en === en)) item.ex.push({ en, cn });
    }

    // 短语
    for (const p of c.phrase?.phrases || []) {
      const en = (p.pContent || '').trim();
      const cn = (p.pCn || '').trim();
      if (!en) continue;
      if (!item.phr.some((x) => x.en === en)) item.phr.push({ en, cn });
    }

    // 同根词（派生树基础）
    for (const rel of c.relWord?.rels || []) {
      for (const w of rel.words || []) {
        const hwd = (w.hwd || '').trim();
        if (!hwd) continue;
        if (!item.rel.some((x) => x.w === hwd)) {
          item.rel.push({ pos: rel.pos || '', w: hwd, cn: (w.tran || '').trim() });
        }
      }
    }

    // 同义词（近义辨析基础）
    for (const syn of c.syno?.synos || []) {
      const words = (syn.hwds || []).map((h) => h.w).filter(Boolean);
      if (!words.length) continue;
      item.syn.push({ pos: syn.pos || '', cn: (syn.tran || '').trim(), words });
    }

    // 考试练习题（源数据无年份/试卷出处，界面上如实标注为「考试练习」）
    for (const e of c.exam || []) {
      const q = (e.question || '').trim();
      const raw = e.choices || [];
      const options = raw.map((x) => (x.choice || '').trim()).filter(Boolean);
      if (!q || options.length < 2) continue;

      const rightChoiceIndex = e.answer?.rightIndex;
      let answerIndex = raw.findIndex((x) => x.choiceIndex === rightChoiceIndex);
      if (answerIndex < 0) answerIndex = Math.max(0, (rightChoiceIndex || 1) - 1);
      if (answerIndex >= options.length) answerIndex = 0;

      if (!item.quiz.some((x) => x.q === q)) {
        item.quiz.push({
          q,
          o: options,
          a: answerIndex,
          e: (e.answer?.explain || '').trim(),
        });
      }
    }

    ok++;
  }

  console.log(`${book.file}: 读取 ${lines.length} 行，有效 ${ok}`);
}

// 限制单条数据量，避免资源过大
const LIMIT = { ex: 3, phr: 4, rel: 6, syn: 3, quiz: 3 };
const words = [];
for (const item of merged.values()) {
  item.defs = item.defs.slice(0, 8);
  item.ex = item.ex.slice(0, LIMIT.ex);
  item.phr = item.phr.slice(0, LIMIT.phr);
  item.rel = item.rel.slice(0, LIMIT.rel);
  item.syn = item.syn.slice(0, LIMIT.syn);
  item.quiz = item.quiz.slice(0, LIMIT.quiz);
  words.push(item);
}

words.sort((a, b) => a.w.toLowerCase().localeCompare(b.w.toLowerCase()));

fs.mkdirSync(outputDir, { recursive: true });
const outFile = path.join(outputDir, 'words.json');
fs.writeFileSync(outFile, JSON.stringify(words), 'utf8');

const stat = fs.statSync(outFile);
const withAudio = words.filter((w) => w.uk || w.us).length;
const withEx = words.filter((w) => w.ex.length).length;
const withRel = words.filter((w) => w.rel.length).length;
const withQuiz = words.filter((w) => w.quiz.length).length;
const quizTotal = words.reduce((n, w) => n + w.quiz.length, 0);

console.log('---');
console.log(`总词条: ${words.length}`);
console.log(`有音标: ${withAudio} | 有例句: ${withEx} | 有同根词: ${withRel}`);
console.log(`有考试练习: ${withQuiz} 词 / 共 ${quizTotal} 题`);
console.log(`输出: ${outFile} (${(stat.size / 1024 / 1024).toFixed(2)} MB)`);

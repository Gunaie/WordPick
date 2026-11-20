/**
 * 生成离线词典 assets/data/dict_core.json
 *
 * 数据源：qwerty-learner 的公开词书（基于 ECDICT 等词库整理），
 * 仅个人自用；分发前需再核验词条授权。
 *
 * 用法：node scripts/build_dict_assets.js
 * 产物：{"word":["音标","中文释义"], ...}
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const BASE_URL =
  'https://cdn.jsdelivr.net/gh/RealKai42/qwerty-learner@master/public/dicts/';

/** 优先级从高到低：前面的词条质量更好，重复词只补空音标 */
const SOURCES = [
  'Oxford5000.json',
  'CET4_T.json',
  'CET6_T.json',
  'KaoYan_2024.json',
  'TOEFL_3_T.json',
  'IELTS_3_T.json',
  'GRE_3_T.json',
];

const CJK = /[\u4e00-\u9fff]/;
const META_LINE =
  /^(时态|名词|形容词|副词|动词|过去式|过去分词|现在分词|复数|比较级|最高级)[:：]/;
const WORD_RE = /^[a-z][a-z'\- .]*$/;
const MAX_TRANSLATION = 110;

const cacheDir = path.join(os.tmpdir(), 'ecdict-core-cache');
const outFile = path.join(__dirname, '..', 'assets', 'data', 'dict_core.json');

async function download(name) {
  fs.mkdirSync(cacheDir, { recursive: true });
  const file = path.join(cacheDir, name);
  if (fs.existsSync(file) && fs.statSync(file).size > 0) return file;

  const res = await fetch(BASE_URL + name);
  if (!res.ok) throw new Error(`下载失败 ${name}: HTTP ${res.status}`);
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  return file;
}

function cleanTranslation(raw) {
  const lines = [].concat(raw || [])
    .flatMap((t) => String(t).split(/\n+/))
    .map((s) => s.trim())
    .filter((s) => s && !META_LINE.test(s));

  let text = lines
    .join('；')
    .replace(/\s*also\s+[\s\S]*$/i, '')
    .replace(
      /\s*(时态|名词|形容词|副词|动词|过去式|过去分词|现在分词|复数|比较级|最高级)[:：][\s\S]*$/g,
      '',
    )
    .replace(/\s+/g, ' ')
    .replace(/([\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])/g, '$1')
    .replace(/([，。；：、！？])\s+/g, '$1')
    .replace(/\s+([，。；：、！？])/g, '$1')
    .replace(/；{2,}/g, '；')
    .replace(/^[；;，,]+|[；;，,]+$/g, '')
    .trim();

  if (text.length > MAX_TRANSLATION) {
    text = `${text.slice(0, MAX_TRANSLATION)}…`;
  }
  return text;
}

async function main() {
  const entries = new Map();

  for (const name of SOURCES) {
    const file = await download(name);
    const list = JSON.parse(fs.readFileSync(file, 'utf8'));
    let kept = 0;

    for (const item of list) {
      const word = String(item.name || '').trim().toLowerCase();
      const translation = cleanTranslation(item.trans);
      if (!word || !WORD_RE.test(word) || !CJK.test(translation)) continue;

      const phonetic = String(item.ukphone || item.usphone || '').trim();
      const old = entries.get(word);
      if (!old) {
        entries.set(word, [phonetic, translation]);
        kept += 1;
      } else if (!old[0] && phonetic) {
        old[0] = phonetic;
      }
    }

    console.log(`${name}: ${list.length} 条，新增 ${kept} 条`);
  }

  const data = {};
  for (const word of [...entries.keys()].sort()) {
    data[word] = entries.get(word);
  }

  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  const json = JSON.stringify(data);
  fs.writeFileSync(outFile, json);

  console.log(
    `共 ${Object.keys(data).length} 词，${(json.length / 1024 / 1024).toFixed(2)} MB -> ${outFile}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

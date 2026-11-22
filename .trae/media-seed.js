// 「拾词」演示数据生成器：日期按运行当天计算，保证截图里是"今天"的状态。
// 由 .trae/media-demo.json 的 storage.module 引用，返回 { localStorage键: 值 }。
module.exports = function buildSeed() {
  const pad = (n) => String(n).padStart(2, '0');
  const day = (offset) => {
    const d = new Date();
    d.setDate(d.getDate() + offset);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  };
  const iso = (offset, hour = 9) => {
    const d = new Date();
    d.setDate(d.getDate() + offset);
    d.setHours(hour, 0, 0, 0);
    return d.toISOString();
  };

  // -part 词根家族：方便展示词根笔记与易混词组
  const words = [
    ['whip', 'wɪp', 'v.', '抽打'],
    ['impart', 'ɪmˈpɑːt', 'v.', '传达，传授'],
    ['impartial', 'ɪmˈpɑːʃl', 'adj.', '公正的'],
    ['departure', 'dɪˈpɑːtʃə', 'n.', '离开，出发'],
    ['department', 'dɪˈpɑːtmənt', 'n.', '部门'],
    ['apartment', 'əˈpɑːtmənt', 'n.', '公寓'],
    ['terrace', 'ˈterəs', 'n.', '露台；梯田'],
    ['ranch', 'rɑːntʃ', 'n.', '大牧场'],
    ['particle', 'ˈpɑːtɪkl', 'n.', '微粒，粒子'],
    ['apart', 'əˈpɑːt', 'adv.', '相距；除外'],
    ['compartment', 'kəmˈpɑːtmənt', 'n.', '车厢；隔间'],
    ['partition', 'pɑːˈtɪʃn', 'n.', '隔板；分割'],
    ['disputable', 'dɪˈspjuːtəbl', 'adj.', '有争议的'],
  ];

  const books = [{
    id: 'book-ielts-core',
    name: '雅思核心词',
    created_at: iso(-20),
    words: words.map(([w, ipa, pos, cn], i) => ({
      w, uk: ipa, us: ipa,
      defs: [{ pos, cn, en: '' }],
      tags: ['雅思'],
      added_at: iso(-15 + Math.floor(i / 4)),
      add_count: 1,
    })),
  }];

  // 一半今天到期、一半逾期，首页才会出现「开始复习」
  const dueKeys = ['impartial', 'departure', 'terrace', 'particle', 'compartment', 'disputable'];
  const reviews = {};
  dueKeys.forEach((k, i) => {
    reviews[k] = {
      ease: 2.5,
      interval: 3 + i,
      reps: 3 + i,
      lapses: i % 2,
      due: iso(i < 2 ? 0 : -1 - i, 1),
      updated_at: iso(i < 2 ? 0 : -2 - i, 20),
    };
  });

  const daily = {};
  [12, 8, 15, 6, 20, 10, 14, 9, 18, 7, 11, 16, 13, 12].forEach((r, i) => {
    daily[day(i - 13)] = { r, n: 3 + (i % 4) };
  });

  const notes = [
    {
      id: 'note-part-root',
      word_key: '',
      title: 'part 词根：分开与部分',
      content: '## part = 部分 / 分开\n\n- **impart**：把知识分给别人 → 传授\n- **partition**：把空间分开 → 隔板\n- **particle**：一小部分 → 微粒\n\n> 记住：part 家族都围绕"分开、部分"。',
      tags: ['词根', '雅思'],
      created_at: iso(-3, 10),
      updated_at: iso(0, 9),
      deleted: false,
    },
    {
      id: 'note-confusable',
      word_key: '',
      title: '易混词对比：apartment / compartment',
      content: '### 区别\n\n| 单词 | 含义 |\n| --- | --- |\n| apartment | 公寓（住人） |\n| compartment | 车厢、隔间（分格） |\n\n两个词都来自 part，但使用场景不同。',
      tags: ['易混词'],
      created_at: iso(-2, 11),
      updated_at: iso(-1, 21),
      deleted: false,
    },
    {
      id: 'note-today',
      word_key: '',
      title: '今日复盘',
      content: '今天重点复习了 **-part 家族**，四选一错 1 个，拼写全对。\n\n明天继续：`departure`、`partition`。',
      tags: ['复盘'],
      created_at: iso(0, 8),
      updated_at: iso(0, 12),
      deleted: false,
    },
  ];

  const confusable = [{
    id: 'group-part',
    name: '-part 家族',
    word_keys: ['impart', 'impartial', 'departure', 'department', 'apartment', 'apart', 'compartment', 'partition', 'particle'],
    created_at: iso(-10),
  }];

  return {
    es_books_v1: books,
    es_review_v1: reviews,
    es_daily_v1: daily,
    es_notes_v1: notes,
    es_confusable_v1: confusable,
  };
};

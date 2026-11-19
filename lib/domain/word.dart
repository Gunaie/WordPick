/// 词条领域模型
///
/// 数据来源：assets/data/words.json（由 scripts/build_word_assets.js 生成）
/// 字段尽量精简以控制包体积，key 使用短名。
library;

class WordSense {
  final String pos;
  final String cn;
  final String en;

  const WordSense({this.pos = '', this.cn = '', this.en = ''});

  factory WordSense.fromJson(Map<String, dynamic> j) => WordSense(
        pos: (j['pos'] ?? '') as String,
        cn: (j['cn'] ?? '') as String,
        en: (j['en'] ?? '') as String,
      );
}

class WordExample {
  final String en;
  final String cn;

  const WordExample({required this.en, this.cn = ''});

  factory WordExample.fromJson(Map<String, dynamic> j) =>
      WordExample(en: (j['en'] ?? '') as String, cn: (j['cn'] ?? '') as String);
}

class WordRoot {
  final String pos;
  final String w;
  final String cn;

  const WordRoot({this.pos = '', required this.w, this.cn = ''});

  factory WordRoot.fromJson(Map<String, dynamic> j) => WordRoot(
        pos: (j['pos'] ?? '') as String,
        w: (j['w'] ?? '') as String,
        cn: (j['cn'] ?? '') as String,
      );
}

class WordSynonym {
  final String pos;
  final String cn;
  final List<String> words;

  const WordSynonym({this.pos = '', this.cn = '', this.words = const []});

  factory WordSynonym.fromJson(Map<String, dynamic> j) => WordSynonym(
        pos: (j['pos'] ?? '') as String,
        cn: (j['cn'] ?? '') as String,
        words: ((j['words'] ?? const []) as List).cast<String>(),
      );
}

/// 考试练习题（源数据无年份/试卷出处，不标"某年真题"）
class QuizItem {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explain;

  const QuizItem({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.explain = '',
  });

  String get answerText =>
      answerIndex >= 0 && answerIndex < options.length ? options[answerIndex] : '';

  factory QuizItem.fromJson(Map<String, dynamic> j) => QuizItem(
        question: (j['q'] ?? '') as String,
        options: ((j['o'] ?? const []) as List).map((e) => '$e').toList(),
        answerIndex: (j['a'] as num?)?.toInt() ?? 0,
        explain: (j['e'] ?? '') as String,
      );
}

class Word {
  final String w;
  final String uk;
  final String us;
  final List<WordSense> defs;
  final List<WordExample> ex;
  final List<WordExample> phr;
  final List<WordRoot> rel;
  final List<WordSynonym> syn;
  final List<QuizItem> quiz;
  final List<String> tags;

  const Word({
    required this.w,
    this.uk = '',
    this.us = '',
    this.defs = const [],
    this.ex = const [],
    this.phr = const [],
    this.rel = const [],
    this.syn = const [],
    this.quiz = const [],
    this.tags = const [],
  });

  String get key => w.toLowerCase();

  /// 主释义（第一条，用于卡片正面提示）
  String get primaryDefinition => defs.isEmpty ? '' : defs.first.cn;

  factory Word.fromJson(Map<String, dynamic> j) => Word(
        w: (j['w'] ?? '') as String,
        uk: (j['uk'] ?? '') as String,
        us: (j['us'] ?? '') as String,
        defs: ((j['defs'] ?? const []) as List)
            .map((e) => WordSense.fromJson(e as Map<String, dynamic>))
            .toList(),
        ex: ((j['ex'] ?? const []) as List)
            .map((e) => WordExample.fromJson(e as Map<String, dynamic>))
            .toList(),
        phr: ((j['phr'] ?? const []) as List)
            .map((e) => WordExample.fromJson(e as Map<String, dynamic>))
            .toList(),
        rel: ((j['rel'] ?? const []) as List)
            .map((e) => WordRoot.fromJson(e as Map<String, dynamic>))
            .toList(),
        syn: ((j['syn'] ?? const []) as List)
            .map((e) => WordSynonym.fromJson(e as Map<String, dynamic>))
            .toList(),
        quiz: ((j['quiz'] ?? const []) as List)
            .map((e) => QuizItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        tags: ((j['tags'] ?? const []) as List).cast<String>(),
      );
}

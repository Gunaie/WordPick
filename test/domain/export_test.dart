import 'dart:convert';

import 'package:english_study/data/daily_stat.dart';
import 'package:english_study/data/note_record.dart';
import 'package:english_study/domain/custom_word_parser.dart';
import 'package:english_study/domain/export_builder.dart';
import 'package:english_study/domain/export_import.dart';
import 'package:english_study/domain/srs.dart';
import 'package:english_study/domain/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('导出内容', () {
    final now = DateTime(2026, 11, 20, 21, 5);
    final notes = [
      NoteRecord(
        id: 'n1',
        wordKey: 'apple',
        title: '苹果的复数',
        content: '苹果；注意复数 apples',
        tags: const ['名词', '例句'],
        createdAt: now,
        updatedAt: now,
      ),
      NoteRecord(
        id: 'n2',
        wordKey: '',
        content: '今天读到一句好句子。',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('JSON 包含词书、笔记、复习状态与每日统计', () {
      final book = CustomWordBook(
        id: 'b1',
        name: '我的单词本',
        createdAt: now,
        words: [
          CustomWordEntry(
            word: const Word(
              w: 'apple',
              defs: [WordSense(cn: '苹果')],
            ),
            addedAt: now,
          ),
        ],
      );
      final state = ReviewState.initial();
      final raw = buildJsonExport(
        books: [book],
        notes: notes,
        states: {'apple': state},
        daily: [const DailyStat(date: '2026-11-20', reviews: 3, newWords: 1)],
        now: now,
      );

      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['schema'], 1);
      expect(json['exported_at'], now.toIso8601String());
      expect((json['books'] as List).single['name'], '我的单词本');
      expect((json['notes'] as List).length, 2);
      expect((json['notes'] as List).first['title'], '苹果的复数');
      expect((json['notes'] as List).first['tags'], ['名词', '例句']);
      expect((json['review_states'] as Map)['apple']['reps'], 0);
      expect((json['daily'] as List).single['date'], '2026-11-20');
      expect((json['daily'] as List).single['r'], 3);
    });

    test('Markdown 按日期分组', () {
      final md = buildNotesMarkdown(notes: notes, now: now);
      expect(md, contains('# 英语笔记'));
      expect(md, contains('## 2026-11-20'));
      expect(md, contains('### 21:05 · 苹果的复数'));
      expect(md, contains('#名词 #例句'));
      expect(md, contains('苹果；注意复数 apples'));
      expect(md, contains('今天读到一句好句子。'));
      expect(md, isNot(contains('## apple')));
      expect(md, isNot(contains('## 随手记')));
    });

    test('空笔记导出给出说明而不是空白', () {
      final md = buildNotesMarkdown(notes: const [], now: now);
      expect(md, contains('还没有笔记'));
    });
  });

  group('备份恢复解析', () {
    final now = DateTime(2026, 11, 20, 21, 5);

    test('可解析完整的导出备份', () {
      final book = CustomWordBook(
        id: 'b1',
        name: '我的单词本',
        createdAt: now,
        words: [
          CustomWordEntry(
            word: const Word(
              w: 'apple',
              defs: [WordSense(pos: 'n.', cn: '苹果')],
            ),
            addedAt: now,
          ),
        ],
      );
      final note = NoteRecord(
        id: 'n1',
        wordKey: 'apple',
        title: '苹果',
        content: '注意复数',
        tags: const ['名词'],
        createdAt: now,
        updatedAt: now,
      );
      final state = ReviewState(
        interval: 3,
        reps: 2,
        due: now,
        updatedAt: now,
      );
      final raw = buildJsonExport(
        books: [book],
        notes: [note],
        states: {'apple': state},
        daily: [const DailyStat(date: '2026-11-20', reviews: 4, newWords: 2)],
        now: now,
      );

      final data = parseExportJson(raw);
      expect(data.books.single.words.single.word.w, 'apple');
      expect(data.books.single.words.single.word.primaryDefinition, '苹果');
      expect(data.notes.single.id, 'n1');
      expect(data.notes.single.tags, ['名词']);
      expect(data.states['apple']?.interval, 3);
      expect(data.daily.single.reviews, 4);
      expect(data.daily.single.newWords, 2);
      expect(data.exportedAt, now);
    });

    test('拒绝空内容、非法 JSON、其他应用与过高版本', () {
      expect(() => parseExportJson('  '), throwsFormatException);
      expect(() => parseExportJson('not json'), throwsFormatException);
      expect(
        () => parseExportJson('{"app":"other"}'),
        throwsFormatException,
      );
      expect(
        () => parseExportJson('{"app":"english-study","schema":9}'),
        throwsFormatException,
      );
    });

    test('缺可选字段时解析为空数据而不是报错', () {
      final data = parseExportJson('{"app":"english-study","schema":1}');
      expect(data.isEmpty, isTrue);
      expect(data.notes, isEmpty);
      expect(data.books, isEmpty);
    });
  });
}

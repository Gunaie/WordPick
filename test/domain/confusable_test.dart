import 'dart:math';

import 'package:english_study/domain/confusable_group.dart';
import 'package:english_study/domain/confusable_queue.dart';
import 'package:english_study/domain/word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('易混词组', () {
    const adapt = Word(w: 'adapt', defs: [WordSense(cn: '适应')]);
    const adopt = Word(w: 'adopt', defs: [WordSense(cn: '采用')]);
    const adept = Word(w: 'adept', defs: [WordSense(cn: '熟练的')]);
    const abide = Word(w: 'abide', defs: [WordSense(cn: '遵守')]);
    const cat = Word(w: 'cat', defs: [WordSense(cn: '猫')]);
    const dog = Word(w: 'dog', defs: [WordSense(cn: '狗')]);
    final poolByKey = {
      for (final w in [adapt, adopt, adept, abide, cat, dog]) w.key: w,
    };

    ConfusableGroup group(
      String id,
      List<String> keys, {
      String name = '',
    }) =>
        ConfusableGroup(
          id: id,
          name: name,
          wordKeys: keys,
          createdAt: DateTime(2026, 11, 21),
        );

    test('JSON 往返并容忍空白与重复 key', () {
      final restored = ConfusableGroup.fromJson(const {
        'id': '',
        'name': '',
        'word_keys': [' Adapt ', 'adopt', 'adopt', ''],
        'created_at': '2026-11-21T10:00:00.000',
      });
      expect(restored.id, startsWith('group-'));
      expect(restored.wordKeys, ['adapt', 'adopt']);
      expect(restored.displayName, 'adapt / adopt');

      final g = group('g1', ['adapt', 'adopt'], name: 'a / b');
      final back = ConfusableGroup.fromJson(g.toJson());
      expect(back.id, 'g1');
      expect(back.name, 'a / b');
      expect(back.wordKeys, ['adapt', 'adopt']);
      expect(back.createdAt, DateTime(2026, 11, 21));
    });

    test('同伴紧接插在触发词之后，超出上限挤占尾部新词', () {
      final round = buildConfusableRound(
        dueWords: [adapt],
        freshWords: [cat, dog],
        groups: [group('g1', ['adapt', 'adopt'], name: '形近词')],
        poolByKey: poolByKey,
        maxLength: 3,
        random: Random(1),
      );
      expect(round.words.map((w) => w.key).toList(), ['adapt', 'adopt', 'cat']);
      expect(round.companions, {'adopt': '形近词'});
    });

    test('已在队列中的词不重复插入', () {
      final round = buildConfusableRound(
        dueWords: [adapt, adopt, cat],
        freshWords: const [],
        groups: [group('g1', ['adapt', 'adopt'])],
        poolByKey: poolByKey,
        maxLength: 3,
      );
      expect(round.words.length, 3);
      expect(round.words.map((w) => w.key).toList(), ['adapt', 'adopt', 'cat']);
      expect(round.companions, isEmpty);
    });

    test('一组只触发一次，不链式扩散', () {
      final round = buildConfusableRound(
        dueWords: [adapt],
        freshWords: const [],
        groups: [
          group('g1', ['adapt', 'adopt']),
          group('g2', ['adopt', 'abide']),
        ],
        poolByKey: poolByKey,
        maxLength: 3,
        random: Random(2),
      );
      expect(round.words.map((w) => w.key).toList(), ['adapt', 'adopt']);
      expect(round.companions.keys, ['adopt']);
    });

    test('组内顺序随机，但成员集合固定且不超上限', () {
      final keys = <String>{};
      for (var seed = 0; seed < 8; seed++) {
        final round = buildConfusableRound(
          dueWords: [adapt],
          freshWords: [cat, dog],
          groups: [
            group('g1', ['adapt', 'adopt', 'adept', 'abide']),
          ],
          poolByKey: poolByKey,
          maxLength: 4,
          random: Random(seed),
        );
        expect(round.words.length, 4);
        expect(round.words.first.key, 'adapt');
        expect(
          round.words.map((w) => w.key).toSet(),
          {'adapt', 'adopt', 'adept', 'abide'},
        );
        keys.add(round.words.map((w) => w.key).skip(1).join(','));
      }
      // 不同随机种子至少出现过两种组内顺序
      expect(keys.length, greaterThan(1));
    });

    test('少于 2 个词的组被忽略', () {
      final round = buildConfusableRound(
        dueWords: [adapt],
        freshWords: const [],
        groups: [group('g1', ['adapt'])],
        poolByKey: poolByKey,
        maxLength: 1,
      );
      expect(round.words.map((w) => w.key).toList(), ['adapt']);
      expect(round.companions, isEmpty);
    });
  });
}

import 'dart:io';

import 'package:english_study/data/dictionary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('离线词典', () {
    test('紧凑 JSON 解析后可按小写查词', () {
      final repo = DictionaryRepository(
        entries: DictionaryRepository.decode(
          '{"apple":["ˈæpl","n. 苹果"],"look after":["","照顾"]}',
        ),
      );
      expect(repo.lookup(' Apple ')?.phonetic, 'ˈæpl');
      expect(repo.lookup('LOOK AFTER')?.translation, '照顾');
      expect(repo.lookup('missing'), isNull);
    });

    test('缺字段或空释义的条目被忽略', () {
      final entries = DictionaryRepository.decode(
        '{"ok":["p","释义"],"empty":["p"," "],"bad":["p"],"num":[1,2]}',
      );
      expect(entries.keys, ['ok']);
    });

    test('内置词典资源包含常用词', () {
      final raw = File('assets/data/dict_core.json').readAsStringSync();
      final entries = DictionaryRepository.decode(raw);
      expect(entries.length, greaterThan(10000));
      expect(entries['apple']?.phonetic, isNotEmpty);
      expect(entries['apple']?.translation, contains('苹果'));
    });
  });
}

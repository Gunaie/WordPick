// ignore_for_file: avoid_print
// 自建词解析的冒烟验证脚本（`dart run scripts/parse_probe.dart`）
import 'package:english_study/domain/custom_word_parser.dart';

void main() {
  const text = '''
serendipity 意外发现
resilient, 有韧性的
take off    起飞
hello:你好
中文词 应被忽略
123 应被忽略

  spaced  带前导空格
''';

  final words =
      parseCustomWordsDetailed(text, repeatable: {'hello'}).added;

  print('解析结果: ${words.length} 条');
  for (final w in words) {
    print('  ${w.w}  ->  ${w.primaryDefinition}');
  }

  final expected = ['serendipity', 'resilient', 'take off', 'spaced'];
  final actual = words.map((w) => w.w).toList();
  final ok = expected.length == actual.length &&
      List.generate(expected.length, (i) => expected[i] == actual[i])
          .every((e) => e);

  print(ok ? 'PASS' : 'FAIL: 期望 $expected，实际 $actual');
}

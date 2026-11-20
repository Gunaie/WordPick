/// 备份文件解析（纯逻辑，便于单测）
///
/// 与 [buildJsonExport] 的结构一一对应；解析失败抛出带中文说明的 [FormatException]。
library;

import 'dart:convert';

import '../data/daily_stat.dart';
import '../data/note_record.dart';
import 'custom_word_parser.dart';
import 'srs.dart';

/// 从备份文件读出的数据（尚未与本地合并）
class ImportedData {
  final List<CustomWordBook> books;
  final List<NoteRecord> notes;
  final Map<String, ReviewState> states;
  final List<DailyStat> daily;
  final DateTime? exportedAt;

  const ImportedData({
    this.books = const [],
    this.notes = const [],
    this.states = const {},
    this.daily = const [],
    this.exportedAt,
  });

  bool get isEmpty =>
      books.isEmpty && notes.isEmpty && states.isEmpty && daily.isEmpty;
}

ImportedData parseExportJson(String raw) {
  final text = raw.trim();
  if (text.isEmpty) throw const FormatException('内容为空');

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw const FormatException('不是合法的 JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('备份格式不正确');
  }
  if (decoded['app'] != 'english-study') {
    throw const FormatException('不是本应用导出的备份文件');
  }
  final schema = (decoded['schema'] as num?)?.toInt() ?? 1;
  if (schema > 1) {
    throw FormatException('备份版本过高（schema $schema），请先升级应用');
  }

  final books = <CustomWordBook>[];
  for (final item in _list(decoded['books'])) {
    final j = _map(item);
    if (j == null) continue;
    final book = CustomWordBook.fromJson(j);
    if (book.id.isNotEmpty) books.add(book);
  }

  final notes = <NoteRecord>[];
  for (final item in _list(decoded['notes'])) {
    final j = _map(item);
    if (j == null) continue;
    final id = '${j['id'] ?? ''}';
    if (id.isEmpty) continue;
    notes.add(NoteRecord.fromJson(j));
  }

  final states = <String, ReviewState>{};
  final rawStates = decoded['review_states'];
  if (rawStates is Map) {
    for (final e in rawStates.entries) {
      final j = _map(e.value);
      if (j == null) continue;
      states['${e.key}'] = ReviewState.fromJson(j);
    }
  }

  final daily = <DailyStat>[];
  for (final item in _list(decoded['daily'])) {
    final j = _map(item);
    if (j == null) continue;
    final date = '${j['date'] ?? ''}';
    if (date.isEmpty) continue;
    daily.add(DailyStat.fromJson(date, j));
  }

  return ImportedData(
    books: books,
    notes: notes,
    states: states,
    daily: daily,
    exportedAt: DateTime.tryParse('${decoded['exported_at'] ?? ''}'),
  );
}

Iterable<Object?> _list(Object? value) =>
    value is List ? value : const <Object?>[];

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

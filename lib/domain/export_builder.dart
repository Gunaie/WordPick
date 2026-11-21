/// 导出内容构造（纯逻辑，便于单测）
library;

import 'dart:convert';

import '../data/daily_stat.dart';
import '../data/note_record.dart';
import 'custom_word_parser.dart';
import 'srs.dart';

/// 完整数据导出（JSON）
String buildJsonExport({
  required List<CustomWordBook> books,
  required List<NoteRecord> notes,
  required Map<String, ReviewState> states,
  required List<DailyStat> daily,
  DateTime? now,
}) {
  final data = {
    'app': 'english-study',
    'schema': 1,
    'exported_at': (now ?? DateTime.now()).toIso8601String(),
    'books': books.map((b) => b.toJson()).toList(),
    'notes': notes.map((n) => n.toJson()).toList(),
    'review_states': {for (final e in states.entries) e.key: e.value.toJson()},
    'daily': [
      for (final d in daily) {'date': d.date, ...d.toJson()},
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// 笔记导出（Markdown）：按更新日期分组，组内按时间正序
String buildNotesMarkdown({required List<NoteRecord> notes, DateTime? now}) {
  final at = now ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('# 英语笔记')
    ..writeln()
    ..writeln('> 导出时间：${_fmtDateTime(at)}')
    ..writeln('> 共 ${notes.length} 条笔记')
    ..writeln();

  if (notes.isEmpty) {
    buffer.writeln('_还没有笔记。_');
    return buffer.toString();
  }

  final groups = <String, List<NoteRecord>>{};
  for (final n in notes) {
    groups.putIfAbsent(_fmtDate(n.updatedAt), () => []).add(n);
  }
  final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

  for (final day in days) {
    final list = groups[day]!
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    buffer
      ..writeln('## $day')
      ..writeln();
    for (final n in list) {
      final heading = n.title.trim().isEmpty ? '' : ' · ${n.title.trim()}';
      buffer
        ..writeln('### ${_fmtTime(n.updatedAt)}$heading')
        ..writeln();
      if (n.tags.isNotEmpty) {
        buffer
          ..writeln('> ${n.tags.map((t) => '#$t').join(' ')}')
          ..writeln();
      }
      if (n.content.isNotEmpty) {
        buffer
          ..writeln(n.content)
          ..writeln();
      }
    }
  }
  return buffer.toString();
}

String _fmtDate(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}

String _fmtDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

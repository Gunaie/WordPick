import 'package:english_study/domain/srs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SM-2 调度', () {
    test('首次答对间隔为 1 天', () {
      final s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      expect(s.reps, 1);
      expect(s.interval, 1);
      expect(s.lapses, 0);
    });

    test('连续答对间隔递增', () {
      var s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      s = SrsEngine.next(s, ReviewGrade.good);
      expect(s.interval, 3);
      s = SrsEngine.next(s, ReviewGrade.good);
      expect(s.interval, greaterThan(3));
    });

    test('忘记后重置并累计 lapses', () {
      var s = SrsEngine.next(ReviewState.initial(), ReviewGrade.good);
      s = SrsEngine.next(s, ReviewGrade.good);
      final before = s.lapses;
      s = SrsEngine.next(s, ReviewGrade.again);
      expect(s.reps, 0);
      expect(s.interval, 0);
      expect(s.lapses, before + 1);
      expect(s.due.difference(DateTime.now()).inMinutes, lessThanOrEqualTo(11));
    });

    test('E-Factor 不低于 1.3', () {
      var s = ReviewState.initial();
      for (var i = 0; i < 10; i++) {
        s = SrsEngine.next(s, ReviewGrade.again);
      }
      expect(s.ease, greaterThanOrEqualTo(1.3));
    });
  });
}

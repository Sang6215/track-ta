import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await TrainingStore.load();
  });
  test('All source records imported without filling empty weeks', () {
    expect(store.days.length, 5);
    expect(store.exercises.length, 28);
    expect(store.totalSets, 91);
    expect(store.entries.length, 108);
    expect(store.latestWeek, 3);
    expect(
      [for (int i = 1; i <= 8; i++) store.weekDone(i)],
      [56, 34, 18, 0, 0, 0, 0, 0],
    );
    final bench = store.exercises.first;
    expect(store.entry(1, bench, 2).weight, '2x12.5kg');
    expect(store.entry(1, bench, 4).empty, true);
  });
  test('Weight parsing preserves pairs, decimals and missing vs zero', () {
    expect(parseWeight('2x12.5kg'), 25);
    expect(parseWeight('2 × 7,5 kg'), 15);
    expect(parseWeight('35kg'), 35);
    expect(parseWeight('0'), 0);
    for (final bad in ['', '-5', 'hello', '2xx3']) {
      expect(parseWeight(bad), isNull);
    }
  });
  test(
    'Edits persist across restart; deleted imported records stay deleted',
    () async {
      final ex = store.exercises.first;
      await store.update(
        4,
        ex,
        1,
        const SetEntry(weight: '2x15kg', reps: '8', note: 'Tốt'),
      );
      await store.update(1, ex, 1, const SetEntry());
      final loaded = await TrainingStore.load();
      expect(loaded.entry(4, ex, 1).note, 'Tốt');
      expect(loaded.entry(1, ex, 1).empty, true);
      expect(loaded.entry(1, ex, 2).weight, '2x12.5kg');
    },
  );
  test('New week is empty and backup restores exact state', () async {
    final saved = store.backup();
    await store.addWeek();
    expect(store.weeks, 9);
    expect(store.weekDone(9), 0);
    await store.restore(saved);
    expect(store.weeks, 8);
    expect(store.backup(), saved);
  });
  test('Malformed restore never changes existing data', () async {
    final saved = store.backup();
    final invalid = jsonDecode(saved);
    invalid['entries']['1:unknown:1'] = {'weight': '10', 'reps': '8'};
    await expectLater(
      store.restore(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(store.backup(), saved);
    invalid['entries'].remove('1:unknown:1');
    invalid['weeks'] = 0;
    await expectLater(
      store.restore(jsonEncode(invalid)),
      throwsFormatException,
    );
    expect(store.backup(), saved);
  });
  test('Progress keeps blank weeks null; assisted uses minimum', () async {
    final ex = store.exercises.firstWhere((e) => e.assisted);
    await store.update(4, ex, 1, const SetEntry(weight: '40', reps: '8'));
    await store.update(4, ex, 2, const SetEntry(weight: '45', reps: '8'));
    expect(store.best(4, ex), 40);
    expect(store.best(5, ex), isNull);
    final plank = store.exercises.firstWhere((e) => e.timed);
    await store.update(4, plank, 1, const SetEntry(reps: '60'));
    expect(store.best(4, plank), 60);
  });
  test('CSV retains original weight and escapes user formulas', () async {
    await store.update(
      4,
      store.exercises.first,
      1,
      const SetEntry(weight: '2x12.5kg', reps: '10', note: '=SUM(1,2)'),
    );
    final csv = store.csv();
    expect(csv.startsWith('\uFEFF'), true);
    expect(csv, contains('2x12.5kg'));
    expect(csv, contains("'=SUM(1,2)"));
  });
}

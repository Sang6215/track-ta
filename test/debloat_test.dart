import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/debloat.dart';
import 'package:track_ta/models.dart';

class FailingStore extends TrainingStore {
  FailingStore(TrainingStore source)
    : super(source.prefs, source.days, Map.of(source.entries), source.weeks);
  @override
  Future<void> save() async => throw Exception('Disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingStore store;
  late Exercise bench;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await TrainingStore.load();
    store.entries.clear();
    bench = store.exercises.first;
  });
  void history(Exercise e, List<String> weights, {String reps = '8'}) {
    for (var i = 0; i < 4; i++) {
      store.entries[store.key(i + 1, e, 1)] = SetEntry(
        weight: e.timed ? '' : weights[i],
        reps: e.timed ? weights[i] : reps,
      );
    }
  }

  DebloatSuggestion suggestion(Exercise e) => buildDebloatPlan(
    store,
  ).suggestions.firstWhere((s) => s.exercise.id == e.id);

  test('Regression is capped before factor and rounds to 2.5kg', () {
    history(bench, ['40kg', '42.5kg', '45kg', '47.5kg']);
    final s = suggestion(bench);
    expect(s.rawForecast, 50);
    expect(s.forecast, 47.5);
    expect(s.weight, '27.5kg');
    expect(s.reps, '6');
  });
  test('Paired weights round each dumbbell and keep 2x notation', () {
    history(bench, ['2x10kg', '2x12.5kg', '2x12.5kg', '2x15kg']);
    expect(suggestion(bench).weight, '2x10kg');
    expect(suggestion(bench).weeklyValues, [20, 25, 25, 30]);
  });
  test('Assisted uses weekly minimum, divides by factor and rounds up', () {
    final ex = store.exercises.firstWhere((e) => e.assisted);
    history(ex, ['40', '45', '45', '50']);
    store.entries[store.key(1, ex, 2)] = const SetEntry(
      weight: '55',
      reps: '8',
    );
    final s = suggestion(ex);
    expect(s.weeklyValues.first, 40);
    expect(s.forecast, 40);
    expect(s.weight, '67.5kg');
  });
  test('Timed rounds to 5 seconds; BW fills only target reps', () {
    final plank = store.exercises.firstWhere((e) => e.timed);
    history(plank, ['60', '60', '60', '60']);
    expect(suggestion(plank).reps, '35');
    expect(suggestion(plank).weight, '');
    history(bench, ['', '', '', '']);
    expect(suggestion(bench).weight, '');
    expect(suggestion(bench).forecast, isNull);
    expect(suggestion(bench).reps, '6');
  });
  test('Eligibility needs weeks 1–4; suggestions count as unconfirmed data', () {
    history(bench, ['40', '40', '40', '40']);
    store.entries[store.key(4, bench, 1)] = const SetEntry(
      weight: '40',
      reps: '8',
      source: 'debloat',
    );
    expect(canBuildDebloat(store), false);
    final other = store.exercises[1];
    history(other, ['20', '20', '20', '20']);
    expect(canBuildDebloat(store), true);
    // Week 4 only holds an unconfirmed suggestion, so bench runs on 3 weeks.
    final plan = buildDebloatPlan(store);
    final s = plan.suggestions.firstWhere((s) => s.exercise.id == bench.id);
    expect(s.weeksUsed, 3);
    expect(s.forecast, 40);
    expect(plan.skipped.keys, isNot(contains(bench)));
  });
  test('Two of four weeks still regress; missing weeks are blank', () {
    history(store.exercises[1], ['20', '20', '20', '20']);
    store.entries[store.key(1, bench, 1)] = const SetEntry(
      weight: '40kg',
      reps: '8',
    );
    store.entries[store.key(3, bench, 1)] = const SetEntry(
      weight: '44kg',
      reps: '8',
    );
    final s = suggestion(bench);
    expect(s.weeksUsed, 2);
    expect(s.weeklyValues, [40, null, 44, null]);
    expect(s.rawForecast, 48);
    expect(s.forecast, 44);
    expect(s.weight, '27.5kg');
  });
  test('Single week repeats its own value', () {
    history(store.exercises[1], ['20', '20', '20', '20']);
    store.entries[store.key(2, bench, 1)] = const SetEntry(
      weight: '45kg',
      reps: '8',
    );
    final s = suggestion(bench);
    expect(s.weeksUsed, 1);
    expect(s.rawForecast, 45);
    expect(s.forecast, 45);
    expect(s.weight, '27.5kg');
  });
  test('Assisted with partial weeks clamps to lowest available week', () {
    history(store.exercises[1], ['20', '20', '20', '20']);
    final ex = store.exercises.firstWhere((e) => e.assisted);
    store.entries[store.key(1, ex, 1)] = const SetEntry(
      weight: '50',
      reps: '8',
    );
    store.entries[store.key(2, ex, 1)] = const SetEntry(
      weight: '40',
      reps: '8',
    );
    final s = suggestion(ex);
    expect(s.weeksUsed, 2);
    expect(s.rawForecast, 10);
    expect(s.forecast, 10);
    expect(s.weight, '17.5kg');
  });
  test('Exercise with no logged weeks stays skipped', () {
    history(bench, ['40', '40', '40', '40']);
    final untouched = store.exercises[2];
    final plan = buildDebloatPlan(store);
    expect(plan.skipped[untouched], 'Chưa có hiệp đã tập nào trong tuần 1–4.');
    expect(plan.suggestions.any((s) => s.exercise.id == untouched.id), false);
  });
  test(
    'Only empty sets filled; suggested sets not completed, restart and confirm',
    () async {
      history(bench, ['40', '42.5', '45', '47.5']);
      const existing = SetEntry(note: 'Giữ ghi chú này');
      store.entries[store.key(5, bench, 1)] = existing;
      final plan = buildDebloatPlan(store);
      expect(plan.fillCount, 3);
      expect(plan.preservedSets, 1);
      expect(await store.applyDebloat(5, plan.values), 3);
      expect(store.entry(5, bench, 1).toJson(), existing.toJson());
      expect(store.weekDone(5), 0);
      expect(store.best(5, bench), isNull);
      expect(store.isDebloat(5), true);
      expect(await store.applyDebloat(5, plan.values), 0);
      final loaded = await TrainingStore.load();
      expect(loaded.isDebloat(5), true);
      final v = loaded.entry(5, bench, 2);
      expect(v.suggested, true);
      await loaded.update(
        5,
        bench,
        2,
        SetEntry(weight: v.weight, reps: v.reps),
      );
      expect(loaded.weekDone(5), 1);
      expect(loaded.best(5, bench), 27.5);
    },
  );
  test(
    'Invalid labels and invalid batch roll back all entries and labels',
    () async {
      history(bench, ['40', '40', '40', '40']);
      final before = store.backup();
      for (final labels in [
        [5, 5],
        [0],
        [9],
        ['5'],
        null,
      ]) {
        final raw = jsonDecode(before);
        raw['debloatWeeks'] = labels;
        if (labels == null) {
          raw.remove('debloatWeeks');
          store.readBackup(jsonEncode(raw));
          expect(store.debloatWeeks, isEmpty);
        } else {
          expect(
            () => store.readBackup(jsonEncode(raw)),
            throwsFormatException,
          );
        }
      }
      await expectLater(
        store.applyDebloat(5, {
          '5:missing:1': const SetEntry(reps: '8', source: 'debloat'),
        }),
        throwsFormatException,
      );
      expect(store.backup(), before);
    },
  );
  test('Declining regression clamps at zero', () {
    history(bench, ['100', '50', '10', '0']);
    expect(suggestion(bench).forecast, 0);
    expect(suggestion(bench).weight, '0kg');
  });
  test('Failed batch persistence restores entries and week labels', () async {
    history(bench, ['40', '40', '40', '40']);
    final failed = FailingStore(store);
    final before = failed.backup();
    await expectLater(
      failed.applyDebloat(5, buildDebloatPlan(failed).values),
      throwsException,
    );
    expect(failed.backup(), before);
  });
}

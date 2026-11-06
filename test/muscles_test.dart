import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/main.dart';
import 'package:track_ta/models.dart';
import 'package:track_ta/muscles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await TrainingStore.load();
  });

  test('Every imported exercise has distinct primary and secondary groups', () {
    expect(
      exerciseMuscles.keys.toSet(),
      store.exercises.map((e) => e.id).toSet(),
    );
    for (final targets in exerciseMuscles.values) {
      expect(targets.primary, isNotEmpty);
      expect(targets.primary.toSet().length, targets.primary.length);
      expect(targets.secondary.toSet().length, targets.secondary.length);
      expect(
        targets.primary.toSet().intersection(targets.secondary.toSet()),
        isEmpty,
      );
    }
  });

  test(
    'Weekly analysis uses completed sets and excludes secondary groups',
    () async {
      expect(primarySetCounts(store, 4).values.every((n) => n == 0), true);
      final bench = store.exercises.firstWhere((e) => e.id == 'd1e1');
      final row = store.exercises.firstWhere((e) => e.id == 'd1e4');
      await store.update(4, bench, 1, const SetEntry(weight: '40', reps: '8'));
      await store.update(4, bench, 2, const SetEntry(weight: '40'));
      await store.update(4, row, 1, const SetEntry(weight: '35', reps: '10'));
      final counts = primarySetCounts(store, 4);
      expect(counts[MuscleGroup.chest], 1);
      expect(counts[MuscleGroup.lats], 1);
      expect(counts[MuscleGroup.upperBack], 1);
      expect(counts[MuscleGroup.triceps], 0);
      expect(counts[MuscleGroup.biceps], 0);
    },
  );

  testWidgets('Exercise model and weekly analysis work on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TrackApp(store: store));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -430));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('muscle-d5e1')));
    await tester.pumpAndSettle();
    expect(find.text('MẶT TRƯỚC'), findsOneWidget);
    expect(find.text('MẶT SAU'), findsOneWidget);
    expect(find.textContaining('Xô'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiến độ'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Bản đồ cơ'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Bản đồ cơ'));
    await tester.pumpAndSettle();
    expect(find.text('Số hiệp theo nhóm cơ chính'), findsOneWidget);
    expect(find.text('Tuần 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

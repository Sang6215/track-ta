import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/main.dart';
import 'package:track_ta/models.dart';
import 'package:track_ta/debloat_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await TrainingStore.load();
  });

  Future<void> makeEligible() async {
    final bench = store.exercises.first;
    for (var w = 1; w <= 4; w++) {
      await store.update(
        w,
        bench,
        1,
        const SetEntry(weight: '40kg', reps: '8'),
      );
    }
  }
  testWidgets(
    'Phone workflow: seed, edit, navigation, progress and backup UI',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TrackApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Tuần 03'), findsOneWidget);
      expect(find.text('18/18 hiệp'), findsOneWidget);
      final row = find.byKey(const ValueKey('set-d5e1-1'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cơ tác động'));
      await tester.pumpAndSettle();
      expect(find.text('MẶT TRƯỚC'), findsOneWidget);
      expect(find.text('MẶT SAU'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('weight-input')),
        '37.5kg',
      );
      await tester.enterText(find.byKey(const ValueKey('reps-input')), '11');
      await tester.ensureVisible(find.text('Lưu hiệp'));
      await tester.tap(find.text('Lưu hiệp'));
      await tester.pumpAndSettle();
      expect(store.entries['3:d5e1:1']!.weight, '37.5kg');
      await tester.tap(find.text('Tiến độ'));
      await tester.pumpAndSettle();
      expect(find.text('Nhìn lại tiến độ'), findsOneWidget);
      await tester.tap(find.text('Dữ liệu'));
      await tester.pumpAndSettle();
      expect(find.text('Đã nhập từ Excel'), findsOneWidget);
      await tester.tap(find.text('Lịch tập'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(find.text('Tuần 04'), findsOneWidget);
      expect(find.text('0/18 hiệp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Small phone navigation has no layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(TrackApp(store: store));
    await tester.pumpAndSettle();
    for (final tab in ['Tiến độ', 'Dữ liệu', 'Lịch tập']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Debloat hidden until four weeks; preview, apply and confirm a set',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(TrackApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Tuần debloat'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final bench = store.exercises.first;
      for (var w = 1; w <= 4; w++) {
        await store.update(
          w,
          bench,
          1,
          const SetEntry(weight: '40kg', reps: '8'),
        );
      }
      await tester.pumpWidget(TrackApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Tuần debloat'), findsOneWidget);
      await tester.ensureVisible(find.text('Xem & áp dụng'));
      await tester.tap(find.text('Xem & áp dụng'));
      await tester.pumpAndSettle();
      expect(find.byType(DebloatPreview), findsOneWidget);
      expect(find.text('Tuần 5 · Debloat'), findsOneWidget);
      await tester.tap(find.text('Áp dụng vào tuần 5'));
      await tester.pumpAndSettle();
      expect(store.isDebloat(5), true);
      expect(store.weekDone(5), 0);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
      await tester.pumpAndSettle();
      expect(find.textContaining('DEBLOAT'), findsWidgets);
      final row = find.byKey(const ValueKey('set-d1e1-1'));
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lưu hiệp'));
      await tester.tap(find.text('Lưu hiệp'));
      await tester.pumpAndSettle();
      expect(store.weekDone(5), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AI button explains setup when no key is configured', (
    tester,
  ) async {
    await makeEligible();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DebloatPreview(store: store))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-run')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-setup')));
    await tester.pumpAndSettle();
    expect(find.textContaining('aistudio.google.com/apikey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Configured AI auto-analyses, shows advice and applies adjustments',
    (tester) async {
      await makeEligible();
      SharedPreferences.setMockInitialValues({
        'trackta.gemini.v1': jsonEncode({
          'key': 'AIza-syFake-key-1234567890',
          'model': 'gemini-2.5-flash',
        }),
      });
      final bench = store.exercises.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebloatPreview(
              store: store,
              aiSender: (_, _, _) async => jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'text': jsonEncode({
                            'summary': 'Bốn tuần tiến bộ đều, giữ kỹ thuật.',
                            'warnings': ['Đỡ khớp vai khi đẩy nặng.'],
                            'exercises': [
                              {
                                'id': bench.id,
                                'comment': 'Giữ nhịp đẩy ổn định.',
                                'weight': '25kg',
                                'reps': '7',
                              },
                            ],
                          }),
                        },
                      ],
                    },
                  },
                ],
              }),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-run')), findsOneWidget);
      expect(find.textContaining('Bốn tuần tiến bộ đều'), findsOneWidget);
      expect(find.textContaining('Đỡ khớp vai'), findsOneWidget);
      expect(find.textContaining('AI: Giữ nhịp đẩy ổn định.'), findsOneWidget);
      expect(find.textContaining('AI điều chỉnh: 25kg × 7'), findsOneWidget);
      await tester.ensureVisible(
        find.text('Áp dụng vào tuần 5 (kèm điều chỉnh AI)'),
      );
      await tester.tap(find.text('Áp dụng vào tuần 5 (kèm điều chỉnh AI)'));
      await tester.pumpAndSettle();
      final applied = store.entry(5, bench, 1);
      expect(applied.reps, '7');
      expect(applied.weight, '25kg');
      expect(applied.suggested, true);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/ai_coach.dart';
import 'package:track_ta/debloat.dart';
import 'package:track_ta/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TrainingStore store;
  late Exercise bench, plank;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await TrainingStore.load();
    store.entries.clear();
    bench = store.exercises.first;
    plank = store.exercises.firstWhere((e) => e.timed);
    for (var i = 0; i < 4; i++) {
      store.entries[store.key(i + 1, bench, 1)] = const SetEntry(
        weight: '40kg',
        reps: '8',
      );
      store.entries[store.key(i + 1, store.exercises[1], 1)] = const SetEntry(
        weight: '20kg',
        reps: '8',
      );
      store.entries[store.key(i + 1, plank, 1)] = const SetEntry(reps: '60');
    }
  });

  DebloatPlan buildPlan() => buildDebloatPlan(store);
  DebloatSuggestion suggestionFor(String id) =>
      buildPlan().suggestions.firstWhere((s) => s.exercise.id == id);

  String geminiBody(Object payload) => jsonEncode({
    'candidates': [
      {'content': {'parts': [{'text': jsonEncode(payload)}]}},
    ],
  });

  group('AiCoachConfig', () {
    test('round-trips through preferences and defaults safely', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await AiCoachConfig.load()).ready, false);
      const config = AiCoachConfig(
        apiKey: '  AIza-syFake-key-123456  ',
        model: 'gemini-2.0-flash',
      );
      await config.save();
      final loaded = await AiCoachConfig.load();
      expect(loaded.apiKey, 'AIza-syFake-key-123456');
      expect(loaded.model, 'gemini-2.0-flash');
      expect(loaded.ready, true);
      SharedPreferences.setMockInitialValues({
        AiCoachConfig.storageKey: 'not json',
      });
      final broken = await AiCoachConfig.load();
      expect(broken.ready, false);
      expect(broken.model, AiCoachConfig.defaultModel);
      SharedPreferences.setMockInitialValues({});
    });
  });

  group('validateAdjustment', () {
    test('accepts weights inside ±20% and rounds to the same step', () {
      final s = suggestionFor(bench.id);
      expect(s.weight, '25kg');
      expect(validateAdjustment(s, '26kg', null)?.weight, '25kg');
      expect(validateAdjustment(s, '30kg', null)?.weight, '30kg');
    });
    test('rejects weights outside ±20%, empty weights and non-weights', () {
      final s = suggestionFor(bench.id);
      expect(validateAdjustment(s, '40kg', null), isNull);
      expect(validateAdjustment(s, '15kg', null), isNull);
      expect(validateAdjustment(s, 'nặng', null), isNull);
    });
    test('keeps 2x notation for paired suggestions', () {
      for (var i = 0; i < 4; i++) {
        store.entries[store.key(i + 1, bench, 1)] = const SetEntry(
          weight: '2x20kg',
          reps: '8',
        );
      }
      final s = suggestionFor(bench.id);
      expect(s.weight, '2x12.5kg');
      final ok = validateAdjustment(s, '2x14kg', null);
      expect(ok?.weight, '2x15kg');
    });
    test('clamps reps into the target range and seconds into ±20%', () {
      final s = suggestionFor(bench.id);
      expect(validateAdjustment(s, null, '20')?.reps, '8');
      expect(validateAdjustment(s, null, '7')?.reps, '7');
      expect(validateAdjustment(s, null, 'nhiều'), isNull);
      final timed = suggestionFor(plank.id);
      expect(timed.reps, '35');
      expect(validateAdjustment(timed, null, '40')?.reps, '40');
      expect(validateAdjustment(timed, null, '999'), isNull);
    });
  });

  group('parseResponse', () {
    test('maps fields, keeps comments for skipped exercises, drops unknown ids', () {
      final current = buildPlan();
      final skippedId = current.skipped.keys.first.id;
      final analysis = parseResponse(geminiBody({
        'summary': 'Tiến bộ đều.',
        'warnings': ['Đỡ vai phải', ''],
        'exercises': [
          {'id': bench.id, 'comment': ' Giữ  kỹ thuật  tốt. '},
          {'id': skippedId, 'comment': 'Chưa có dữ liệu, tập nhẹ thử cảm giác.'},
          {'id': 'ghost', 'comment': 'bỏ qua'},
          'rác',
        ],
      }), current);
      expect(analysis.summary, 'Tiến bộ đều.');
      expect(analysis.warnings, ['Đỡ vai phải']);
      expect(analysis.byExercise[bench.id]!.comment, 'Giữ kỹ thuật tốt.');
      expect(analysis.byExercise.containsKey(skippedId), isTrue);
      expect(analysis.byExercise.containsKey('ghost'), isFalse);
    });
    test('rejects broken envelopes with a friendly message', () {
      final current = buildPlan();
      expect(
        () => parseResponse(geminiBody('không phải json'), current),
        throwsA(isA<AiCoachException>()),
      );
      expect(
        () => parseResponse('cũng hỏng', current),
        throwsA(isA<AiCoachException>()),
      );
      expect(
        () => parseResponse(
          jsonEncode({
            'error': {'code': 400, 'message': 'API key not valid'},
          }),
          current,
        ),
        throwsA(isA<AiCoachException>()),
      );
    });
  });

  group('AiCoach.analyze', () {
    test('sends the plan, validates adjustments and merges into empty sets', () async {
      final current = buildPlan();
      String? sent;
      Uri? endpoint;
      String? key;
      final analysis = await AiCoach(
        const AiCoachConfig(
          apiKey: 'AIza-syFake-key-123456',
          model: 'gemini-2.5-flash',
        ),
        send: (uri, apiKey, body) async {
          endpoint = uri;
          key = apiKey;
          sent = body;
          return geminiBody({
            'summary': 'Tuần giảm tải hợp lý.',
            'warnings': [],
            'exercises': [
              {'id': bench.id, 'comment': 'Hạ nhẹ nếu mỏi.', 'weight': '25kg', 'reps': '7'},
            ],
          });
        },
      ).analyze(current);
      expect(endpoint.toString(), contains('gemini-2.5-flash:generateContent'));
      expect(key, 'AIza-syFake-key-123456');
      expect(sent, contains(bench.id));
      expect(sent, contains('thinkingBudget'));
      final merged = mergeAiValues(current, analysis);
      expect(merged['5:${bench.id}:1']!.weight, '25kg');
      expect(merged['5:${bench.id}:1']!.reps, '7');
      expect(merged.values.every((v) => v.suggested), isTrue);
    });
    test('retries once without thinking config when the model rejects it', () async {
      final calls = <String>[];
      final analysis = await AiCoach(
        const AiCoachConfig(apiKey: 'AIza-syFake-key-123456', model: 'gemini-x'),
        send: (_, _, body) {
          calls.add(body);
          if (body.contains('thinkingBudget')) {
            throw const AiCoachException('bị từ chối', status: 400);
          }
          return Future.value(
            geminiBody({'summary': 'OK', 'warnings': [], 'exercises': []}),
          );
        },
      ).analyze(buildPlan());
      expect(calls.length, 2);
      expect(calls[0].contains('thinkingBudget'), isTrue);
      expect(calls[1].contains('thinkingBudget'), isFalse);
      expect(analysis.summary, 'OK');
    });
    test('strips markdown fences around the JSON payload', () {
      final current = buildPlan();
      final fenced = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text':
                      '```json\n${jsonEncode({'summary': 'Trong fences.', 'warnings': [], 'exercises': []})}\n```',
                },
              ],
            },
          },
        ],
      });
      expect(parseResponse(fenced, current).summary, 'Trong fences.');
    });
    test('out-of-range adjustment falls back to the formula value', () {
      final current = buildPlan();
      final analysis = parseResponse(geminiBody({
        'summary': '',
        'warnings': [],
        'exercises': [
          {'id': bench.id, 'comment': 'Quá nhẹ.', 'weight': '90kg'},
        ],
      }), current);
      final merged = mergeAiValues(current, analysis);
      expect(merged['5:${bench.id}:1']!.weight, '25kg');
    });
    test('requires a configured key', () async {
      const coach = AiCoachConfig(apiKey: '', model: 'gemini-2.5-flash');
      await expectLater(
        AiCoach(coach, send: (_, _, _) => throw StateError('must not send')).analyze(
          buildPlan(),
        ),
        throwsA(isA<AiCoachException>()),
      );
    });
  });
}

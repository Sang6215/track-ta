import 'dart:math';
import 'models.dart';

class DebloatSuggestion {
  final Exercise exercise;
  final List<double?> weeklyValues;
  final double? rawForecast, forecast;
  final String weight, reps;
  final int emptySets, preservedSets, weeksUsed;
  final bool paired;
  const DebloatSuggestion({
    required this.exercise,
    required this.weeklyValues,
    required this.rawForecast,
    required this.forecast,
    required this.weight,
    required this.reps,
    required this.emptySets,
    required this.preservedSets,
    required this.weeksUsed,
    required this.paired,
  });
}

class DebloatPlan {
  final int targetWeek;
  final double factor;
  final bool eligible;
  final List<DebloatSuggestion> suggestions;
  final Map<Exercise, String> skipped;
  final Map<String, SetEntry> values;
  final int preservedSets;
  const DebloatPlan({
    required this.targetWeek,
    required this.factor,
    required this.eligible,
    required this.suggestions,
    required this.skipped,
    required this.values,
    required this.preservedSets,
  });
  int get fillCount => values.length;
}

bool canBuildDebloat(TrainingStore store) =>
    List.generate(4, (i) => i + 1).every(
      (w) => store.entries.entries.any(
        (e) => e.key.startsWith('$w:') && e.value.complete,
      ),
    );

/// Least squares on whichever of weeks 1–4 have a value; one point repeats
/// itself. Weeks without data are simply missing points, never zero.
double forecastWeekFive(List<double?> weekly) {
  final points = [
    for (int i = 0; i < 4; i++)
      if (weekly[i] != null) (i + 1, weekly[i]!),
  ];
  if (points.length == 1) return points[0].$2;
  final meanX = points.fold<double>(0, (a, p) => a + p.$1) / points.length;
  final meanY = points.fold<double>(0, (a, p) => a + p.$2) / points.length;
  var numerator = 0.0, denominator = 0.0;
  for (final (x, y) in points) {
    numerator += (x - meanX) * (y - meanY);
    denominator += (x - meanX) * (x - meanX);
  }
  return meanY + (denominator == 0 ? 0 : numerator / denominator) * (5 - meanX);
}

double roundDebloat(double value, double step, {bool up = false}) =>
    (up ? (value / step - 1e-9).ceil() : (value / step + 0.5 + 1e-9).floor()) *
    step;

String formatSuggestedWeight(
  double total, {
  bool paired = false,
  bool assisted = false,
}) {
  final count = paired ? 2 : 1;
  final amount = roundDebloat(total / count, 2.5, up: assisted);
  return '${paired ? '2x' : ''}${number(amount)}kg';
}

DebloatPlan buildDebloatPlan(
  TrainingStore store, {
  int targetWeek = 5,
  double factor = 0.6,
}) {
  if (targetWeek != 5 || !factor.isFinite || factor <= 0 || factor > 1) {
    throw ArgumentError('Tuần debloat là tuần 5; hệ số trong (0, 1].');
  }
  final suggestions = <DebloatSuggestion>[], skipped = <Exercise, String>{};
  final values = <String, SetEntry>{};
  var preserved = 0;
  final eligible = canBuildDebloat(store);
  if (eligible) {
    for (final e in store.exercises.where((e) => !e.archived)) {
      final completed = [
        for (int w = 1; w <= 4; w++)
          [
            for (int s = 1; s <= e.sets; s++) store.entry(w, e, s),
          ].where((v) => v.complete).toList(),
      ];
      if (completed.every((v) => v.isEmpty)) {
        skipped[e] = 'Chưa có hiệp đã tập nào trong tuần 1–4.';
        continue;
      }
      final logged = completed.expand((v) => v).toList();
      final weeksUsed = completed.where((v) => v.isNotEmpty).length;
      final bw =
          !e.timed && !e.assisted && logged.every((v) => v.weight.isEmpty);
      final weekly = [for (int w = 1; w <= 4; w++) store.best(w, e)];
      final available = weekly.whereType<double>().toList();
      if (!bw && available.isEmpty) {
        skipped[e] = 'Thiếu tạ hoặc thời gian hợp lệ trong 4 tuần.';
        continue;
      }
      final target = RegExp(r'\d+')
          .allMatches(e.target)
          .map((m) => int.parse(m[0]!))
          .where((n) => n > 0)
          .toList();
      if (!e.timed && target.isEmpty) {
        skipped[e] = 'Mục tiêu reps chưa có số hợp lệ.';
        continue;
      }
      final raw = bw ? null : forecastWeekFive(weekly);
      final forecast = raw
          ?.clamp(
            0.0,
            available.reduce(e.assisted ? min : max),
          )
          .toDouble();
      final paired =
          !bw &&
          !e.timed &&
          logged.every(
            (v) => RegExp(
              r'^2\s*[x×]',
              caseSensitive: false,
            ).hasMatch(v.weight.trim()),
          );
      final weight = bw || e.timed
          ? ''
          : formatSuggestedWeight(
              e.assisted ? forecast! / factor : forecast! * factor,
              paired: paired,
              assisted: e.assisted,
            );
      final reps = e.timed
          ? '${max(5, roundDebloat(forecast! * factor, 5).toInt())}'
          : '${target.reduce(min)}';
      var empty = 0;
      for (int s = 1; s <= e.sets; s++) {
        if (store.entry(targetWeek, e, s).empty) {
          values[store.key(targetWeek, e, s)] = SetEntry(
            weight: weight,
            reps: reps,
            source: 'debloat',
          );
          empty++;
        }
      }
      preserved += e.sets - empty;
      suggestions.add(
        DebloatSuggestion(
          exercise: e,
          weeklyValues: weekly,
          rawForecast: raw,
          forecast: forecast,
          weight: weight,
          reps: reps,
          emptySets: empty,
          preservedSets: e.sets - empty,
          weeksUsed: weeksUsed,
          paired: paired,
        ),
      );
    }
  }
  return DebloatPlan(
    targetWeek: targetWeek,
    factor: factor,
    eligible: eligible,
    suggestions: suggestions,
    skipped: skipped,
    values: values,
    preservedSets: preserved,
  );
}

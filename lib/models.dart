import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Exercise {
  final String id, name, target;
  final int sets;
  final bool timed, assisted, archived;
  final List<String> primaryMuscles, secondaryMuscles;
  Exercise(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      target = j['target'],
      sets = j['sets'],
      timed = j['timed'],
      assisted = j['assisted'],
      archived = j['archived'] ?? false,
      primaryMuscles = List<String>.from(j['primaryMuscles'] ?? []),
      secondaryMuscles = List<String>.from(j['secondaryMuscles'] ?? []);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    'sets': sets,
    'timed': timed,
    'assisted': assisted,
    'archived': archived,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
  };
  String get shortName =>
      RegExp(r'\(([^)]+)\)').firstMatch(name)?.group(1) ?? name;
}

class TrainingDay {
  final String id, name, subtitle;
  final int weekday;
  final List<Exercise> exercises;
  TrainingDay(Map<String, dynamic> j)
    : id = j['id'] ?? 'day${j['weekday']}',
      name = j['name'],
      subtitle = j['subtitle'],
      weekday = j['weekday'],
      exercises = (j['exercises'] as List).map((e) => Exercise(e)).toList();
  List<Exercise> get activeExercises =>
      exercises.where((e) => !e.archived).toList();
  int get totalSets => activeExercises.fold(0, (a, e) => a + e.sets);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'weekday': weekday,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };
}

class SetEntry {
  final String weight, reps, note, source;
  const SetEntry({
    this.weight = '',
    this.reps = '',
    this.note = '',
    this.source = 'app',
  });
  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
    weight: j['weight'] as String,
    reps: j['reps'] as String,
    note: (j['note'] ?? '') as String,
    source: (j['source'] ?? 'app') as String,
  );
  Map<String, dynamic> toJson() => {
    'weight': weight,
    'reps': reps,
    'note': note,
    'source': source,
  };
  bool get suggested => source == 'debloat';
  bool get complete => !suggested && (int.tryParse(reps) ?? 0) > 0;
  bool get empty => weight.isEmpty && reps.isEmpty && note.isEmpty;
}

/// Converts only explicitly written weight; never adds a barbell weight.
double? parseWeight(String text) {
  final s = text
      .toLowerCase()
      .replaceAll(',', '.')
      .replaceAll(RegExp(r'\s|kg'), '')
      .replaceAll('×', 'x');
  final m = RegExp(r'^(?:(\d+)x)?(\d+(?:\.\d+)?)$').firstMatch(s);
  if (m == null) return null;
  return double.parse(m[2]!) * (m[1] == null ? 1 : int.parse(m[1]!));
}

String number(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

class TrainingStore {
  static const storageKey = 'trackta.data.v1';
  final SharedPreferences prefs;
  List<TrainingDay> days;
  Map<String, SetEntry> entries;
  int weeks;
  Set<int> debloatWeeks = {};
  bool isDebloat(int week) => debloatWeeks.contains(week);
  Future<void>? _pending;
  Future<T> transaction<T>(Future<T> Function() action) {
    final result = _pending == null
        ? action()
        : _pending!.then((_) => action());
    late final Future<void> tail;
    tail = result
        .then<void>((_) {}, onError: (Object e, StackTrace s) {})
        .whenComplete(() {
          if (identical(_pending, tail)) _pending = null;
        });
    _pending = tail;
    return result;
  }

  TrainingStore(this.prefs, this.days, this.entries, this.weeks);
  static Future<TrainingStore> load() async {
    final seed =
        jsonDecode(await rootBundle.loadString('assets/seed.json'))
            as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    final store = TrainingStore(
      prefs,
      (seed['days'] as List).map((d) => TrainingDay(d)).toList(),
      {},
      seed['weeks'],
    );
    final saved = prefs.getString(storageKey);
    if (saved != null) {
      store.readBackup(saved);
    } else {
      store.entries = (seed['entries'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, SetEntry.fromJson(v)),
      );
      await store.save();
    }
    return store;
  }

  List<Exercise> get exercises => days.expand((d) => d.exercises).toList();
  String key(int week, Exercise e, int set) => '$week:${e.id}:$set';
  SetEntry entry(int week, Exercise e, int set) =>
      entries[key(week, e, set)] ?? const SetEntry();
  int get latestWeek =>
      entries.keys.fold(1, (a, k) => max(a, int.parse(k.split(':')[0])));
  int done(int week, TrainingDay d) => d.activeExercises.fold(
    0,
    (a, e) =>
        a +
        [
          for (int s = 1; s <= e.sets; s++) entry(week, e, s),
        ].where((s) => s.complete).length,
  );
  int weekDone(int w) => days.fold(0, (a, d) => a + done(w, d));
  int get totalSets => days.fold(0, (a, d) => a + d.totalSets);
  double? best(int week, Exercise e) {
    final values = [for (int s = 1; s <= e.sets; s++) entry(week, e, s)]
        .where((v) => v.complete)
        .map((v) => e.timed ? double.tryParse(v.reps) : parseWeight(v.weight))
        .whereType<double>();
    if (values.isEmpty) return null;
    return e.assisted ? values.reduce(min) : values.reduce(max);
  }

  String backup() => const JsonEncoder.withIndent('  ').convert({
    'app': 'trackta',
    'version': 2,
    'weeks': weeks,
    'debloatWeeks': debloatWeeks.toList()..sort(),
    'days': days.map((d) => d.toJson()).toList(),
    'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
  });
  void readBackup(String text) {
    final j = jsonDecode(text);
    if (j is! Map ||
        j['app'] != 'trackta' ||
        ![1, 2].contains(j['version']) ||
        j['weeks'] is! int ||
        j['weeks'] < 8 ||
        j['weeks'] > 10000 ||
        j['entries'] is! Map) {
      throw const FormatException('File sao lưu không hợp lệ.');
    }
    final parsedDays = j['version'] == 2 ? parseDays(j['days']) : days;
    final labels = j.containsKey('debloatWeeks') ? j['debloatWeeks'] : [];
    if (labels is! List ||
        labels.any((w) => w is! int || w < 1 || w > j['weeks']) ||
        labels.toSet().length != labels.length) {
      throw const FormatException('Nhãn tuần debloat không hợp lệ.');
    }
    final validExercises = {
      for (final d in parsedDays)
        for (final e in d.exercises) e.id: e,
    };
    final parsed = <String, SetEntry>{};
    for (final item in (j['entries'] as Map).entries) {
      final parts = item.key.toString().split(':');
      if (parts.length != 3) {
        throw const FormatException('Mã hiệp không hợp lệ.');
      }
      final week = int.tryParse(parts[0]), set = int.tryParse(parts[2]);
      final ex = validExercises[parts[1]];
      if (week == null ||
          week < 1 ||
          week > j['weeks'] ||
          ex == null ||
          set == null ||
          set < 1 ||
          set > ex.sets ||
          item.value is! Map) {
        throw const FormatException('Tuần hoặc bài tập không hợp lệ.');
      }
      final v = SetEntry.fromJson(Map<String, dynamic>.from(item.value));
      if (v.weight.length > 40 ||
          v.reps.length > 5 ||
          v.note.length > 500 ||
          (v.weight.isNotEmpty &&
              (parseWeight(v.weight) == null ||
                  parseWeight(v.weight)! > 10000)) ||
          (v.reps.isNotEmpty &&
              ((int.tryParse(v.reps) ?? -1) < 1 ||
                  int.parse(v.reps) > 99999))) {
        throw const FormatException('Giá trị hiệp không hợp lệ.');
      }
      parsed[item.key] = v;
    }
    weeks = j['weeks'];
    days = parsedDays;
    entries = parsed;
    debloatWeeks = Set<int>.from(labels);
  }

  static List<TrainingDay> parseDays(dynamic raw) {
    const muscles = {
      'chest',
      'lats',
      'upperBack',
      'lowerBack',
      'frontShoulder',
      'sideShoulder',
      'rearShoulder',
      'biceps',
      'triceps',
      'forearms',
      'abs',
      'quads',
      'hamstrings',
      'glutes',
      'calves',
    };
    bool text(dynamic value, int max) =>
        value is String && value.trim().isNotEmpty && value.length <= max;
    bool id(dynamic value) =>
        value is String && RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(value);
    if (raw is! List || raw.isEmpty || raw.length > 14) {
      throw const FormatException('Lịch tập không hợp lệ.');
    }
    final dayIds = <String>{}, exerciseIds = <String>{};
    final parsed = <TrainingDay>[];
    for (final d in raw) {
      if (d is! Map ||
          !id(d['id']) ||
          !dayIds.add(d['id']) ||
          !text(d['name'], 100) ||
          d['subtitle'] is! String ||
          d['subtitle'].length > 300 ||
          d['weekday'] is! int ||
          d['weekday'] < 1 ||
          d['weekday'] > 7 ||
          d['exercises'] is! List ||
          d['exercises'].isEmpty ||
          d['exercises'].length > 60) {
        throw const FormatException('Buổi tập không hợp lệ.');
      }
      for (final e in d['exercises']) {
        if (e is! Map ||
            !id(e['id']) ||
            !exerciseIds.add(e['id']) ||
            !text(e['name'], 200) ||
            !text(e['target'], 40) ||
            e['sets'] is! int ||
            e['sets'] < 1 ||
            e['sets'] > 30 ||
            e['timed'] is! bool ||
            e['assisted'] is! bool ||
            (e['timed'] && e['assisted']) ||
            (e['archived'] != null && e['archived'] is! bool)) {
          throw const FormatException('Bài tập không hợp lệ.');
        }
        final primary = e['primaryMuscles'] ?? [],
            secondary = e['secondaryMuscles'] ?? [];
        if (primary is! List ||
            secondary is! List ||
            primary.any((m) => !muscles.contains(m)) ||
            secondary.any((m) => !muscles.contains(m)) ||
            primary.toSet().length != primary.length ||
            secondary.toSet().length != secondary.length ||
            primary.toSet().intersection(secondary.toSet()).isNotEmpty) {
          throw const FormatException('Nhóm cơ không hợp lệ.');
        }
      }
      final day = TrainingDay(Map<String, dynamic>.from(d));
      if (day.activeExercises.isEmpty) {
        throw const FormatException('Mỗi buổi cần ít nhất một bài đang tập.');
      }
      parsed.add(day);
    }
    return parsed;
  }

  Future<void> save() async {
    if (!await prefs.setString(storageKey, backup())) {
      throw Exception('Không thể lưu trên thiết bị.');
    }
  }

  Future<void> update(int week, Exercise e, int set, SetEntry value) =>
      transaction(() async {
        final k = key(week, e, set), old = entries[k];
        if (value.empty) {
          entries.remove(k);
        } else {
          entries[k] = value;
        }
        try {
          await save();
        } catch (_) {
          if (old == null) {
            entries.remove(k);
          } else {
            entries[k] = old;
          }
          rethrow;
        }
      });

  Future<void> addWeek() => transaction(() async {
    weeks++;
    try {
      await save();
    } catch (_) {
      weeks--;
      rethrow;
    }
  });

  Future<int> applyDebloat(int week, Map<String, SetEntry> values) =>
      transaction(() async {
        if (week != 5 ||
            !List.generate(4, (i) => i + 1).every(
              (w) => entries.entries.any(
                (e) => e.key.startsWith('$w:') && e.value.complete,
              ),
            )) {
          throw const FormatException('Cần hiệp đã tập ở cả tuần 1–4.');
        }
        final old = backup();
        var filled = 0;
        try {
          for (final item in values.entries) {
            if (!item.key.startsWith('$week:') || !item.value.suggested) {
              throw const FormatException('Gợi ý debloat không hợp lệ.');
            }
            if ((entries[item.key] ?? const SetEntry()).empty) {
              entries[item.key] = item.value;
              filled++;
            }
          }
          debloatWeeks.add(week);
          readBackup(backup());
          await save();
          return filled;
        } catch (_) {
          readBackup(old);
          rethrow;
        }
      });

  Future<void> restore(String raw) => transaction(() async {
    final previous = backup();
    try {
      readBackup(raw);
      await save();
    } catch (_) {
      readBackup(previous);
      rethrow;
    }
  });

  String csv() {
    String quote(String s) => '"${s.replaceAll('"', '""')}"';
    final rows = <List<String>>[
      [
        'Tuần',
        'Ngày',
        'Bài tập',
        'Hiệp',
        'Mục tiêu',
        'Tạ (nguyên bản)',
        'Reps / giây',
        'Ghi chú',
      ],
    ];
    for (int w = 1; w <= weeks; w++) {
      for (final d in days) {
        for (final e in d.exercises) {
          for (int s = 1; s <= e.sets; s++) {
            final v = entry(w, e, s);
            if (v.empty) continue;
            rows.add([
              '$w',
              'Thứ ${d.weekday + 1} - ${d.name}',
              e.name,
              '$s',
              e.target,
              v.weight,
              v.reps,
              v.note,
            ]);
          }
        }
      }
    }
    return '\uFEFF${rows.map((r) => r.map((s) => quote(RegExp(r'^[=+@\-\t\r]').hasMatch(s) ? "'$s" : s)).join(',')).join('\r\n')}';
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import 'models.dart';
import 'palette.dart';

const _primary = primary;
const _lime = lime;
const _muted = muted;
const _ink = ink;

enum MuscleGroup {
  chest('Ngực'),
  lats('Xô'),
  upperBack('Lưng trên'),
  lowerBack('Lưng dưới'),
  frontShoulder('Vai trước'),
  sideShoulder('Vai giữa'),
  rearShoulder('Vai sau'),
  biceps('Tay trước'),
  triceps('Tay sau'),
  forearms('Cẳng tay'),
  abs('Bụng'),
  quads('Đùi trước'),
  hamstrings('Đùi sau'),
  glutes('Mông'),
  calves('Bắp chân');

  final String label;
  const MuscleGroup(this.label);
}

class MuscleTargets {
  final List<MuscleGroup> primary, secondary;
  const MuscleTargets(this.primary, [this.secondary = const []]);
}

const exerciseMuscles = <String, MuscleTargets>{
  'd1e1': MuscleTargets(
    [MuscleGroup.chest],
    [MuscleGroup.frontShoulder, MuscleGroup.triceps],
  ),
  'd1e2': MuscleTargets(
    [MuscleGroup.lats],
    [MuscleGroup.upperBack, MuscleGroup.biceps],
  ),
  'd1e3': MuscleTargets(
    [MuscleGroup.frontShoulder, MuscleGroup.sideShoulder],
    [MuscleGroup.triceps],
  ),
  'd1e4': MuscleTargets(
    [MuscleGroup.lats, MuscleGroup.upperBack],
    [MuscleGroup.biceps, MuscleGroup.rearShoulder],
  ),
  'd1e5': MuscleTargets([MuscleGroup.biceps], [MuscleGroup.forearms]),
  'd1e6': MuscleTargets([MuscleGroup.triceps]),
  'd2e1': MuscleTargets([MuscleGroup.quads], [MuscleGroup.glutes]),
  'd2e2': MuscleTargets([MuscleGroup.quads], [MuscleGroup.glutes]),
  'd2e3': MuscleTargets([MuscleGroup.hamstrings]),
  'd2e4': MuscleTargets([MuscleGroup.calves]),
  'd2e5': MuscleTargets([MuscleGroup.abs]),
  'd2e6': MuscleTargets([MuscleGroup.abs], [MuscleGroup.glutes]),
  'd4e1': MuscleTargets(
    [MuscleGroup.chest],
    [MuscleGroup.frontShoulder, MuscleGroup.triceps],
  ),
  'd4e2': MuscleTargets([MuscleGroup.chest], [MuscleGroup.frontShoulder]),
  'd4e3': MuscleTargets(
    [MuscleGroup.frontShoulder, MuscleGroup.sideShoulder],
    [MuscleGroup.triceps],
  ),
  'd4e4': MuscleTargets([MuscleGroup.sideShoulder]),
  'd4e5': MuscleTargets([MuscleGroup.triceps]),
  'd5e1': MuscleTargets(
    [MuscleGroup.lats],
    [MuscleGroup.upperBack, MuscleGroup.biceps],
  ),
  'd5e2': MuscleTargets(
    [MuscleGroup.lats],
    [MuscleGroup.upperBack, MuscleGroup.biceps],
  ),
  'd5e3': MuscleTargets(
    [MuscleGroup.lats, MuscleGroup.upperBack],
    [MuscleGroup.biceps, MuscleGroup.rearShoulder],
  ),
  'd5e4': MuscleTargets([MuscleGroup.rearShoulder, MuscleGroup.upperBack]),
  'd5e5': MuscleTargets([MuscleGroup.biceps, MuscleGroup.forearms]),
  'd5e6': MuscleTargets([MuscleGroup.biceps], [MuscleGroup.forearms]),
  'd6e1': MuscleTargets(
    [MuscleGroup.hamstrings, MuscleGroup.glutes],
    [MuscleGroup.lowerBack],
  ),
  'd6e2': MuscleTargets(
    [MuscleGroup.quads, MuscleGroup.glutes],
    [MuscleGroup.hamstrings],
  ),
  'd6e3': MuscleTargets([MuscleGroup.quads]),
  'd6e4': MuscleTargets([MuscleGroup.calves]),
  'd6e5': MuscleTargets([MuscleGroup.abs]),
};

MuscleTargets? targetsFor(Exercise exercise) {
  if (exercise.primaryMuscles.isEmpty) return exerciseMuscles[exercise.id];
  return MuscleTargets(
    exercise.primaryMuscles.map((m) => MuscleGroup.values.byName(m)).toList(),
    exercise.secondaryMuscles.map((m) => MuscleGroup.values.byName(m)).toList(),
  );
}

Map<MuscleGroup, int> primarySetCounts(TrainingStore store, int week) {
  final counts = {for (final muscle in MuscleGroup.values) muscle: 0};
  for (final exercise in store.exercises) {
    final targets = targetsFor(exercise);
    if (targets == null) continue;
    final completeSets = [
      for (int set = 1; set <= exercise.sets; set++)
        store.entry(week, exercise, set),
    ].where((entry) => entry.complete).length;
    for (final muscle in targets.primary) {
      counts[muscle] = counts[muscle]! + completeSets;
    }
  }
  return counts;
}

class ExerciseMuscleView extends StatelessWidget {
  final Exercise exercise;
  final double height;
  const ExerciseMuscleView({
    super.key,
    required this.exercise,
    this.height = 202,
  });

  @override
  Widget build(BuildContext context) {
    final targets = targetsFor(exercise);
    if (targets == null) {
      return const Text('Bài tập này chưa được phân loại nhóm cơ.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MuscleMapPair(
          height: height,
          colors: {
            for (final muscle in targets.secondary) muscle: _lime,
            for (final muscle in targets.primary) muscle: _primary,
          },
        ),
        const SizedBox(height: 12),
        _LegendLine(color: _primary, label: 'Chính', muscles: targets.primary),
        if (targets.secondary.isNotEmpty) ...[
          const SizedBox(height: 7),
          _LegendLine(color: _lime, label: 'Phụ', muscles: targets.secondary),
        ],
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  final List<MuscleGroup> muscles;
  const _LegendLine({
    required this.color,
    required this.label,
    required this.muscles,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(top: 4, right: 8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      Text(
        '$label: ',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      Expanded(
        child: Text(
          muscles.map((m) => m.label).join(' · '),
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
        ),
      ),
    ],
  );
}

class MuscleMapPair extends StatelessWidget {
  final Map<MuscleGroup, Color> colors;
  final double height;
  const MuscleMapPair({super.key, required this.colors, this.height = 244});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mô hình cơ thể trước và sau; nhóm cơ được tô màu',
    child: Row(
      children: [
        for (final back in [false, true]) ...[
          if (back) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Text(
                    back ? 'MẶT SAU' : 'MẶT TRƯỚC',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: height,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _BodyPainter(back: back, colors: colors),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _BodyPainter extends CustomPainter {
  final bool back;
  final Map<MuscleGroup, Color> colors;
  _BodyPainter({required this.back, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 100, size.height / 240);
    canvas.save();
    canvas.translate(
      (size.width - scale * 100) / 2,
      (size.height - scale * 240) / 2,
    );
    canvas.scale(scale);
    final outline = Paint()..color = const Color(0xFF253631);
    final edge = Paint()
      ..color = const Color(0xFF17231F)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    void zone(MuscleGroup group, List<Offset> points) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(
        path,
        Paint()..color = colors[group] ?? const Color(0xFF3B4C45),
      );
      canvas.drawPath(path, edge);
    }

    List<Offset> p(List<double> coords) => [
      for (int i = 0; i < coords.length; i += 2)
        Offset(coords[i], coords[i + 1]),
    ];

    canvas.drawOval(const Rect.fromLTWH(42, 3, 16, 22), outline);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(46, 23, 8, 12),
        const Radius.circular(3),
      ),
      outline,
    );
    final torso = Path()
      ..addPolygon(
        p([
          37,
          32,
          63,
          32,
          70,
          43,
          65,
          83,
          61,
          116,
          55,
          132,
          45,
          132,
          39,
          116,
          35,
          83,
          30,
          43,
        ]),
        true,
      );
    canvas.drawPath(torso, outline);
    for (final mirror in [false, true]) {
      canvas.save();
      if (mirror) {
        canvas.translate(100, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawPath(
        Path()..addPolygon(
          p([
            32,
            35,
            38,
            43,
            35,
            68,
            30,
            92,
            24,
            117,
            17,
            115,
            18,
            88,
            22,
            59,
            25,
            43,
          ]),
          true,
        ),
        outline,
      );
      canvas.drawPath(
        Path()..addPolygon(
          p([
            43,
            126,
            50,
            126,
            49,
            175,
            46,
            213,
            44,
            235,
            33,
            235,
            34,
            212,
            34,
            181,
            37,
            145,
          ]),
          true,
        ),
        outline,
      );
      zone(
        MuscleGroup.sideShoulder,
        p([28, 34, 37, 34, 38, 44, 35, 54, 27, 53, 23, 45]),
      );
      if (back) {
        zone(
          MuscleGroup.rearShoulder,
          p([30, 36, 38, 35, 39, 45, 34, 55, 26, 52]),
        );
        zone(MuscleGroup.triceps, p([25, 55, 34, 56, 32, 72, 27, 83, 21, 78]));
        zone(
          MuscleGroup.forearms,
          p([21, 81, 29, 87, 25, 110, 18, 113, 17, 100]),
        );
        zone(
          MuscleGroup.upperBack,
          p([38, 36, 48, 36, 50, 61, 43, 63, 35, 57]),
        );
        zone(
          MuscleGroup.lats,
          p([35, 59, 45, 66, 49, 91, 47, 107, 39, 101, 35, 80]),
        );
        zone(
          MuscleGroup.lowerBack,
          p([47, 93, 50, 94, 50, 119, 43, 117, 40, 107]),
        );
        zone(
          MuscleGroup.glutes,
          p([41, 121, 50, 121, 49, 143, 38, 143, 36, 133]),
        );
        zone(
          MuscleGroup.hamstrings,
          p([38, 145, 48, 145, 47, 178, 43, 190, 36, 186, 34, 171]),
        );
      } else {
        zone(
          MuscleGroup.frontShoulder,
          p([29, 36, 37, 35, 39, 43, 35, 53, 27, 52, 24, 44]),
        );
        zone(MuscleGroup.biceps, p([26, 56, 34, 57, 32, 73, 27, 82, 21, 77]));
        zone(
          MuscleGroup.forearms,
          p([21, 80, 28, 86, 25, 110, 18, 113, 17, 100]),
        );
        zone(
          MuscleGroup.chest,
          p([39, 43, 49, 45, 50, 68, 42, 74, 35, 70, 34, 54]),
        );
        zone(MuscleGroup.abs, p([42, 75, 50, 72, 50, 119, 44, 118, 39, 103]));
        zone(
          MuscleGroup.quads,
          p([39, 143, 49, 143, 47, 178, 44, 190, 36, 186, 35, 171]),
        );
      }
      zone(
        MuscleGroup.calves,
        p([36, 191, 44, 193, 46, 209, 43, 229, 35, 229, 34, 210]),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.back != back || !mapEquals(old.colors, colors);
}

class MuscleAnalysisPage extends StatefulWidget {
  final TrainingStore store;
  final int initialWeek;
  const MuscleAnalysisPage({
    super.key,
    required this.store,
    required this.initialWeek,
  });
  @override
  State<MuscleAnalysisPage> createState() => _MuscleAnalysisPageState();
}

class _MuscleAnalysisPageState extends State<MuscleAnalysisPage> {
  late int week;
  @override
  void initState() {
    super.initState();
    week = widget.initialWeek;
  }

  @override
  Widget build(BuildContext context) {
    final counts = primarySetCounts(widget.store, week);
    final maxCount = counts.values.fold(0, math.max);
    final groups = MuscleGroup.values.toList()
      ..sort((a, b) {
        final comparison = counts[b]!.compareTo(counts[a]!);
        return comparison != 0 ? comparison : a.index.compareTo(b.index);
      });
    final colors = {
      for (final group in groups)
        if (counts[group]! > 0)
          group: Color.lerp(
            const Color(0xFF638055),
            _lime,
            counts[group]! / math.max(1, maxCount),
          )!,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Phân tích nhóm cơ')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Tuần trước',
                      onPressed: week > 1 ? () => setState(() => week--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Tuần $week',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tuần sau',
                      onPressed: week < widget.store.weeks
                          ? () => setState(() => week++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${widget.store.weekDone(week)} hiệp đã ghi trong tuần',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 16),
                MuscleMapPair(colors: colors),
                const SizedBox(height: 18),
                const Text(
                  'Số hiệp theo nhóm cơ chính',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (maxCount == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Tuần này chưa có hiệp nào được ghi.',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 105,
                          child: Text(
                            group.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxCount == 0
                                  ? 0
                                  : counts[group]! / maxCount,
                              minHeight: 9,
                              color: colors[group] ?? _lime,
                              backgroundColor: const Color(0xFF35443C),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${counts[group]}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 15),
                const Text(
                  'Chỉ tính hiệp có reps hoặc thời gian. Một hiệp có thể thuộc hai nhóm cơ chính. Màu và phân loại là minh họa gần đúng, không đo mức kích hoạt cơ hay chất lượng tập.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

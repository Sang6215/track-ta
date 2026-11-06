import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'muscles.dart';
import 'palette.dart';

class ProgressPage extends StatefulWidget {
  final TrainingStore store;
  final int week;
  const ProgressPage({super.key, required this.store, required this.week});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  static const _rangeLabels = ['4 tuần', '3 tháng', 'Tất cả'];
  static const _rangeWeeks = [4, 12, 0];
  String? selected;
  int range = 0;
  bool volume = false;

  TrainingStore get store => widget.store;

  Exercise get exercise => store.exercises.firstWhere(
    (e) => e.id == (selected ?? 'd5e1'),
    orElse: () => store.exercises.first,
  );

  int get startWeek {
    final span = _rangeWeeks[range];
    return span == 0 ? 1 : max(1, widget.week - span + 1);
  }

  double? bestAllTime(Exercise e) {
    double? result;
    for (var w = 1; w <= store.weeks; w++) {
      final value = store.best(w, e);
      if (value == null) continue;
      result = result == null
          ? value
          : e.assisted
          ? min(result, value)
          : max(result, value);
    }
    return result;
  }

  int? bestWeek(Exercise e, double? pr) {
    if (pr == null) return null;
    for (var w = 1; w <= store.weeks; w++) {
      if (store.best(w, e) == pr) return w;
    }
    return null;
  }

  double? weeklyVolume(Exercise e, int week) {
    double total = 0;
    var any = false;
    for (var s = 1; s <= e.sets; s++) {
      final entry = store.entry(week, e, s);
      if (!entry.complete) continue;
      final reps = int.tryParse(entry.reps) ?? 0;
      if (reps <= 0) continue;
      any = true;
      if (e.timed) {
        total += reps.toDouble();
      } else {
        final weight = parseWeight(entry.weight) ?? 0;
        total += weight * reps;
      }
    }
    return any ? total : null;
  }

  int get streak {
    var w = widget.week, count = 0;
    while (w >= 1 && store.weekDone(w) > 0) {
      count++;
      w--;
    }
    return count;
  }

  int get sessionsThisWeek => store.days
      .where((d) => store.done(widget.week, d) > 0)
      .length;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final pr = bestAllTime(e);
    final prWeek = bestWeek(e, pr);
    final showVolume = volume && !e.timed;
    final values = [
      for (var w = startWeek; w <= widget.week; w++)
        showVolume ? weeklyVolume(e, w) : store.best(w, e),
    ];
    final weeks = [for (var w = startWeek; w <= widget.week; w++) w];
    final muscleCounts = primarySetCounts(store, widget.week);
    final groups = MuscleGroup.values.toList()
      ..sort((a, b) {
        final comparison = muscleCounts[b]!.compareTo(muscleCounts[a]!);
        return comparison != 0 ? comparison : a.index.compareTo(b.index);
      });
    final topMuscles = groups.where((g) => muscleCounts[g]! > 0).take(4).toList();
    final maxMuscle = topMuscles.isEmpty ? 0 : muscleCounts[topMuscles.first]!;
    final activeWeeks = List.generate(
      store.weeks,
      (i) => i + 1,
    ).where((w) => store.weekDone(w) > 0).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TIẾN ĐỘ',
                    style: TextStyle(
                      color: primary,
                      fontSize: 8.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Nhìn lại tiến độ',
                    style: TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$activeWeeks tuần có dữ liệu',
              style: const TextStyle(color: muted2, fontSize: 9.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _segmented(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _stat(
                'BUỔI TẬP',
                '$sessionsThisWeek',
                'tuần này',
                Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _stat(
                e.timed ? 'PR THỜI GIAN' : 'PR',
                pr == null ? '—' : number(pr),
                e.timed ? 'giây' : 'kg',
                Icons.emoji_events_outlined,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _stat(
                'CHUỖI',
                '$streak',
                'tuần',
                Icons.local_fire_department_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _exercisePicker(e),
        const SizedBox(height: 8),
        _chartCard(e, values, weeks, pr, prWeek),
        const SizedBox(height: 10),
        _muscleCard(topMuscles, muscleCounts, maxMuscle),
        const SizedBox(height: 20),
        const Text(
          'Chi tiết theo tuần',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (var w = 1; w <= store.weeks; w++)
          if ([
            for (var s = 1; s <= e.sets; s++) store.entry(w, e, s),
          ].any((v) => !v.empty))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tuần $w${store.isDebloat(w) ? ' · DEBLOAT' : ''}',
                    style: const TextStyle(
                      color: lime,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (var s = 1; s <= e.sets; s++)
                    if (!store.entry(w, e, s).empty)
                      historyRow(store.entry(w, e, s), s, e),
                ],
              ),
            ),
        const SizedBox(height: 6),
        const Text(
          'Tuần chưa ghi được để trống trên biểu đồ, không tính là 0.',
          style: TextStyle(color: muted2, fontSize: 10.5, height: 1.5),
        ),
      ],
    );
  }

  Widget _segmented() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: borderSoft),
    ),
    child: Row(
      children: [
        for (var i = 0; i < _rangeLabels.length; i++)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => range = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: range == i ? raised : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  _rangeLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: range == i ? primary : muted2,
                    fontSize: 10,
                    fontWeight: range == i
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _stat(String label, String value, String unit, IconData icon) =>
      Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: muted2,
                      fontSize: 7.5,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontSize: 23,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      unit,
                      style: const TextStyle(color: muted2, fontSize: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _exercisePicker(Exercise e) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: borderSoft),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        key: ValueKey('progress-picker-${e.id}'),
        value: e.id,
        isExpanded: true,
        isDense: true,
        dropdownColor: raised,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(Icons.expand_more, size: 18, color: muted2),
        style: const TextStyle(
          fontFamily: 'Barlow',
          fontSize: 11.5,
          color: Colors.white,
        ),
        items: [
          for (final d in store.days)
            for (final x in d.exercises)
              DropdownMenuItem(
                value: x.id,
                child: Text(
                  '${d.name} · ${x.shortName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
        onChanged: (v) => setState(() => selected = v),
      ),
    ),
  );

  Widget _chartCard(
    Exercise e,
    List<double?> values,
    List<int> weeks,
    double? pr,
    int? prWeek,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.timed
                        ? 'THỜI GIAN TỐT NHẤT'
                        : e.assisted
                        ? 'MỨC TRỢ LỰC THẤP NHẤT'
                        : volume && !e.timed
                        ? 'VOLUME TUẦN'
                        : 'MỨC TẠ CAO NHẤT',
                    style: const TextStyle(
                      color: muted2,
                      fontSize: 7.5,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!e.timed && !e.assisted)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderSoft),
                ),
                child: Row(
                  children: [
                    _metricChip('Tạ', !volume, () {
                      setState(() => volume = false);
                    }),
                    _metricChip('Volume', volume, () {
                      setState(() => volume = true);
                    }),
                  ],
                ),
              ),
          ],
        ),
        SizedBox(
          height: 152,
          child: values.every((v) => v == null)
              ? const Center(
                  child: Text(
                    'Chưa có dữ liệu cho bài tập này.',
                    style: TextStyle(color: muted2, fontSize: 11),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: CustomPaint(
                    painter: TrendPainter(values: values, weeks: weeks),
                    size: Size.infinite,
                  ),
                ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: lime,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      volume && !e.timed
                          ? 'Volume (kg × reps)'
                          : 'Giá trị tốt nhất',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted2, fontSize: 8.5),
                    ),
                  ),
                ],
              ),
            ),
            if (pr != null) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.emoji_events_outlined,
                size: 10,
                color: lime,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  'PR ${number(pr)}${e.timed ? 's' : 'kg'}${prWeek == null ? '' : ' · tuần $prWeek'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: lime, fontSize: 8.5),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _metricChip(String label, bool on, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: on ? raised : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: on ? primary : muted2,
          fontSize: 8,
          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );

  Widget _muscleCard(
    List<MuscleGroup> groups,
    Map<MuscleGroup, int> counts,
    int maxCount,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cân bằng tuần này',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MuscleAnalysisPage(store: store, initialWeek: widget.week),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'Bản đồ cơ',
                      style: TextStyle(
                        color: primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 1),
                    Icon(Icons.chevron_right, size: 12, color: primary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Tuần này chưa có hiệp nào được ghi.',
              style: TextStyle(color: muted2, fontSize: 10.5),
            ),
          )
        else ...[
          for (final group in groups) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: maxCount == 0 ? 0 : counts[group]! / maxCount,
                      minHeight: 4,
                      color: lime,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 18,
                  child: Text(
                    '${counts[group]}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            counts.values.any((c) => c == 0)
                ? 'Một vài nhóm cơ chưa có hiệp chính trong tuần này.'
                : 'Chỉ tính hiệp chính; chạm “Bản đồ cơ” để xem nhóm phụ.',
            style: const TextStyle(color: muted2, fontSize: 8.5),
          ),
        ],
      ],
    ),
  );

  Widget historyRow(SetEntry v, int s, Exercise e) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Hiệp $s${v.suggested ? ' · Gợi ý' : ''}',
              style: const TextStyle(color: muted2, fontSize: 11),
            ),
            const Spacer(),
            Text(
              e.timed
                  ? '${v.reps} giây'
                  : '${v.weight.isEmpty ? 'BW' : v.weight} × ${v.reps.isEmpty ? '—' : v.reps}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (v.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              v.note,
              style: const TextStyle(color: muted2, fontSize: 10),
            ),
          ),
      ],
    ),
  );
}

class TrendPainter extends CustomPainter {
  final List<double?> values;
  final List<int> weeks;
  TrendPainter({required this.values, required this.weeks});
  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, right = 8.0, top = 6.0, bottom = 18.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final best = values.whereType<double>();
    if (best.isEmpty) return;
    final rawMin = best.reduce(min), rawMax = best.reduce(max);
    final axisStep = _niceStep(
      rawMax == rawMin ? max(1.0, rawMax / 4) : (rawMax - rawMin) / 3,
    );
    var axisMin = (rawMin / axisStep).floor() * axisStep;
    var axisMax = (rawMax / axisStep).ceil() * axisStep;
    if (axisMax <= axisMin) {
      axisMin = max(0, rawMax - axisStep);
      axisMax = axisMin + axisStep * 2;
    }
    final span = axisMax - axisMin;

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (
      var value = axisMin;
      value <= axisMax + axisStep * .01;
      value += axisStep
    ) {
      final y = top + (axisMax - value) / span * chartHeight;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: _short(value),
          style: const TextStyle(color: muted2, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(left - label.width - 5, y - label.height / 2));
    }

    double xAt(int index) =>
        left + (values.length == 1 ? chartWidth / 2 : chartWidth * index / (values.length - 1));
    double yAt(double value) => top + (axisMax - value) / span * chartHeight;

    var previous = -1;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        previous = -1;
        continue;
      }
      final point = Offset(xAt(i), yAt(value));
      if (previous >= 0 && values[previous] != null) {
        final start = Offset(xAt(previous), yAt(values[previous]!));
        final area = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(point.dx, point.dy)
          ..lineTo(point.dx, top + chartHeight)
          ..lineTo(start.dx, top + chartHeight)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33D4F58A), Color(0x00D4F58A)],
            ).createShader(
              Rect.fromLTWH(left, top, chartWidth, chartHeight),
            ),
        );
        canvas.drawLine(
          start,
          point,
          Paint()
            ..color = lime
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawCircle(point, 3.2, Paint()..color = lime);
      previous = i;
    }

    final lastIndex = values.lastIndexWhere((v) => v != null);
    if (lastIndex >= 0) {
      final point = Offset(xAt(lastIndex), yAt(values[lastIndex]!));
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = lime
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final step = values.length <= 6 ? 1 : (values.length / 6).ceil();
    for (var i = 0; i < values.length; i++) {
      if (i % step != 0 && i != values.length - 1) continue;
      final label = TextPainter(
        text: TextSpan(
          text: 'T${weeks[i]}',
          style: const TextStyle(color: muted2, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          xAt(i) - label.width / 2,
          size.height - label.height,
        ),
      );
    }
  }

  double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    final residual = raw / magnitude;
    final nice = residual <= 1
        ? 1.0
        : residual <= 2
        ? 2.0
        : residual <= 2.5
        ? 2.5
        : residual <= 5
        ? 5.0
        : 10.0;
    return nice * magnitude;
  }

  String _short(double value) => value >= 10000
      ? '${(value / 1000).round()}k'
      : value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : number(value);

  @override
  bool shouldRepaint(covariant TrendPainter oldDelegate) => true;
}

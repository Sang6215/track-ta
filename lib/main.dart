import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'ai_coach.dart';
import 'debloat.dart';
import 'debloat_ui.dart';
import 'muscles.dart';
import 'palette.dart';
import 'photo_journal.dart';
import 'photos.dart';
import 'progress.dart';
import 'rest_alarm.dart';
import 'usb_sync.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ink,
    ),
  );
  try {
    final store = await TrainingStore.load();
    try {
      await PhotoJournal.recoverLostImage();
    } catch (_) {
      // A failed photo recovery must not block access to the workout log.
    }
    runApp(TrackApp(store: store));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Không thể mở dữ liệu đã lưu. Dữ liệu vẫn được giữ trên thiết bị. Hãy đóng và mở lại ứng dụng.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: main, child: const Text('Thử lại')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackApp extends StatelessWidget {
  final TrainingStore store;
  const TrackApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Track Tạ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Barlow',
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: Color(0xFFF3F6EF),
        secondary: lime,
        onSecondary: ink,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 54,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSoft,
        space: 1,
        thickness: 1,
      ),
    ),
    home: Home(store: store),
  );
}

class Home extends StatefulWidget {
  final TrainingStore store;
  const Home({super.key, required this.store});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  TrainingStore get store => widget.store;
  late int week, day;
  int tab = 0;
  String? expandedExerciseId;
  @override
  void initState() {
    super.initState();
    week = store.latestWeek;
    day = store.days.lastIndexWhere((d) => store.done(week, d) > 0);
    if (day < 0) day = 0;
  }

  String get openExerciseId {
    final exercises = store.days[day].activeExercises;
    final pinned = expandedExerciseId;
    if (pinned != null && exercises.any((e) => e.id == pinned)) return pinned;
    for (final exercise in exercises) {
      for (var s = 1; s <= exercise.sets; s++) {
        if (!store.entry(week, exercise, s).complete) return exercise.id;
      }
    }
    return exercises.first.id;
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> pickWeek() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chọn tuần tập',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, -1),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm tuần'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: store.weeks,
                itemBuilder: (c, i) => ListTile(
                  title: Text(
                    'Tuần ${i + 1}${store.isDebloat(i + 1) || (i == 4 && canBuildDebloat(store)) ? ' · Debloat' : ''}',
                  ),
                  subtitle: Text(
                    '${store.weekDone(i + 1)} / ${store.totalSets} hiệp đã ghi',
                  ),
                  trailing: week == i + 1
                      ? const Icon(Icons.check_circle, color: primary)
                      : null,
                  onTap: () => Navigator.pop(context, i + 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    if (result == -1) {
      try {
        await store.addWeek();
        if (mounted) setState(() => week = store.weeks);
      } catch (_) {
        message('Chưa lưu được tuần mới. Vui lòng thử lại.');
      }
    } else {
      setState(() {
        week = result;
        expandedExerciseId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.fitness_center, color: onPrimary, size: 17),
          ),
          const SizedBox(width: 8),
          const Text(
            'track tạ',
            style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontSize: 22,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -.4,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Đồng hồ nghỉ',
          onPressed: () => showModalBottomSheet(
            context: context,
            showDragHandle: true,
            builder: (_) => const RestTimer(),
          ),
          icon: const Icon(Icons.timer_outlined, size: 21),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: IndexedStack(
            index: tab,
            children: [
              workout(),
              ProgressPage(store: store, week: week),
              tab == 2 ? const PhotosPage() : const SizedBox.shrink(),
              settings(),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: _HomeNav(
      index: tab,
      onSelected: (i) => setState(() => tab = i),
    ),
  );
  Widget workout() {
    final d = store.days[day];
    final completed = store.done(week, d);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
      children: [
        weekBar(),
        const SizedBox(height: 10),
        dayStrip(),
        if (canBuildDebloat(store) && week <= 5) ...[
          const SizedBox(height: 10),
          debloatBanner(),
        ],
        const SizedBox(height: 12),
        workoutCard(d, completed),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Bài tập hôm nay',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              'Chạm hiệp để ghi',
              style: TextStyle(color: muted2, fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < d.activeExercises.length; i++)
          d.activeExercises[i].id == openExerciseId
              ? exerciseCard(d.activeExercises[i], i)
              : nextExerciseRow(d.activeExercises[i], i),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined, size: 13, color: muted2),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Lưu trên điện thoại · Không cần mạng',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted2, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget weekBar() => Row(
    children: [
      IconButton(
        tooltip: 'Tuần trước',
        visualDensity: VisualDensity.compact,
        onPressed: week > 1
            ? () => setState(() {
                week--;
                expandedExerciseId = null;
              })
            : null,
        icon: const Icon(Icons.chevron_left, size: 20),
      ),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: pickWeek,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Tuần ${week.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: muted2,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (store.isDebloat(week)) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: lime.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DEBLOAT',
                          style: TextStyle(
                            color: lime,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        '${store.weekDone(week)}/${store.totalSets} hiệp tuần này',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted2, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Tuần sau',
        visualDensity: VisualDensity.compact,
        onPressed: week < store.weeks
            ? () => setState(() {
                week++;
                expandedExerciseId = null;
              })
            : pickWeek,
        icon: const Icon(Icons.chevron_right, size: 20),
      ),
    ],
  );

  Widget dayStrip() => Row(
    children: [
      for (var weekday = 1; weekday <= 7; weekday++) ...[
        if (weekday > 1) const SizedBox(width: 4),
        Expanded(child: dayChip(weekday)),
      ],
    ],
  );

  String dayLabel(int weekday) => weekday == 7 ? 'CN' : 'T${weekday + 1}';

  Widget dayChip(int weekday) {
    final index = store.days.indexWhere((d) => d.weekday == weekday);
    if (index < 0) {
      return Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderSoft),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayLabel(weekday),
              style: const TextStyle(
                color: muted2,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            const Icon(Icons.bedtime_outlined, size: 13, color: muted2),
          ],
        ),
      );
    }
    final d = store.days[index], selected = day == index;
    final done = store.done(week, d) > 0;
    return Material(
      color: selected ? primary : surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('day-${d.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          day = index;
          expandedExerciseId = null;
        }),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected ? null : Border.all(color: borderSoft),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayLabel(d.weekday),
                style: TextStyle(
                  color: selected
                      ? onPrimary.withValues(alpha: .62)
                      : muted2,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? onPrimary : Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? (selected ? onPrimary : lime)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget debloatBanner() => Container(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderSoft),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, size: 16, color: lime),
        const SizedBox(width: 9),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tuần debloat',
                style: TextStyle(
                  color: lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Gợi ý giảm tải cho tuần 5 từ dữ liệu tuần 1–4',
                style: TextStyle(color: muted2, fontSize: 9.5),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: previewDebloat,
          child: const Text('Xem & áp dụng', style: TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );

  Widget workoutCard(TrainingDay d, int completed) {
    final total = d.totalSets, pct = total == 0 ? 0.0 : completed / total;
    final finished = completed >= total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C405C)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D3049), Color(0xFF142033)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'HÔM NAY · ${d.weekday == 7 ? 'CHỦ NHẬT' : 'THỨ ${d.weekday + 1}'} · ${d.name.toUpperCase()}',
                  style: const TextStyle(
                    color: primary,
                    fontSize: 8.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: (finished ? lime : primary).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: (finished ? lime : primary).withValues(alpha: .25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: finished ? lime : primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      finished ? 'Đã xong' : 'Đang tập',
                      style: TextStyle(
                        color: finished ? lime : primary,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.subtitle,
                      style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontSize: 22,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${d.activeExercises.length} bài',
                          style: const TextStyle(color: muted, fontSize: 10.5),
                        ),
                        const Text(
                          '·',
                          style: TextStyle(color: muted2, fontSize: 10.5),
                        ),
                        Text(
                          '$completed/$total hiệp',
                          style: const TextStyle(
                            color: primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!finished)
                          Text(
                            '· còn ${total - completed} hiệp',
                            style: const TextStyle(
                              color: muted2,
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 4,
                        color: primary,
                        backgroundColor: Colors.white.withValues(alpha: .10),
                      ),
                    ),
                    Text(
                      '${(pct * 100).round()}%',
                      style: const TextStyle(
                        color: primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              color: primary,
              backgroundColor: Colors.white.withValues(alpha: .10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Tuần trước ${store.weekDone(week - 1)} hiệp',
                style: const TextStyle(color: muted2, fontSize: 9.5),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: openFocus,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'Vào focus',
                        style: TextStyle(
                          color: primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward, size: 11, color: primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget nextExerciseRow(Exercise e, int index) {
    final completed = [
      for (var s = 1; s <= e.sets; s++) store.entry(week, e, s),
    ].where((v) => v.complete).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: .018),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => expandedExerciseId = e.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderSoft),
            ),
            child: Row(
              children: [
                Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    color: primary,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${e.sets} hiệp · ${e.target}${e.timed ? ' giây' : ' reps'}',
                        style: const TextStyle(color: muted2, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$completed/${e.sets}',
                  style: const TextStyle(color: muted2, fontSize: 9.5),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: muted2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int nextSetFor(Exercise exercise) {
    for (var s = 1; s <= exercise.sets; s++) {
      if (!store.entry(week, exercise, s).complete) return s;
    }
    return 1;
  }

  Future<void> openFocus({Exercise? exercise, int? set}) async {
    final exercises = store.days[day].activeExercises;
    final target =
        exercise ??
        exercises.firstWhere(
          (e) => [
            for (var s = 1; s <= e.sets; s++) store.entry(week, e, s),
          ].any((v) => !v.complete),
          orElse: () => exercises.first,
        );
    await edit(target, set ?? nextSetFor(target));
  }

  void showMuscles(Exercise e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${e.sets} hiệp · ${e.target}${e.timed ? ' giây' : ' reps'}',
                  style: const TextStyle(color: muted2, fontSize: 11),
                ),
                const SizedBox(height: 14),
                ExerciseMuscleView(exercise: e, height: 178),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget exerciseCard(Exercise e, int index) {
    final done = [
      for (var s = 1; s <= e.sets; s++) store.entry(week, e, s),
    ].where((v) => v.complete).length;
    final previous = store.best(week - 1, e);
    final nextSet = nextSetFor(e);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
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
              Text(
                (index + 1).toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  color: primary,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontSize: 19,
                        height: 1.08,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      e.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted2, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              Text(
                '$done/${e.sets}',
                style: const TextStyle(color: muted2, fontSize: 9.5),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey('muscle-${e.id}'),
                tooltip: 'Cơ tác động',
                visualDensity: VisualDensity.compact,
                onPressed: () => showMuscles(e),
                icon: const Icon(
                  Icons.accessibility_new,
                  size: 17,
                  color: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            children: [
              Text.rich(
                TextSpan(
                  text: 'Tuần trước ',
                  style: const TextStyle(color: muted2, fontSize: 9.5),
                  children: [
                    TextSpan(
                      text: previous == null
                          ? '—'
                          : e.timed
                          ? '${number(previous)} giây'
                          : '${number(previous)} kg',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  text: 'Mục tiêu ',
                  style: const TextStyle(color: muted2, fontSize: 9.5),
                  children: [
                    TextSpan(
                      text: '${e.target}${e.timed ? ' giây' : ' reps'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (e.assisted)
                const Text(
                  'Trợ lực: ít kg hơn = ít hỗ trợ hơn',
                  style: TextStyle(color: lime, fontSize: 9),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const SizedBox(
                width: 22,
                child: Text(
                  'HIỆP',
                  style: TextStyle(
                    color: muted2,
                    fontSize: 7.5,
                    letterSpacing: .6,
                  ),
                ),
              ),
              const Expanded(
                flex: 3,
                child: Text(
                  'TUẦN TRƯỚC',
                  style: TextStyle(
                    color: muted2,
                    fontSize: 7.5,
                    letterSpacing: .6,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  e.timed ? 'THỜI GIAN' : 'TẠ × REPS',
                  style: const TextStyle(
                    color: muted2,
                    fontSize: 7.5,
                    letterSpacing: .6,
                  ),
                ),
              ),
              const SizedBox(width: 26),
            ],
          ),
          const SizedBox(height: 3),
          for (var s = 1; s <= e.sets; s++)
            setRow(e, s, active: s == nextSet),
        ],
      ),
    );
  }

  Widget setRow(Exercise e, int s, {bool active = false}) {
    final v = store.entry(week, e, s), previous = store.entry(week - 1, e, s);
    String display(SetEntry a) => a.empty
        ? '—'
        : e.timed
        ? '${a.reps.isEmpty ? '—' : a.reps} giây'
        : '${a.weight.isEmpty ? 'BW' : a.weight} × ${a.reps.isEmpty ? '—' : a.reps}';
    final highlight = active && !v.complete && !v.suggested;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: v.suggested
            ? primarySoft
            : v.complete
            ? completeSoft
            : highlight
            ? raised
            : ink.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: ValueKey('set-${e.id}-$s'),
          borderRadius: BorderRadius.circular(9),
          onTap: () => edit(e, s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: highlight
                  ? Border.all(color: primary.withValues(alpha: .45))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$s',
                    style: const TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontSize: 12,
                      color: muted2,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    week == 1 ? '—' : display(previous),
                    style: const TextStyle(fontSize: 10, color: muted2),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    v.empty
                        ? (highlight ? 'Ghi hiệp này' : '+ Ghi hiệp')
                        : '${v.suggested ? 'Gợi ý: ' : ''}${display(v)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: v.suggested
                          ? primary
                          : v.complete
                          ? lime
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 26,
                  child: highlight
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'GHI',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: onPrimary,
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : Icon(
                          v.suggested
                              ? Icons.lightbulb_outline
                              : v.complete
                              ? Icons.check_circle
                              : v.note.isNotEmpty
                              ? Icons.notes
                              : Icons.add_circle_outline,
                          color: v.suggested
                              ? primary
                              : v.complete
                              ? lime
                              : muted,
                          size: 16,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> previewDebloat() async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DebloatPreview(store: store),
    );
    if (count != null && mounted) {
      setState(() {
        week = 5;
        day = 0;
        expandedExerciseId = null;
      });
      message('Đã điền $count hiệp gợi ý. Mở và lưu từng hiệp sau khi tập.');
    }
  }

  Future<void> edit(Exercise e, int s) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SetEditor(store: store, week: week, exercise: e, set: s),
    );
    if (changed == true && mounted) {
      setState(() {});
      message('Đã lưu hiệp trên thiết bị');
    }
  }

  Widget settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Dữ liệu của bạn',
        style: TextStyle(
          fontFamily: 'BarlowCondensed',
          fontSize: 30,
          height: 1,
          fontWeight: FontWeight.w600,
          letterSpacing: -.4,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Lịch tập và nhật ký luôn sẵn sàng, kể cả khi offline.',
        style: TextStyle(color: muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => UsbSyncPage(store: store)),
          );
          if (mounted) {
            setState(() {
              day = day.clamp(0, store.days.length - 1);
              week = week.clamp(1, store.weeks);
            });
          }
        },
        icon: const Icon(Icons.usb_rounded),
        label: const Padding(
          padding: EdgeInsets.all(13),
          child: Text('Kết nối Windows qua USB'),
        ),
      ),
      const SizedBox(height: 16),
      panel(
        Icons.table_chart_outlined,
        'Đã nhập từ Excel',
        '28 bài tập · 5 buổi/tuần\n108 hiệp đã ghi ở tuần 1–3\nLich_Tap_5_Ngay_Tuan.xlsx',
      ),
      const SizedBox(height: 16),
      panel(
        Icons.info_outline,
        'Cách ghi và tính tạ',
        'Nhập 35kg hoặc 2x12.5kg. Biểu đồ quy đổi 2x12.5kg thành 25kg, không tự cộng thanh đòn. Giữ cùng cách ghi để so sánh các tuần.\n\nBW là bài dùng trọng lượng cơ thể, không nhập kg. Plank ghi số giây. Với hít xà trợ lực, kg là mức hỗ trợ.\n\nExcel chưa có ngày bắt đầu nên các tuần được giữ nguyên số thứ tự. Tuần trống không có nghĩa là đã bỏ tập.',
      ),
      const SizedBox(height: 16),
      panel(
        Icons.lightbulb_outline,
        'Công thức tuần debloat',
        'Tuần 5 được gợi ý khi tuần 1–4 đều có hiệp đã tập. Mỗi bài lấy mức tốt nhất ở các tuần có dữ liệu (bài có 1–3 tuần vẫn tính trên các tuần đó, tuần thiếu không tính là 0): tạ cao nhất, trợ lực thấp nhất hoặc giây cao nhất; hồi quy tuyến tính và kẹp vào 0–mức tốt nhất đã ghi (trợ lực: thấp nhất). Tạ/giây ×60%, trợ lực ÷60%; tạ làm tròn 2,5 kg (mỗi quả với 2x), trợ lực làm tròn lên, giây làm tròn 5. Chỉ điền hiệp trống. Gợi ý chưa tính hoàn thành cho tới khi mở và lưu hiệp.',
      ),
      const SizedBox(height: 16),
      const AiSettingsPanel(),
      const SizedBox(height: 22),
      const Text(
        'Sao lưu & chuyển máy',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Xuất bản sao lưu trước khi gỡ app hoặc xóa dữ liệu ứng dụng.',
        style: TextStyle(color: muted, height: 1.5),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => export(false),
        icon: const Icon(Icons.download_rounded),
        label: const Padding(
          padding: EdgeInsets.all(13),
          child: Text('Lưu bản sao lưu JSON'),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => export(true),
        icon: const Icon(Icons.grid_on_outlined),
        label: const Padding(
          padding: EdgeInsets.all(13),
          child: Text('Xuất nhật ký CSV (Excel)'),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: restore,
        icon: const Icon(Icons.restore_page_outlined),
        label: const Padding(
          padding: EdgeInsets.all(13),
          child: Text('Khôi phục từ bản sao lưu'),
        ),
      ),
      const SizedBox(height: 26),
      const Center(
        child: Text(
          'TRACK TẠ / 2.0.0\nDành cho những buổi tập của bạn.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11, height: 1.8),
        ),
      ),
    ],
  );
  Widget panel(IconData icon, String title, String text) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: primary),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.65),
        ),
      ],
    ),
  );
  Future<void> export(bool csv) async {
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final result = await FilePicker.saveFile(
        mimeType: csv ? 'text/csv' : 'application/json',
        dialogTitle: 'Lưu dữ liệu Track Tạ',
        fileName: 'track-ta-$stamp.${csv ? 'csv' : 'json'}',
        type: FileType.custom,
        allowedExtensions: [csv ? 'csv' : 'json'],
        bytes: Uint8List.fromList(
          utf8.encode(csv ? store.csv() : store.backup()),
        ),
      );
      if (result != null) {
        message('Đã xuất ${csv ? 'nhật ký CSV' : 'bản sao lưu'}');
      }
    } catch (_) {
      message('Chưa xuất được file. Hãy thử chọn thư mục khác.');
    }
  }

  Future<void> restore() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 10000000) {
        throw const FormatException();
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 10000000) {
        throw const FormatException();
      }
      final raw = utf8.decode(bytes),
          preview = TrainingStore(store.prefs, store.days, {}, 8);
      preview.readBackup(raw);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Khôi phục nhật ký?'),
          content: Text(
            'Bản sao lưu có ${preview.entries.length} hiệp, ${preview.weeks} tuần. Thao tác sẽ thay thế nhật ký hiện tại. Hãy lưu bản sao hiện tại nếu cần giữ lại.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Khôi phục'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await store.restore(raw);
        if (mounted) {
          setState(() {
            week = store.latestWeek;
            expandedExerciseId = null;
          });
        }
        message('Đã khôi phục nhật ký');
      }
    } catch (_) {
      message(
        'Không thể khôi phục. Kiểm tra file sao lưu Track Tạ; dữ liệu hiện tại vẫn được giữ.',
      );
    }
  }
}

class _HomeNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;
  const _HomeNav({required this.index, required this.onSelected});
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.insights_rounded,
    Icons.photo_camera_outlined,
    Icons.tune_rounded,
  ];
  static const _labels = ['Lịch tập', 'Tiến độ', 'Ảnh tháng', 'Dữ liệu'];
  @override
  Widget build(BuildContext context) => Material(
    color: ink,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: index == i,
                    button: true,
                    label: _labels[i],
                    child: InkWell(
                      onTap: () => onSelected(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22,
                            height: 2,
                            decoration: BoxDecoration(
                              color: index == i ? primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Icon(
                            _icons[i],
                            size: 20,
                            color: index == i ? primary : muted2,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _labels[i],
                            style: TextStyle(
                              color: index == i ? primary : muted2,
                              fontSize: 10.5,
                              fontWeight: index == i
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SetEditor extends StatefulWidget {
  final TrainingStore store;
  final int week, set;
  final Exercise exercise;
  const SetEditor({
    super.key,
    required this.store,
    required this.week,
    required this.exercise,
    required this.set,
  });
  @override
  State<SetEditor> createState() => _SetEditorState();
}

class _SetEditorState extends State<SetEditor> with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  late TextEditingController weight, reps, note;
  late int currentSet;
  bool saving = false, showMuscle = false, showNote = false, restBusy = false;
  DateTime? restDeadline;
  Timer? restTicker;
  String? restIssue;

  Exercise get e => widget.exercise;
  TrainingStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    currentSet = widget.set;
    final v = store.entry(widget.week, e, currentSet);
    weight = TextEditingController(text: v.weight);
    reps = TextEditingController(text: v.reps);
    note = TextEditingController(text: v.note);
    showNote = v.note.isNotEmpty;
    _refreshRest();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    restTicker?.cancel();
    weight.dispose();
    reps.dispose();
    note.dispose();
    super.dispose();
  }

  void _loadSet(int value) {
    final v = store.entry(widget.week, e, value);
    setState(() {
      currentSet = value;
      weight.text = v.weight;
      reps.text = v.reps;
      note.text = v.note;
      showNote = v.note.isNotEmpty;
    });
  }

  Future<void> save({bool clear = false}) async {
    if (saving || (!clear && !form.currentState!.validate())) return;
    setState(() => saving = true);
    try {
      await store.update(
        widget.week,
        e,
        currentSet,
        clear
            ? const SetEntry()
            : SetEntry(
                weight: weight.text.trim(),
                reps: reps.text.trim(),
                note: note.text.trim(),
              ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa lưu được. Hãy thử lại.')),
        );
      }
    }
  }

  Future<void> _refreshRest() async {
    try {
      final saved = await RestAlarm.status();
      if (!mounted) return;
      setState(() => restDeadline = saved);
      if (saved != null) {
        restTicker?.cancel();
        restTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            if (restDeadline != null &&
                DateTime.now().isAfter(restDeadline!)) {
              restDeadline = null;
              restTicker?.cancel();
            }
          });
        });
      }
    } catch (_) {
      // Desktop and widget tests have no alarm channel; ignore.
    }
  }

  Future<void> _startRest(int seconds) async {
    if (restBusy) return;
    setState(() {
      restBusy = true;
      restIssue = null;
    });
    try {
      if (!await RestAlarm.requestNotifications()) {
        if (mounted) {
          setState(() {
            restBusy = false;
            restIssue = 'notification_permission';
          });
        }
        return;
      }
      final deadline = await RestAlarm.start(seconds);
      if (!mounted) return;
      setState(() {
        restDeadline = deadline;
        restBusy = false;
      });
      _refreshRest();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          restBusy = false;
          restIssue = error.code;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          restBusy = false;
          restIssue = 'unavailable';
        });
      }
    }
  }

  Future<void> _stopRest() async {
    try {
      await RestAlarm.cancel();
    } catch (_) {
      // Ignore when the platform channel is not available.
    }
    restTicker?.cancel();
    if (mounted) setState(() => restDeadline = null);
  }

  int get restSeconds {
    final deadline = restDeadline;
    if (deadline == null) return 0;
    final value = (deadline.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil();
    return value > 0 ? value : 0;
  }

  void _stepWeight(double direction) {
    final source = weight.text.trim().isEmpty
        ? store.entry(widget.week - 1, e, currentSet).weight
        : weight.text;
    final perSide = source.toLowerCase().contains('x');
    final current = parseWeight(source) ?? 0;
    final next = max(0.0, current + direction * (perSide ? 5 : 2.5));
    weight.text = perSide ? '2x${number(next / 2)}' : number(next);
  }

  void _applyWeight(String value) {
    final perSide = weight.text.toLowerCase().contains('x');
    weight.text = perSide
        ? '2x${number((double.tryParse(value) ?? 0) / 2)}'
        : value;
  }

  void _stepReps(int direction) {
    final step = e.timed ? 5 : 1;
    final current = int.tryParse(reps.text) ?? 0;
    final next = current + direction * step;
    reps.text = '${next < step ? step : next}';
  }

  List<String> get weightQuick {
    final source = weight.text.trim().isEmpty
        ? store.entry(widget.week - 1, e, currentSet).weight
        : weight.text;
    final perSide = source.toLowerCase().contains('x');
    final base = parseWeight(source) ?? 0;
    final step = perSide ? 5.0 : 2.5;
    return [base - step, base, base + step]
        .where((v) => v >= 0)
        .map(number)
        .toSet()
        .toList();
  }

  bool weightChipOn(String value) {
    final current = parseWeight(weight.text), chip = parseWeight(value);
    return current != null && chip != null && current == chip;
  }

  List<int> get repQuick {
    final current = int.tryParse(reps.text) ?? 0;
    if (e.timed) {
      if (current > 0) {
        return {max(5, current - 15), current, current + 15}.toList();
      }
      return [30, 60, 90];
    }
    final range = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(e.target);
    if (range != null) {
      final low = int.parse(range.group(1)!);
      final high = int.parse(range.group(2)!);
      return [low, high, high + 2];
    }
    if (current > 0) {
      return {max(1, current - 2), current, current + 2}.toList();
    }
    final target = int.tryParse(e.target) ?? 10;
    return {max(1, target - 2), target, target + 2}.toList();
  }

  @override
  Widget build(BuildContext context) {
    final exercises = store.days
        .firstWhere(
          (d) => d.exercises.any((x) => x.id == e.id),
          orElse: () => store.days.first,
        )
        .activeExercises;
    final index = exercises.indexWhere((x) => x.id == e.id);
    final targets = targetsFor(e);
    final completed = [
      for (var s = 1; s <= e.sets; s++) store.entry(widget.week, e, s),
    ].where((v) => v.complete).length;
    final previous = store.entry(widget.week - 1, e, currentSet);
    final previousBest = store.best(widget.week - 1, e);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !saving,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .94,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _topBar(index, exercises.length),
              Expanded(
                child: Form(
                  key: form,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, viewInsets + 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      _progress(completed),
                      const SizedBox(height: 12),
                      _hero(targets, index, exercises.length),
                      if (showMuscle) ...[
                        const SizedBox(height: 12),
                        ExerciseMuscleView(exercise: e, height: 150),
                      ],
                      const SizedBox(height: 12),
                      _setStrip(),
                      const SizedBox(height: 10),
                      _restBanner(),
                      const SizedBox(height: 10),
                      _inputs(previous, previousBest),
                      const SizedBox(height: 12),
                      if (showNote)
                        TextFormField(
                          controller: note,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Ghi chú',
                            hintText: 'Cảm nhận, kỹ thuật, mức hỗ trợ…',
                            counterText: '',
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() => showNote = true),
                            icon: const Icon(Icons.notes, size: 16),
                            label: const Text(
                              'Thêm ghi chú',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: saving ? null : () => save(),
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_rounded, size: 17),
                              const SizedBox(width: 6),
                              Text(
                                saving ? 'Đang lưu…' : 'Lưu hiệp',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!store.entry(widget.week, e, currentSet).empty)
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text(
                                          'Xóa dữ liệu hiệp này?',
                                        ),
                                        content: const Text(
                                          'Tạ, reps và ghi chú của hiệp này sẽ được xóa.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Hủy'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Xóa hiệp'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) save(clear: true);
                                  },
                            child: const Text(
                              'Xóa dữ liệu hiệp',
                              style: TextStyle(color: danger, fontSize: 11.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(int index, int total) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 2, 12, 2),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Đóng',
          onPressed: saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
        Expanded(
          child: Text(
            'BUỔI TẬP · BÀI ${index + 1}/$total',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: muted2,
              fontSize: 8.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: primarySoft,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            'TUẦN ${widget.week.toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: primary,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _progress(int completed) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Hiệp $currentSet/${e.sets}',
              style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontSize: 17,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$completed/${e.sets} hiệp đã ghi',
              style: const TextStyle(color: muted2, fontSize: 9.5),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: e.sets == 0 ? 0 : completed / e.sets,
            minHeight: 4,
            color: primary,
            backgroundColor: Colors.white.withValues(alpha: .10),
          ),
        ),
      ],
    ),
  );

  Widget _hero(MuscleTargets? targets, int index, int total) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'BÀI ${index + 1} / $total · HIỆP $currentSet',
        style: const TextStyle(
          color: primary,
          fontSize: 8.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        e.name,
        style: const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontSize: 28,
          height: 1.02,
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        e.shortName,
        style: const TextStyle(color: muted2, fontSize: 10),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (targets != null) ...[
            for (final muscle in targets.primary)
              _muscleChip('${muscle.label} · chính', primary),
            for (final muscle in targets.secondary)
              _muscleChip('${muscle.label} · phụ', lime),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => showMuscle = !showMuscle),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showMuscle
                        ? Icons.keyboard_arrow_up
                        : Icons.accessibility_new,
                    size: 13,
                    color: muted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    showMuscle ? 'Ẩn cơ tác động' : 'Cơ tác động',
                    style: const TextStyle(color: muted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _muscleChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 8.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _setStrip() => Row(
    children: [
      for (var s = 1; s <= e.sets; s++) ...[
        if (s > 1) const SizedBox(width: 5),
        Expanded(child: _setChip(s)),
      ],
    ],
  );

  Widget _setChip(int s) {
    final v = store.entry(widget.week, e, s);
    final selected = currentSet == s;
    final value = v.empty
        ? '—'
        : e.timed
        ? '${v.reps.isEmpty ? '—' : v.reps}s'
        : '${v.weight.isEmpty ? 'BW' : v.weight}×${v.reps.isEmpty ? '—' : v.reps}';
    return Material(
      color: selected
          ? primarySoft
          : v.complete
          ? completeSoft
          : surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _loadSet(s),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? primary : borderSoft,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                s.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 10,
                  color: selected ? primary : muted2,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: v.complete
                        ? lime
                        : selected
                        ? primary
                        : muted,
                  ),
                ),
              ),
              if (v.complete) ...[
                const SizedBox(width: 2),
                const Icon(Icons.check, size: 10, color: lime),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _restBanner() {
    final running = restDeadline != null && restSeconds > 0;
    final mm = restSeconds ~/ 60;
    final ss = (restSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: primary.withValues(alpha: .45)),
                ),
                alignment: Alignment.center,
                child: Text(
                  running ? '$mm:$ss' : '90',
                  style: TextStyle(
                    color: primary,
                    fontSize: running ? 8 : 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? 'Đang nghỉ giữa hiệp' : 'Nghỉ giữa hiệp',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      running
                          ? 'Hết giờ sẽ có chuông và rung'
                          : 'Bắt đầu 90 giây sau khi lưu hiệp',
                      style: const TextStyle(color: muted2, fontSize: 8.5),
                    ),
                  ],
                ),
              ),
              if (running) ...[
                TextButton(
                  onPressed: restBusy
                      ? null
                      : () => _startRest(restSeconds + 30),
                  child: const Text('+30s', style: TextStyle(fontSize: 10)),
                ),
                TextButton(
                  onPressed: _stopRest,
                  child: const Text(
                    'Bỏ qua',
                    style: TextStyle(color: muted2, fontSize: 10),
                  ),
                ),
              ] else
                TextButton(
                  onPressed: restBusy ? null : () => _startRest(90),
                  child: const Text('Bắt đầu', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
          if (restIssue != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 39, right: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  restIssue == 'notification_permission'
                      ? 'Cần quyền thông báo để báo hết giờ nghỉ.'
                      : 'Không bật được đồng hồ nền trên thiết bị này.',
                  style: const TextStyle(color: caution, fontSize: 8.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputs(SetEntry previous, double? previousBest) => Container(
    padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSoft),
    ),
    child: Column(
      children: [
        Row(
          children: [
            if (!e.timed) ...[
              Expanded(child: _weightField()),
              Container(
                width: 1,
                height: 84,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: borderSoft,
              ),
            ],
            Expanded(child: _repsField()),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            previous.empty
                ? 'Tuần trước chưa có dữ liệu'
                : e.timed
                ? 'Tuần trước ${previous.reps} giây'
                : 'Tuần trước ${previous.weight.isEmpty ? 'BW' : previous.weight} × ${previous.reps}${previousBest == null ? '' : ' · tốt nhất ${number(previousBest)} kg'}',
            style: const TextStyle(color: muted2, fontSize: 9),
          ),
        ),
      ],
    ),
  );

  Widget _weightField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        e.assisted ? 'TẠ TRỢ LỰC (KG)' : 'TẠ (KG)',
        style: const TextStyle(
          color: muted2,
          fontSize: 8,
          letterSpacing: .8,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          _stepButton(Icons.remove, () => _stepWeight(-1)),
          Expanded(
            child: TextFormField(
              key: const ValueKey('weight-input'),
              controller: weight,
              textAlign: TextAlign.center,
              maxLength: 40,
              style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: 'BW',
                hintStyle: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 24,
                  color: muted2,
                ),
              ),
              validator: (v) {
                if (v!.trim().isEmpty) return null;
                final n = parseWeight(v);
                return n == null || n > 10000 ? 'Nhập 35 hoặc 2x12.5' : null;
              },
            ),
          ),
          _stepButton(Icons.add, () => _stepWeight(1)),
        ],
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          for (final value in weightQuick) ...[
            if (value != weightQuick.first) const SizedBox(width: 3),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => setState(() => _applyWeight(value)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: weightChipOn(value)
                        ? primary
                        : Colors.white.withValues(alpha: .02),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: weightChipOn(value) ? onPrimary : muted,
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _repsField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        e.timed ? 'THỜI GIAN (GIÂY)' : 'REPS',
        style: const TextStyle(
          color: muted2,
          fontSize: 8,
          letterSpacing: .8,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          _stepButton(Icons.remove, () => _stepReps(-1)),
          Expanded(
            child: TextFormField(
              key: const ValueKey('reps-input'),
              controller: reps,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 5,
              style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                hintText: e.timed ? '60' : '10',
                hintStyle: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontSize: 24,
                  color: muted2,
                ),
              ),
              validator: (v) => v!.isNotEmpty && (int.tryParse(v) ?? 0) < 1
                  ? 'Nhập số lớn hơn 0'
                  : null,
            ),
          ),
          _stepButton(Icons.add, () => _stepReps(1)),
        ],
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          for (final value in repQuick) ...[
            if (value != repQuick.first) const SizedBox(width: 3),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => setState(() => reps.text = '$value'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: reps.text.trim() == '$value'
                        ? primary
                        : Colors.white.withValues(alpha: .02),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: reps.text.trim() == '$value'
                          ? onPrimary
                          : muted,
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _stepButton(IconData icon, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(7),
    onTap: onTap,
    child: Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: raised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderSoft),
      ),
      child: Icon(icon, size: 14),
    ),
  );
}

class AiSettingsPanel extends StatefulWidget {
  const AiSettingsPanel({super.key});
  @override
  State<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends State<AiSettingsPanel> {
  final keyInput = TextEditingController();
  final modelInput = TextEditingController();
  bool loaded = false, busy = false, hideKey = true, statusOk = false;
  String? status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await AiCoachConfig.load();
    if (!mounted) return;
    setState(() {
      keyInput.text = config.apiKey;
      modelInput.text =
          config.model == AiCoachConfig.defaultModel ? '' : config.model;
      loaded = true;
    });
  }

  @override
  void dispose() {
    keyInput.dispose();
    modelInput.dispose();
    super.dispose();
  }

  AiCoachConfig get _config => AiCoachConfig(
    apiKey: keyInput.text,
    model: modelInput.text.trim().isEmpty
        ? AiCoachConfig.defaultModel
        : modelInput.text.trim(),
  );

  Future<void> _save() async {
    if (keyInput.text.trim().isEmpty) {
      setState(() {
        statusOk = false;
        status = 'Ô key đang trống. Nhập API key trước khi lưu.';
      });
      return;
    }
    setState(() => busy = true);
    try {
      await _config.save();
      if (mounted) {
        setState(() {
          statusOk = true;
          status = 'Đã lưu cấu hình AI trên thiết bị.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          statusOk = false;
          status = 'Chưa lưu được. Hãy thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      // Never let an empty field overwrite the saved key: fall back to it.
      var config = _config;
      if (!config.ready) config = await AiCoachConfig.load();
      if (!config.ready) {
        throw const AiCoachException(
          'Ô key đang trống và chưa có key nào đã lưu. Nhập API key rồi bấm Lưu.',
        );
      }
      await AiCoach(config).ping();
      if (mounted) {
        setState(() {
          statusOk = true;
          status = 'Kết nối Gemini thành công.';
        });
      }
    } on AiCoachException catch (e) {
      if (mounted) {
        setState(() {
          statusOk = false;
          status = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          statusOk = false;
          status = 'Không kiểm tra được kết nối. Thử lại sau.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.psychology_alt_outlined, color: primary),
        const SizedBox(height: 14),
        const Text(
          'Trợ lý AI (Gemini)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        const Text(
          'Nhận xét và điều chỉnh nhẹ tuần debloat trong bản xem trước. Tùy chọn: không có key, ứng dụng vẫn đầy đủ tính năng với gợi ý công thức.',
          style: TextStyle(color: muted, fontSize: 13, height: 1.65),
        ),
        if (loaded) ...[
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('ai-key-input'),
            controller: keyInput,
            obscureText: hideKey,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'API key Google AI Studio',
              helperText: 'Tạo miễn phí tại aistudio.google.com/apikey',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: hideKey ? 'Hiện key' : 'Ẩn key',
                onPressed: () => setState(() => hideKey = !hideKey),
                icon: Icon(hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ai-model-input'),
            controller: modelInput,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Model (tùy chọn)',
              hintText: AiCoachConfig.defaultModel,
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('ai-save'),
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('ai-test'),
                onPressed: busy ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Kiểm tra kết nối'),
              ),
            ],
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                status!,
                style: TextStyle(
                  color: statusOk ? lime : danger,
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Key chỉ lưu trên thiết bị và không nằm trong bản sao lưu JSON hay dữ liệu USB. Khi bấm phân tích, dữ liệu tuần 1–4 (tên bài, mức tạ, dự báo) được gửi tới Google qua internet; không gửi ảnh hay ghi chú.',
          style: TextStyle(color: muted, fontSize: 11, height: 1.6),
        ),
      ],
    ),
  );
}

class RestTimer extends StatefulWidget {
  const RestTimer({super.key});
  @override
  State<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<RestTimer> with WidgetsBindingObserver {
  int seconds = 90;
  DateTime? deadline;
  Timer? ticker;
  bool busy = false;
  String? issue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final saved = await RestAlarm.status();
      if (!mounted) return;
      setState(() {
        if (saved != null) {
          deadline = saved;
          updateSeconds();
          beginTicking();
        } else if (deadline != null) {
          deadline = null;
          seconds = 0;
          ticker?.cancel();
        }
      });
    } catch (_) {
      if (mounted) setState(() => issue = 'unavailable');
    }
  }

  void updateSeconds() {
    if (deadline == null) return;
    final remaining =
        (deadline!.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    seconds = remaining > 0 ? remaining : 0;
    if (seconds == 0) {
      deadline = null;
      ticker?.cancel();
    }
  }

  void beginTicking() {
    ticker?.cancel();
    if (deadline == null) return;
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(updateSeconds);
    });
  }

  Future<void> start(int count) async {
    if (busy) return;
    setState(() {
      busy = true;
      issue = null;
    });
    try {
      if (!await RestAlarm.requestNotifications()) {
        if (mounted) setState(() => issue = 'notification_permission');
        return;
      }
      final saved = await RestAlarm.start(count);
      if (!mounted) return;
      setState(() {
        deadline = saved;
        updateSeconds();
        beginTicking();
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => issue = e.code);
    } catch (_) {
      if (mounted) setState(() => issue = 'unavailable');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    try {
      await RestAlarm.cancel();
      ticker?.cancel();
      if (mounted) {
        setState(() {
          deadline = null;
          seconds = 90;
          issue = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => issue = 'unavailable');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Nghỉ giữa hiệp',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          Text(
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w800,
              color: primary,
            ),
          ),
          Text(
            deadline != null
                ? 'Bạn có thể đóng app; hết giờ sẽ có chuông và rung.'
                : seconds == 0
                ? 'Sẵn sàng cho hiệp tiếp theo!'
                : 'Chọn thời gian nghỉ để bắt đầu.',
            style: const TextStyle(color: muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              for (final n in [60, 90, 120, 180])
                OutlinedButton(
                  onPressed: busy ? null : () => start(n),
                  child: Text('${n}s'),
                ),
            ],
          ),
          if (issue != null) ...[
            const SizedBox(height: 10),
            Text(
              issue == 'notification_permission'
                  ? 'Cho phép thông báo để nhận chuông và rung khi hết giờ.'
                  : issue == 'exact_alarm_permission'
                  ? 'Cho phép báo thức chính xác để đồng hồ báo đúng lúc khi app đã đóng.'
                  : 'Không thể bật đồng hồ nền trên thiết bị này.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: caution),
            ),
            if (issue == 'notification_permission')
              TextButton(
                onPressed: RestAlarm.openNotificationSettings,
                child: const Text('Mở cài đặt thông báo'),
              ),
            if (issue == 'exact_alarm_permission')
              TextButton(
                onPressed: RestAlarm.openExactAlarmSettings,
                child: const Text('Cho phép báo thức chính xác'),
              ),
            if (issue == 'exact_alarm_permission')
              const Text(
                'Sau khi cho phép, quay lại và chạm thời gian nghỉ lần nữa.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: deadline == null ? null : stop,
            child: const Text('Dừng đồng hồ'),
          ),
        ],
      ),
    ),
  );
}

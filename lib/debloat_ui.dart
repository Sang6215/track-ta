import 'package:flutter/material.dart';
import 'ai_coach.dart';
import 'debloat.dart';
import 'models.dart';
import 'palette.dart';

class DebloatPreview extends StatefulWidget {
  final TrainingStore store;
  final GeminiSend? aiSender;
  const DebloatPreview({super.key, required this.store, this.aiSender});
  @override
  State<DebloatPreview> createState() => _DebloatPreviewState();
}

class _DebloatPreviewState extends State<DebloatPreview> {
  bool saving = false;
  String? error;
  AiCoachConfig? aiConfig;
  AiAnalysis? ai;
  bool aiBusy = false;
  String? aiError;

  @override
  void initState() {
    super.initState();
    _initAi();
  }

  Future<void> _initAi() async {
    final config = await AiCoachConfig.load();
    if (!mounted) return;
    setState(() => aiConfig = config);
    if (config.ready) _runAi();
  }

  Future<void> _runAi() async {
    if (aiBusy || saving || aiConfig == null || !aiConfig!.ready) return;
    setState(() {
      aiBusy = true;
      aiError = null;
    });
    try {
      final analysis = await AiCoach(
        aiConfig!,
        send: widget.aiSender,
      ).analyze(buildDebloatPlan(widget.store));
      if (mounted) setState(() => ai = analysis);
    } on AiCoachException catch (e) {
      if (mounted) setState(() => aiError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => aiError = 'Không phân tích được bằng AI. Dùng gợi ý công thức.');
      }
    } finally {
      if (mounted) setState(() => aiBusy = false);
    }
  }

  void _explainSetup() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Trợ lý AI cho tuần debloat'),
      content: const Text(
        'Vào tab Dữ liệu → Trợ lý AI (Gemini), nhập API key tạo miễn phí tại aistudio.google.com/apikey rồi quay lại đây.\n\n'
        'Khi phân tích, dữ liệu tuần 1–4 (tên bài, mức tạ, dự báo) được gửi tới Google qua internet. '
        'Không có key, mọi tính năng vẫn hoạt động với gợi ý công thức.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final plan = buildDebloatPlan(widget.store);
    return PopScope(
      canPop: !saving,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tuần 5 · Debloat',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.fillCount} hiệp trống sẽ điền · ${plan.preservedSets} hiệp đã có được giữ nguyên (ở các bài đủ dữ liệu).',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hồi quy tuyến tính trên các tuần có dữ liệu (bài có 1–3 tuần vẫn tính; thiếu tuần không tính là 0), kẹp dự báo vào 0–mức tốt nhất đã ghi (trợ lực: thấp nhất). Tạ/giây ×60%; trợ lực ÷60%. Tạ làm tròn 2,5 kg mỗi quả khi ghi 2x; trợ lực làm tròn lên. Giây làm tròn 5, tối thiểu 5 giây. Gợi ý chưa tính là đã tập.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                _aiControls(),
                if (aiError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      aiError!,
                      style: const TextStyle(color: caution, fontSize: 12),
                    ),
                  ),
                if (ai != null && (ai!.summary.isNotEmpty || ai!.warnings.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  _aiSummaryCard(),
                ],
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    children: [
                      for (final s in plan.suggestions)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.exercise.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Tuần 1–4: ${s.weeklyValues.map((v) => v == null ? (s.rawForecast == null ? 'BW' : '—') : number(v)).join(' → ')} · Dữ liệu ${s.weeksUsed}/4 tuần',
                                ),
                                Text(
                                  'Dự báo: ${s.rawForecast == null ? 'BW' : number(s.rawForecast!)} · Sau giới hạn: ${s.forecast == null ? 'BW' : number(s.forecast!)}',
                                ),
                                Text(
                                  s.exercise.timed
                                      ? 'Gợi ý: ${s.reps} giây'
                                      : 'Gợi ý: ${s.weight.isEmpty ? 'BW' : s.weight} × ${s.reps} reps',
                                  style: const TextStyle(color: primary),
                                ),
                                _aiLines(s),
                                Text(
                                  'Điền ${s.emptySets} · Giữ ${s.preservedSets} hiệp',
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final skip in plan.skipped.entries)
                        ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(skip.key.name),
                          subtitle: Text(
                            'Bỏ qua: ${skip.value}'
                            '${ai?.byExercise[skip.key.id]?.comment == null ? '' : '\nAI: ${ai!.byExercise[skip.key.id]!.comment}'}',
                          ),
                        ),
                    ],
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                FilledButton(
                  onPressed:
                      saving || !plan.eligible || plan.suggestions.isEmpty
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            final fresh = buildDebloatPlan(widget.store);
                            final values = ai == null
                                ? fresh.values
                                : mergeAiValues(fresh, ai!);
                            final count = await widget.store.applyDebloat(
                              5,
                              values,
                            );
                            if (context.mounted) Navigator.pop(context, count);
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                saving = false;
                                error =
                                    'Chưa lưu được. Dữ liệu cũ được giữ nguyên; hãy thử lại.';
                              });
                            }
                          }
                        },
                  child: Text(
                    saving
                        ? 'Đang lưu…'
                        : 'Áp dụng vào tuần 5${ai == null ? '' : ' (kèm điều chỉnh AI)'}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiControls() {
    if (aiConfig == null) return const SizedBox.shrink();
    if (!aiConfig!.ready) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('ai-setup'),
          onPressed: _explainSetup,
          icon: const Icon(Icons.psychology_alt_outlined, size: 18),
          label: const Text('Phân tích bằng AI · Chưa cấu hình'),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('ai-run'),
        onPressed: aiBusy || saving ? null : _runAi,
        icon: aiBusy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.psychology_alt_outlined, size: 18),
        label: Text(
          aiBusy ? 'Đang phân tích…' : ai == null ? 'Phân tích bằng AI' : 'Phân tích lại',
        ),
      ),
    );
  }

  Widget _aiSummaryCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: primarySoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NHẬN XÉT TRỢ LÝ AI',
          style: TextStyle(
            color: lime,
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
        if (ai!.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(ai!.summary, style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ],
        for (final warning in ai!.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 15,
                  color: caution,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'AI chỉ được điều chỉnh trong ±20% giá trị công thức; ngoài biên sẽ giữ nguyên gợi ý.',
          style: TextStyle(color: muted, fontSize: 10.5),
        ),
      ],
    ),
  );

  Widget _aiLines(DebloatSuggestion s) {
    final advice = ai?.byExercise[s.exercise.id];
    if (advice == null) return const SizedBox.shrink();
    final adjusted = ai == null ? null : adjustedFor(s, ai!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (advice.comment.isNotEmpty)
          Text(
            'AI: ${advice.comment}',
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
        if (adjusted != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              s.exercise.timed
                  ? 'AI điều chỉnh: ${adjusted.reps} giây (công thức ${s.reps} giây)'
                  : 'AI điều chỉnh: ${adjusted.weight.isEmpty ? 'BW' : adjusted.weight} × ${adjusted.reps} (công thức ${s.weight.isEmpty ? 'BW' : s.weight} × ${s.reps})',
              style: const TextStyle(
                color: lime,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

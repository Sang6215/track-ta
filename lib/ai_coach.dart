import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'debloat.dart';
import 'models.dart';

/// Optional Gemini commentary for the deload preview. The plan itself stays
/// deterministic: an AI adjustment is accepted only when it lands within ±20%
/// of the formula value, and revalidation happens again at apply time.
class AiCoachConfig {
  static const storageKey = 'trackta.gemini.v1';
  static const defaultModel = 'gemini-2.5-flash';
  final String apiKey;
  final String model;
  const AiCoachConfig({required this.apiKey, required this.model});
  bool get ready => apiKey.trim().length >= 10;

  static Future<AiCoachConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return const AiCoachConfig(apiKey: '', model: defaultModel);
    try {
      final j = jsonDecode(raw);
      String key = '', model = '';
      if (j is Map) {
        if (j['key'] is String) key = j['key'] as String;
        if (j['model'] is String && (j['model'] as String).trim().isNotEmpty) {
          model = (j['model'] as String).trim();
        }
      }
      return AiCoachConfig(apiKey: key, model: model.isEmpty ? defaultModel : model);
    } catch (_) {
      return const AiCoachConfig(apiKey: '', model: defaultModel);
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode({'key': apiKey.trim(), 'model': model.trim()}),
    );
  }
}

class AiCoachException implements Exception {
  final String message;
  final int? status;
  const AiCoachException(this.message, {this.status});
  @override
  String toString() => message;
}

class AiExerciseAdvice {
  final String comment;
  final String? rawWeight, rawReps;
  const AiExerciseAdvice({
    required this.comment,
    this.rawWeight,
    this.rawReps,
  });
}

class AiAnalysis {
  final String summary;
  final List<String> warnings;
  final Map<String, AiExerciseAdvice> byExercise;
  const AiAnalysis({
    required this.summary,
    required this.warnings,
    required this.byExercise,
  });
}

typedef GeminiSend = Future<String> Function(
  Uri endpoint,
  String apiKey,
  String body,
);

String _statusMessage(int status) {
  if (status == 400 || status == 403) {
    return 'API key Gemini không hợp lệ hoặc tên model không được hỗ trợ. Kiểm tra lại trong mục Dữ liệu.';
  }
  if (status == 404) {
    return 'Không tìm thấy model. Kiểm tra tên model trong mục Dữ liệu.';
  }
  if (status == 429) {
    return 'Vượt hạn mức Gemini miễn phí. Thử lại sau hoặc dùng gợi ý công thức.';
  }
  return 'Gemini trả lỗi ($status). Dùng gợi ý công thức.';
}

Future<String> geminiSend(Uri endpoint, String apiKey, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 30));
    request.headers.set('content-type', 'application/json');
    request.headers.set('x-goog-api-key', apiKey);
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 90));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw AiCoachException(
        _statusMessage(response.statusCode),
        status: response.statusCode,
      );
    }
    return text;
  } on AiCoachException {
    rethrow;
  } on SocketException {
    throw const AiCoachException(
      'Không kết nối được internet. Dùng gợi ý công thức.',
    );
  } on TimeoutException {
    throw const AiCoachException(
      'AI phản hồi quá lâu. Dùng gợi ý công thức hoặc thử lại.',
    );
  } finally {
    client.close();
  }
}

String buildPrompt(DebloatPlan plan) {
  final items = [
    for (final s in plan.suggestions)
      {
        'id': s.exercise.id,
        'ten': s.exercise.name,
        'cachDo': s.exercise.timed
            ? 'giay'
            : s.exercise.assisted
            ? 'tro_luc'
            : (s.weight.isEmpty && s.rawForecast == null ? 'BW' : 'ta'),
        'tuan1_4': s.weeklyValues,
        'tuanCoDuLieu': s.weeksUsed,
        'duBaoGioiHan': s.forecast,
        'goiY': s.exercise.timed ? '${s.reps} giây' : s.weight,
        'repsGoiY': s.reps,
        'mucTieu': s.exercise.target,
      },
    for (final skip in plan.skipped.entries)
      {'id': skip.key.id, 'ten': skip.key.name, 'boQua': skip.value},
  ];
  return '''
Bạn là huấn luyện viên sức mạnh giàu kinh nghiệm. Người tập dùng tuần 5 làm tuần giảm tải (deload): khối lượng khoảng 60% dự báo tuyến tính từ tuần 1-4.

QUY ƯỚC DỮ LIỆU:
- tuan1_4: mức tốt nhất từng tuần (null = tuần chưa có dữ liệu). Đơn vị kg đã quy đổi (2x12.5kg = 25) hoặc giây khi cachDo là "giay".
- cachDo "tro_luc": kg là mức hỗ trợ của máy; số THẤP hơn nghĩa là ít hỗ trợ hơn, khó hơn.
- cachDo "BW": bài dùng trọng lượng cơ thể, chỉ cần reps.

NHIỆM VỤ - trả về ĐÚNG một đối tượng JSON, không kèm văn bản nào khác:
{"summary": "2-3 câu nhận xét chung về tiến bộ tuần 1-4 và chủ điểm tuần giảm tải",
 "warnings": ["cảnh báo ngắn nếu có, nếu không thì mảng rỗng"],
 "exercises": [{"id": "...", "comment": "một câu nhận xét hoặc gợi ý kỹ thuật ngắn", "weight": "chỉ khi cần điều chỉnh", "reps": "chỉ khi cần điều chỉnh"}]}

QUY TẮC ĐIỀU CHỈNH:
- Chỉ điều chỉnh khi có lý do rõ (sụt giảm bất thường, mức đứng yên, bài quá nhẹ/nặng so với xu hướng); nếu không thì bỏ weight và reps, chỉ viết comment.
- weight trong ±20% giá trị "goiY", reps trong ±20% "repsGoiY" và nằm trong khoảng mục tiêu khi có thể.
- Giữ nguyên định dạng của "goiY" (ví dụ "2x10kg" thì điều chỉnh cũng viết "2x...").
- Mỗi bài trong DỮ LIỆU đều cần một mục trong exercises (kể cả bài bị bỏ qua, chỉ có comment).

DỮ LIỆU:
${jsonEncode(items)}''';
}

String _cleanText(dynamic value, int limit) {
  if (value is! String) return '';
  final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length > limit ? text.substring(0, limit) : text;
}

SetEntry? validateAdjustment(DebloatSuggestion s, String? rawWeight, String? rawReps) {
  String? weight;
  if (rawWeight != null && rawWeight.trim().isNotEmpty) {
    weight = _acceptWeight(s, rawWeight);
  }
  String? reps;
  if (rawReps != null && rawReps.trim().isNotEmpty) {
    reps = _acceptReps(s, rawReps);
  }
  if (weight == null && reps == null) return null;
  return SetEntry(
    weight: weight ?? s.weight,
    reps: reps ?? s.reps,
    source: 'debloat',
  );
}

String? _acceptWeight(DebloatSuggestion s, String raw) {
  if (s.exercise.timed || s.weight.isEmpty) return null;
  final base = parseWeight(s.weight), value = parseWeight(raw);
  if (base == null || value == null) return null;
  final formatted = formatSuggestedWeight(
    value,
    paired: s.paired,
    assisted: s.exercise.assisted,
  );
  final back = parseWeight(formatted);
  final bound = base * 0.2;
  if (back == null || back < base - bound - 1e-9 || back > base + bound + 1e-9) {
    return null;
  }
  return formatted;
}

String? _acceptReps(DebloatSuggestion s, String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null || value < 1 || value > 999) return null;
  if (s.exercise.timed) {
    final base = int.tryParse(s.reps) ?? 0;
    if (base <= 0 || (value - base).abs() > base * 0.2 + 1e-9) return null;
    return '${max(5, roundDebloat(value.toDouble(), 5).toInt())}';
  }
  final target = RegExp(r'\d+')
      .allMatches(s.exercise.target)
      .map((m) => int.parse(m[0]!))
      .where((n) => n > 0)
      .toList();
  if (target.isEmpty) return null;
  return '${value.clamp(target.reduce(min), target.reduce(max))}';
}

SetEntry? adjustedFor(DebloatSuggestion s, AiAnalysis ai) {
  final advice = ai.byExercise[s.exercise.id];
  if (advice == null) return null;
  return validateAdjustment(s, advice.rawWeight, advice.rawReps);
}

/// Rebuilt against a fresh plan so late edits cannot smuggle stale numbers in;
/// adjusted entries only replace the empty-set keys the plan already fills.
Map<String, SetEntry> mergeAiValues(DebloatPlan plan, AiAnalysis ai) {
  final values = Map<String, SetEntry>.of(plan.values);
  for (final s in plan.suggestions) {
    final adjusted = adjustedFor(s, ai);
    if (adjusted == null) continue;
    for (int set = 1; set <= s.exercise.sets; set++) {
      final key = '${plan.targetWeek}:${s.exercise.id}:$set';
      if (values[key]?.suggested == true) values[key] = adjusted;
    }
  }
  return values;
}

class AiCoach {
  final AiCoachConfig config;
  final GeminiSend send;
  AiCoach(this.config, {GeminiSend? send}) : send = send ?? geminiSend;

  Uri get _endpoint => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent',
  );

  String _body(DebloatPlan plan, {required bool fastThinking}) => jsonEncode({
    'contents': [
      {'role': 'user', 'parts': [{'text': buildPrompt(plan)}]},
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'temperature': 0.3,
      // Thinking models can muse for over a minute on 28 exercises; this
      // task needs none of it (measured 75s with thinking, 10s without).
      if (fastThinking) 'thinkingConfig': {'thinkingBudget': 0},
    },
  });

  Future<AiAnalysis> analyze(DebloatPlan plan) async {
    if (!config.ready) {
      throw const AiCoachException(
        'Chưa cấu hình API key Gemini. Vào Dữ liệu → Trợ lý AI để nhập.',
      );
    }
    try {
      final raw = await send(
        _endpoint,
        config.apiKey.trim(),
        _body(plan, fastThinking: true),
      );
      return parseResponse(raw, plan);
    } on AiCoachException catch (e) {
      // Models without thinking support reject the field; retry once plainly.
      if (e.status != 400) rethrow;
      final raw = await send(
        _endpoint,
        config.apiKey.trim(),
        _body(plan, fastThinking: false),
      );
      return parseResponse(raw, plan);
    }
  }

  Future<void> ping() async {
    if (!config.ready) {
      throw const AiCoachException('Nhập và lưu API key trước khi kiểm tra.');
    }
    final body = jsonEncode({
      'contents': [
        {'role': 'user', 'parts': [{'text': 'Trả lời đúng một chữ: OK'}]},
      ],
      'generationConfig': {'maxOutputTokens': 8},
    });
    await send(_endpoint, config.apiKey.trim(), body);
  }
}

AiAnalysis parseResponse(String raw, DebloatPlan plan) {
  final Map<String, dynamic> envelope;
  try {
    envelope = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw const AiCoachException('Gemini trả dữ liệu không đọc được.');
  }
  if (envelope['error'] is Map) {
    final code = envelope['error']['code'];
    throw AiCoachException(
      code is int ? _statusMessage(code) : 'Gemini từ chối yêu cầu.',
    );
  }
  final candidates = envelope['candidates'];
  final parts = candidates is List &&
          candidates.isNotEmpty &&
          candidates.first is Map &&
          (candidates.first as Map)['content'] is Map
      ? (candidates.first as Map)['content']['parts']
      : null;
  final text = parts is List && parts.isNotEmpty && parts.first is Map
      ? (parts.first as Map)['text']
      : null;
  if (text is! String || text.trim().isEmpty) {
    throw const AiCoachException('Gemini không trả phân tích. Thử lại.');
  }
  var payload = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(payload);
  if (fence != null) payload = fence.group(1)!;
  final Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    throw const AiCoachException('Gemini trả JSON không hợp lệ.');
  }
  final known = <String>{
    for (final s in plan.suggestions) s.exercise.id,
    for (final e in plan.skipped.keys) e.id,
  };
  final advice = <String, AiExerciseAdvice>{};
  final exercises = data['exercises'];
  if (exercises is List) {
    for (final item in exercises) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || !known.contains(id)) continue;
      final weight = item['weight'], reps = item['reps'];
      advice[id] = AiExerciseAdvice(
        comment: _cleanText(item['comment'], 300),
        rawWeight: weight is String ? weight : null,
        rawReps: reps is String ? reps : null,
      );
    }
  }
  final warnings = <String>[];
  final rawWarnings = data['warnings'];
  if (rawWarnings is List) {
    for (final w in rawWarnings.take(6)) {
      final cleaned = _cleanText(w, 200);
      if (cleaned.isNotEmpty) warnings.add(cleaned);
    }
  }
  return AiAnalysis(
    summary: _cleanText(data['summary'], 600),
    warnings: warnings,
    byExercise: advice,
  );
}

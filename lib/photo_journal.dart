import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One private image per calendar month.
class PhotoJournal {
  static const pendingMonthKey = 'trackta.pendingPhotoMonth.v1';
  final Directory directory;

  PhotoJournal(this.directory);

  static Future<PhotoJournal> open() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}trackta_photos',
    );
    await directory.create(recursive: true);
    final journal = PhotoJournal(directory);
    // Recover a replacement interrupted between moving the original aside and
    // moving the new image into place.
    await for (final item in directory.list()) {
      if (item is! File || !item.path.endsWith('.jpg.old')) continue;
      final original = File(item.path.substring(0, item.path.length - 4));
      if (await original.exists()) {
        await item.delete();
      } else {
        await item.rename(original.path);
      }
    }
    return journal;
  }

  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static bool validMonth(String month) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month);
    if (match == null) return false;
    final number = int.parse(match[2]!);
    return number >= 1 && number <= 12;
  }

  static bool isPng(List<int> bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  File fileFor(String month) {
    if (!validMonth(month)) throw const FormatException('Tháng không hợp lệ');
    return File('${directory.path}${Platform.pathSeparator}$month.jpg');
  }

  Future<List<String>> months() async {
    final found = <String>[];
    for (final item in directory.listSync()) {
      if (item is! File) continue;
      final name = item.uri.pathSegments.last;
      if (name.endsWith('.jpg')) {
        final month = name.substring(0, name.length - 4);
        if (validMonth(month)) found.add(month);
      }
    }
    return found..sort((a, b) => b.compareTo(a));
  }

  Future<void> save(String month, String sourcePath) async {
    final target = fileFor(month);
    await directory.create(recursive: true);
    final temporary = File('${target.path}.new');
    final previous = File('${target.path}.old');
    if (await temporary.exists()) await temporary.delete();
    await File(sourcePath).copy(temporary.path);
    if (await previous.exists()) await previous.delete();
    if (await target.exists()) await target.rename(previous.path);
    try {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (await previous.exists()) await previous.rename(target.path);
      rethrow;
    }
  }

  Future<void> remove(String month) async {
    final file = fileFor(month);
    if (await file.exists()) await file.delete();
  }

  /// Android can terminate the activity while an external camera is open.
  static Future<void> recoverLostImage() async {
    final prefs = await SharedPreferences.getInstance();
    final month = prefs.getString(pendingMonthKey);
    if (month == null) return;
    final response = await ImagePicker().retrieveLostData();
    final images = response.files;
    if (validMonth(month) && images != null && images.isNotEmpty) {
      await (await open()).save(month, images.first.path);
    }
    await prefs.remove(pendingMonthKey);
  }
}

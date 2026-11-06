import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'palette.dart';
import 'photo_journal.dart';

String snapshotRevision(String raw) =>
    sha256.convert(utf8.encode(raw)).toString();

/// Available only while the user opens a USB session. The socket is loopback;
/// Windows reaches it with an explicitly selected adb USB port forward.
class UsbSyncServer {
  static const port = 47821;
  final TrainingStore store;
  final void Function(String) onEvent;
  final Directory? backupDirectory;
  final PhotoJournal? photoJournal;
  HttpServer? _server;
  Timer? _expiry;
  final String code;
  final String _token;
  int _failedPairs = 0;
  bool _paired = false;

  UsbSyncServer(
    this.store,
    this.onEvent, {
    this.backupDirectory,
    this.photoJournal,
  }) : code = (100000 + Random.secure().nextInt(900000)).toString(),
       _token = base64UrlEncode(
         List.generate(32, (_) => Random.secure().nextInt(256)),
       );

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _expiry = Timer(const Duration(minutes: 15), () {
      stop();
      onEvent('Phiên kết nối đã hết hạn. Bấm bắt đầu để tạo mã mới.');
    });
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    _expiry?.cancel();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > 24 * 1024 * 1024) {
        throw const FormatException('Dữ liệu quá lớn.');
      }
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Dữ liệu không hợp lệ.');
    }
    return data;
  }

  void _json(HttpRequest r, int status, Object data) {
    r.response.statusCode = status;
    r.response.headers.contentType = ContentType.json;
    r.response.headers.set('Cache-Control', 'no-store');
    r.response.write(jsonEncode(data));
  }

  Future<Map<String, dynamic>> _snapshot() => store.transaction(() async {
    final raw = store.backup();
    return {
      'protocol': 1,
      'appVersion': '1.5.0',
      'revision': snapshotRevision(raw),
      'data': jsonDecode(raw),
    };
  });

  Future<Directory> _backupDirectory() async {
    if (backupDirectory != null) {
      return backupDirectory!..createSync(recursive: true);
    }
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/trackta_usb_backups')
      ..createSync(recursive: true);
  }

  Future<String?> _photoRevision(File file) async => await file.exists()
      ? sha256.convert(await file.readAsBytes()).toString()
      : null;

  Future<PhotoJournal> _journal() async =>
      photoJournal ?? await PhotoJournal.open();

  Future<void> _handle(HttpRequest r) async {
    try {
      if (r.headers.value('origin') != null) {
        _json(r, 403, {'error': 'Chỉ kết nối từ ứng dụng Track Tạ Windows.'});
        return;
      }
      if (r.method == 'GET' && r.uri.path == '/health') {
        _json(r, 200, {'protocol': 1, 'appVersion': '1.5.0'});
        return;
      }
      if (r.method == 'POST' && r.uri.path == '/pair') {
        final body = await _body(r);
        if (_paired || _failedPairs >= 10 || body['code'] != code) {
          _failedPairs++;
          _json(r, 403, {
            'error':
                'Mã ghép nối không đúng hoặc đã được dùng. Tạo phiên mới trên điện thoại.',
          });
        } else {
          _paired = true;
          _json(r, 200, {'token': _token, ...await _snapshot()});
          onEvent('Đã ghép nối với Windows. Sẵn sàng nhận chỉnh sửa.');
        }
        return;
      }
      if (!_paired || r.headers.value('authorization') != 'Bearer $_token') {
        _json(r, 401, {'error': 'Hãy ghép nối lại bằng mã trên điện thoại.'});
        return;
      }
      if (r.method == 'GET' && r.uri.path == '/snapshot') {
        _json(r, 200, await _snapshot());
      } else if (r.method == 'PUT' && r.uri.path == '/snapshot') {
        final body = await _body(r);
        await store.transaction(() async {
          final old = store.backup();
          if (body['baseRevision'] != snapshotRevision(old)) {
            _json(r, 409, {
              'error':
                  'Điện thoại vừa thay đổi dữ liệu. Tải lại để so sánh trước khi gửi.',
            });
            return;
          }
          final raw = jsonEncode(body['data']);
          final preview = TrainingStore(
            store.prefs,
            store.days,
            {},
            store.weeks,
          )..readBackup(raw);
          final next = {for (final e in preview.exercises) e.id: e};
          for (final e in store.exercises) {
            if (!store.entries.keys.any((k) => k.split(':')[1] == e.id)) {
              continue;
            }
            final replacement = next[e.id];
            if (replacement == null ||
                replacement.timed != e.timed ||
                replacement.assisted != e.assisted) {
              throw const FormatException(
                'Bài có nhật ký cần giữ mã và cách đo. Hãy lưu trữ bài cũ và tạo bài mới.',
              );
            }
          }
          final directory = await _backupDirectory();
          await File(
            '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-before.json',
          ).writeAsString(old, flush: true);
          try {
            store.readBackup(raw);
            await store.save();
          } catch (_) {
            store.readBackup(old);
            rethrow;
          }
          final saved = store.backup();
          _json(r, 200, {
            'protocol': 1,
            'appVersion': '1.5.0',
            'revision': snapshotRevision(saved),
            'data': jsonDecode(saved),
          });
          onEvent(
            'Đã nhận lịch tập và nhật ký từ Windows. Bản cũ đã được sao lưu.',
          );
        });
      } else if (r.method == 'GET' && r.uri.path == '/photos') {
        final journal = await _journal();
        final items = <Map<String, dynamic>>[];
        for (final month in await journal.months()) {
          final file = journal.fileFor(month),
              bytes = await journal.fileFor(month).readAsBytes();
          items.add({
            'month': month,
            'revision': await _photoRevision(file),
            'size': bytes.length,
            'format': PhotoJournal.isPng(bytes) ? 'png' : 'jpg',
          });
        }
        _json(r, 200, {'items': items});
      } else if (r.uri.path.startsWith('/photos/')) {
        final month = r.uri.path.substring('/photos/'.length);
        if (!PhotoJournal.validMonth(month)) {
          throw const FormatException('Tháng không hợp lệ.');
        }
        final journal = await _journal();
        final file = journal.fileFor(month);
        if (r.method == 'GET') {
          if (!await file.exists()) {
            _json(r, 404, {'error': 'Tháng này chưa có ảnh.'});
          } else {
            final bytes = await file.readAsBytes();
            r.response.headers.contentType = ContentType(
              'image',
              PhotoJournal.isPng(bytes) ? 'png' : 'jpeg',
            );
            r.response.add(bytes);
          }
        } else if (r.method == 'PUT' || r.method == 'DELETE') {
          final body = await _body(r);
          await store.transaction(() async {
            final revision = await _photoRevision(file);
            if (body['baseRevision'] != revision) {
              _json(r, 409, {
                'error':
                    'Ảnh trên điện thoại đã thay đổi. Tải lại ảnh trước khi sửa.',
              });
              return;
            }
            List<int>? bytes;
            if (r.method == 'PUT') {
              if (body['contentBase64'] is! String) {
                throw const FormatException('Thiếu ảnh.');
              }
              bytes = base64Decode(body['contentBase64']);
              if (bytes.length > 15 * 1024 * 1024 ||
                  !(PhotoJournal.isPng(bytes) ||
                      (bytes.length > 3 &&
                          bytes[0] == 255 &&
                          bytes[1] == 216 &&
                          bytes[2] == 255))) {
                throw const FormatException(
                  'Chọn ảnh JPG/PNG không quá 15 MB.',
                );
              }
            }
            if (revision != null) {
              final backups = await _backupDirectory();
              await file.copy(
                '${backups.path}/$month-${DateTime.now().microsecondsSinceEpoch}.jpg',
              );
            }
            if (bytes == null) {
              await journal.remove(month);
            } else {
              final temp = File('${file.path}.usb');
              try {
                await temp.writeAsBytes(bytes, flush: true);
                await journal.save(month, temp.path);
              } finally {
                if (await temp.exists()) await temp.delete();
              }
            }
            _json(r, 200, {
              'month': month,
              'revision': await _photoRevision(file),
            });
            onEvent('Đã cập nhật ảnh tháng $month từ Windows.');
          });
        } else {
          _json(r, 405, {'error': 'Chức năng không được hỗ trợ.'});
        }
      } else {
        _json(r, 404, {'error': 'Chức năng không được hỗ trợ.'});
      }
    } on FormatException catch (e) {
      _json(r, 400, {
        'error': e.message.isEmpty ? 'Dữ liệu không hợp lệ.' : e.message,
      });
    } catch (_) {
      _json(r, 500, {
        'error':
            'Chưa hoàn tất thao tác. Dữ liệu đã lưu vẫn được giữ; hãy kết nối lại.',
      });
    } finally {
      await r.response.close();
    }
  }
}

class UsbSyncPage extends StatefulWidget {
  final TrainingStore store;
  const UsbSyncPage({super.key, required this.store});
  @override
  State<UsbSyncPage> createState() => _UsbSyncPageState();
}

class _UsbSyncPageState extends State<UsbSyncPage> {
  UsbSyncServer? server;
  bool busy = false;
  String message = 'Kết nối bằng cáp USB và nhập mã trên máy tính.';
  Future<void> start() async {
    setState(() => busy = true);
    final next = UsbSyncServer(widget.store, (text) {
      if (mounted) setState(() => message = text);
    });
    try {
      await next.start();
      if (!mounted) {
        await next.stop();
        return;
      }
      setState(() => server = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Chưa mở được kết nối. Đóng và mở lại màn hình này.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết nối Windows qua USB')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.usb_rounded, size: 64, color: primary),
          const SizedBox(height: 20),
          const Text(
            'Chỉnh sửa trên màn hình lớn',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Cắm điện thoại vào máy tính bằng cáp truyền dữ liệu.\n\n2. Bật Tùy chọn nhà phát triển → Gỡ lỗi USB, rồi cho phép máy tính này khi Android hỏi.\n\n3. Mở Track Tạ Windows, chọn điện thoại và nhập mã bên dưới. Giữ màn hình này mở khi đồng bộ.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),
          if (server == null)
            FilledButton.icon(
              onPressed: busy ? null : start,
              icon: const Icon(Icons.link),
              label: const Text('Bắt đầu kết nối'),
            )
          else ...[
            const Text(
              'MÃ GHÉP NỐI · HIỆU LỰC 15 PHÚT',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            SelectableText(
              server!.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 42,
                letterSpacing: 8,
                fontWeight: FontWeight.w800,
                color: primary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await server!.stop();
                if (mounted) {
                  setState(() {
                    server = null;
                    message = 'Đã đóng kết nối. Bạn có thể tạo mã mới.';
                  });
                }
              },
              child: const Text('Ngắt kết nối / tạo mã mới'),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(color: lime, height: 1.5),
          ),
          const SizedBox(height: 20),
          const Text(
            'Dữ liệu đi qua cáp USB. Lịch tập, nhật ký và ảnh cũ được sao lưu trước khi Windows gửi thay đổi.',
            style: TextStyle(color: muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

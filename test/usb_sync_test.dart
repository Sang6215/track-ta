import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:track_ta/models.dart';
import 'package:track_ta/photo_journal.dart';
import 'package:track_ta/usb_sync.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '1.1 backup migrates with editable program and original records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final original = await TrainingStore.load();
      final v1 = jsonDecode(original.backup()) as Map<String, dynamic>;
      v1['version'] = 1;
      v1.remove('days');
      SharedPreferences.setMockInitialValues({
        TrainingStore.storageKey: jsonEncode(v1),
      });
      final loaded = await TrainingStore.load();
      expect(loaded.entries.length, 108);
      expect(loaded.entry(1, loaded.exercises.first, 2).weight, '2x12.5kg');
      final next = jsonDecode(loaded.backup());
      next['days'][0]['exercises'][0]['name'] = 'Bench mới';
      next['days'][0]['exercises'][1]['archived'] = true;
      await loaded.restore(jsonEncode(next));
      final restarted = await TrainingStore.load();
      expect(restarted.exercises.first.name, 'Bench mới');
      expect(restarted.days.first.activeExercises.length, 5);
      expect(restarted.entries.length, 108);
    },
  );

  test(
    'USB authentication, revision checks and recoverable photo changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await TrainingStore.load();
      final temp = await Directory.systemTemp.createTemp('trackta-usb-test-');
      final journal = PhotoJournal(
        Directory('${temp.path}/photos')..createSync(),
      );
      final server = UsbSyncServer(
        store,
        (_) {},
        backupDirectory: Directory('${temp.path}/backups'),
        photoJournal: journal,
      );
      await server.start();
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttpOverrides(),
      );
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await temp.delete(recursive: true);
      });
      String? token;
      Future<(int, Map<String, dynamic>)> request(
        String method,
        String path, [
        Map<String, dynamic>? data,
      ]) async {
        final r = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:${UsbSyncServer.port}$path'),
        );
        if (token != null) r.headers.set('Authorization', 'Bearer $token');
        if (data != null) {
          r.headers.contentType = ContentType.json;
          r.write(jsonEncode(data));
        }
        final response = await r.close();
        return (
          response.statusCode,
          jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>,
        );
      }

      expect((await request('GET', '/snapshot')).$1, 401);
      expect((await request('POST', '/pair', {'code': 'bad'})).$1, 403);
      final paired = await request('POST', '/pair', {'code': server.code});
      expect(paired.$1, 200);
      token = paired.$2['token'];
      final raw = store.backup(), next = jsonDecode(raw);
      next['days'][0]['exercises'][0]['name'] = 'Bench từ Windows';
      next['debloatWeeks'] = [5];
      next['entries']['5:d1e1:1'] = {
        'weight': '25kg',
        'reps': '6',
        'note': '',
        'source': 'debloat',
      };
      final result = await request('PUT', '/snapshot', {
        'baseRevision': paired.$2['revision'],
        'data': next,
      });
      expect(result.$1, 200);
      expect(store.exercises.first.name, 'Bench từ Windows');
      expect(store.isDebloat(5), true);
      expect(store.weekDone(5), 0);
      expect(result.$2['data']['entries']['5:d1e1:1']['source'], 'debloat');
      expect((await TrainingStore.load()).isDebloat(5), true);
      expect(
        (await Directory('${temp.path}/backups').list().toList()).length,
        1,
      );
      expect(
        (await request('PUT', '/snapshot', {
          'baseRevision': paired.$2['revision'],
          'data': next,
        })).$1,
        409,
      );
      final wrong = jsonDecode(store.backup());
      wrong['days'][0]['exercises'][0]['timed'] = true;
      expect(
        (await request('PUT', '/snapshot', {
          'baseRevision': result.$2['revision'],
          'data': wrong,
        })).$1,
        400,
      );
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
      final photo = await request('PUT', '/photos/2026-10', {
        'baseRevision': null,
        'contentBase64': png,
      });
      expect(photo.$1, 200);
      expect((await request('GET', '/photos')).$2['items'].length, 1);
      expect(
        (await request('DELETE', '/photos/2026-10', {
          'baseRevision': 'stale',
        })).$1,
        409,
      );
      expect(await journal.fileFor('2026-10').exists(), true);
      expect(
        (await request('DELETE', '/photos/2026-10', {
          'baseRevision': photo.$2['revision'],
        })).$1,
        200,
      );
      expect(await journal.fileFor('2026-10').exists(), false);
      expect(
        (await Directory('${temp.path}/backups').list().toList()).length,
        2,
      );
    },
  );
}

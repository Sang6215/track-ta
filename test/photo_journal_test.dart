import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:track_ta/photo_journal.dart';

void main() {
  test(
    'Monthly photos can be replaced and removed without changing other months',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trackta-photos-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final journal = PhotoJournal(directory);
      final first = File('${directory.path}${Platform.pathSeparator}first.tmp');
      final second = File(
        '${directory.path}${Platform.pathSeparator}second.tmp',
      );
      await first.writeAsBytes([1, 2, 3]);
      await second.writeAsBytes([4, 5, 6]);

      await journal.save('2026-08', first.path);
      await journal.save('2026-09', second.path);
      expect(await journal.months(), ['2026-09', '2026-08']);
      expect(await journal.fileFor('2026-08').readAsBytes(), [1, 2, 3]);

      await journal.save('2026-08', second.path);
      expect(await journal.fileFor('2026-08').readAsBytes(), [4, 5, 6]);
      expect(await journal.fileFor('2026-09').readAsBytes(), [4, 5, 6]);
      expect(
        await File('${journal.fileFor('2026-08').path}.old').exists(),
        false,
      );

      await journal.remove('2026-08');
      expect(await journal.months(), ['2026-09']);
      expect(() => journal.fileFor('../2026-08'), throwsFormatException);
      expect(
        PhotoJournal.isPng(await File('web/favicon.png').readAsBytes()),
        true,
      );
      expect(PhotoJournal.isPng([0xFF, 0xD8, 0xFF]), false);
    },
  );
}

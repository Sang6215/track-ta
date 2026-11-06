import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_ta/photo_journal.dart';
import 'package:track_ta/photos.dart';

void main() {
  testWidgets('Two monthly photos fit a narrow phone and show comparison', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('trackta-photo-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final journal = PhotoJournal(directory);
    final image = File('web/favicon.png').readAsBytesSync();
    journal.fileFor('2026-08').writeAsBytesSync(image);
    journal.fileFor('2026-09').writeAsBytesSync(image);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: PhotosPage(journal: journal)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ảnh theo tháng'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('So sánh trước và sau'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:io';

import 'package:all_docs/services/backup_storage.dart';
import 'package:all_docs/services/cloud/icloud_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late List<String> downloads;
  late ICloudBackupStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('icloud_test_');
    downloads = [];
    storage = ICloudBackupStorage(
      () async => root,
      // Stands in for iOS: "downloading" swaps the placeholder for the file.
      (path) async {
        downloads.add(path);
        final name = path.split('/').last;
        final parent = path.substring(0, path.length - name.length);
        await File('$parent.$name.icloud').delete();
        await File(path).writeAsString('{"ok":true}');
        return true;
      },
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('placeholder names map to the real file name', () {
    expect(iCloudPlaceholderName('.Invoice.pdf.icloud'), 'Invoice.pdf');
    expect(iCloudPlaceholderName('Invoice.pdf'), isNull);
    expect(iCloudPlaceholderName('.icloud'), isNull);
  });

  test('lists evicted files under their real names', () async {
    await Directory('${root.path}/Current').create();
    await File('${root.path}/Current/.Contract.pdf.icloud').writeAsString('');
    await File('${root.path}/Current/Here.pdf').writeAsString('x');

    final names = (await storage.list('Current')).map((e) => e.name).toSet();
    expect(names, {'Contract.pdf', 'Here.pdf'});
  });

  test('reading an evicted file downloads it first', () async {
    await File('${root.path}/.alldocs-current.json.icloud').writeAsString('');

    expect(await storage.readText('alldocs-current.json'), '{"ok":true}');
    expect(downloads, ['${root.path}/alldocs-current.json']);
  });

  test('a failed download throws instead of reading as missing', () async {
    final failing = ICloudBackupStorage(() async => root, (_) async => false);
    await File('${root.path}/.m.json.icloud').writeAsString('');

    expect(failing.readText('m.json'), throwsA(isA<FileSystemException>()));
  });

  test('delete removes the placeholder of an evicted file', () async {
    await File('${root.path}/.old.pdf.icloud').writeAsString('');
    await storage.delete('old.pdf');
    expect(await File('${root.path}/.old.pdf.icloud').exists(), isFalse);
    expect(await storage.list(''), isEmpty);
  });

  test('missing files still read as null', () async {
    expect(await storage.readText('nothing.json'), isNull);
    expect(storage, isA<BackupStorage>());
  });
}

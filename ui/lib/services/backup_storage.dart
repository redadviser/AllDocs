import 'dart:convert';
import 'dart:io';

/// A file or folder directly inside a [BackupStorage] folder.
class BackupEntry {
  const BackupEntry({
    required this.name,
    required this.isFolder,
    this.sizeBytes,
  });

  final String name;
  final bool isFolder;
  final int? sizeBytes;
}

/// Where a backup lives: a folder tree addressed by relative paths
/// ("Current/Gallery/Invoice.pdf"), on this phone or in a cloud account.
///
/// Callers make sure the target of [upload], [copy] and [move] is free
/// (deleting what's there first), so implementations never have to decide
/// whether to overwrite.
abstract class BackupStorage {
  /// Shown to the user after a backup ("Backup saved to ...").
  String get label;

  /// Children of [folder] ('' is the root). Empty when it doesn't exist.
  Future<List<BackupEntry>> list(String folder);

  /// Creates [folder] and its parents when missing.
  Future<void> ensureFolder(String folder);

  Future<void> upload(String path, File file);
  Future<void> download(String path, File destination);
  Future<void> copy(String from, String to);
  Future<void> move(String from, String to);

  /// Removes a file or a whole folder. Missing paths are not an error.
  Future<void> delete(String path);

  Future<void> writeText(String path, String text) async {
    final temp = await _tempFile();
    try {
      await temp.writeAsString(text, flush: true);
      await upload(path, temp);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Null when [path] doesn't exist.
  Future<String?> readText(String path) async {
    final temp = await _tempFile();
    try {
      await download(path, temp);
      return await temp.readAsString();
    } on BackupNotFoundException {
      return null;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<File> _tempFile() async {
    final dir = await Directory.systemTemp.createTemp('alldocs_backup_');
    return File('${dir.path}/data');
  }
}

class BackupNotFoundException implements Exception {
  const BackupNotFoundException(this.path);
  final String path;
  @override
  String toString() => 'Backup path not found: $path';
}

/// Splits "a/b/c.pdf" into ("a/b", "c.pdf").
({String parent, String name}) splitBackupPath(String path) {
  final index = path.lastIndexOf('/');
  return index < 0
      ? (parent: '', name: path)
      : (parent: path.substring(0, index), name: path.substring(index + 1));
}

/// A folder on this phone (or a memory card / USB drive the user picked).
class DeviceBackupStorage extends BackupStorage {
  DeviceBackupStorage(this.root);

  final Directory root;

  @override
  String get label => root.path;

  String _abs(String path) => path.isEmpty ? root.path : '${root.path}/$path';

  @override
  Future<List<BackupEntry>> list(String folder) async {
    final dir = Directory(_abs(folder));
    if (!await dir.exists()) return const [];
    final entries = <BackupEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      if (entity is Directory) {
        entries.add(BackupEntry(name: name, isFolder: true));
      } else if (entity is File) {
        entries.add(
          BackupEntry(
            name: name,
            isFolder: false,
            sizeBytes: await entity.length(),
          ),
        );
      }
    }
    return entries;
  }

  @override
  Future<void> ensureFolder(String folder) async {
    await Directory(_abs(folder)).create(recursive: true);
  }

  @override
  Future<void> upload(String path, File file) async {
    final target = File(_abs(path));
    await target.parent.create(recursive: true);
    await file.copy(target.path);
  }

  @override
  Future<void> download(String path, File destination) async {
    final source = File(_abs(path));
    if (!await source.exists()) throw BackupNotFoundException(path);
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
  }

  @override
  Future<void> copy(String from, String to) async {
    final target = File(_abs(to));
    await target.parent.create(recursive: true);
    await File(_abs(from)).copy(target.path);
  }

  @override
  Future<void> move(String from, String to) async {
    final target = File(_abs(to));
    await target.parent.create(recursive: true);
    try {
      await File(_abs(from)).rename(target.path);
    } on FileSystemException {
      // Different volumes can't rename into each other.
      await File(_abs(from)).copy(target.path);
      await File(_abs(from)).delete();
    }
  }

  @override
  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(_abs(path), followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await Directory(_abs(path)).delete(recursive: true);
    } else {
      await File(_abs(path)).delete();
    }
  }

  @override
  Future<String?> readText(String path) async {
    final file = File(_abs(path));
    if (!await file.exists()) return null;
    return utf8.decode(await file.readAsBytes());
  }

  @override
  Future<void> writeText(String path, String text) async {
    final target = File(_abs(path));
    await target.parent.create(recursive: true);
    // Through a temp file so an interrupted write never leaves half a JSON.
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(target.path);
  }
}

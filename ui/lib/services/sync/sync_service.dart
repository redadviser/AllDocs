import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as hashes;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/models.dart';
import '../current_user.dart';
import '../documents_service.dart';
import '../local_documents_store.dart';
import '../plan_service.dart';
import 'sync_api.dart';
import 'sync_crypto.dart';
import 'sync_entities.dart';

/// What the sync screen shows.
@immutable
class SyncStatus {
  const SyncStatus({
    this.enabled = false,
    this.running = false,
    this.waitingForLibrary = false,
    this.toReceive = 0,
    this.lastSyncAt,
    this.problem,
  });

  final bool enabled;
  final bool running;

  /// Joined, and waiting for another device to send the library.
  final bool waitingForLibrary;

  /// Documents whose file hasn't reached this phone yet.
  final int toReceive;
  final DateTime? lastSyncAt;

  /// Why the last try failed (null when it worked).
  final SyncProblem? problem;

  SyncStatus copyWith({
    bool? enabled,
    bool? running,
    bool? waitingForLibrary,
    int? toReceive,
    DateTime? lastSyncAt,
    SyncProblem? problem,
    bool clearProblem = false,
  }) => SyncStatus(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    waitingForLibrary: waitingForLibrary ?? this.waitingForLibrary,
    toReceive: toReceive ?? this.toReceive,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    problem: clearProblem ? null : problem ?? this.problem,
  );
}

/// A QR code's content couldn't be used to join.
enum SyncJoinError { notAnInvite, otherAccount }

class SyncJoinException implements Exception {
  const SyncJoinException(this.error);
  final SyncJoinError error;
}

/// This phone's side of device sync, kept next to the library
/// (`sync_state.json`): which device it is, how far it got, the account's
/// library as the server's sequence of changes builds it ([server]), the
/// library as this phone last wrote it ([base]), what this phone changed
/// that the server doesn't have yet ([outbox]), and which version of each
/// document's file is here ([files]).
class _LocalSync {
  _LocalSync({
    required this.deviceId,
    this.cursor = 0,
    SyncEntities? server,
    SyncEntities? base,
    List<SyncChange>? outbox,
    Map<String, String>? files,
    this.joining = false,
    this.lastSyncAt,
  }) : server = server ?? {},
       base = base ?? {},
       outbox = outbox ?? [],
       files = files ?? {};

  final String deviceId;
  int cursor;
  SyncEntities server;
  SyncEntities base;
  List<SyncChange> outbox;
  Map<String, String> files;

  /// Joined an existing sync and hasn't merged its own library in yet.
  bool joining;
  DateTime? lastSyncAt;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'device_id': deviceId,
    'cursor': cursor,
    'server': server,
    'base': base,
    'outbox': [for (final change in outbox) change.toJson()],
    'files': files,
    'joining': joining,
    'last_sync_at': lastSyncAt?.toIso8601String(),
  };

  static SyncEntities _entities(Object? raw) => {
    for (final entry in (raw as Map? ?? const {}).entries)
      entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
  };

  factory _LocalSync.fromJson(Map<String, dynamic> json) => _LocalSync(
    deviceId: json['device_id'] as String,
    cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    server: _entities(json['server']),
    base: _entities(json['base']),
    outbox: [
      for (final raw in (json['outbox'] as List? ?? const []))
        SyncChange.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
    files: (json['files'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    joining: json['joining'] == true,
    lastSyncAt: DateTime.tryParse(json['last_sync_at']?.toString() ?? ''),
  );
}

/// Device sync (Vault): the library the same on up to the plan's number of
/// phones, end-to-end encrypted, relayed by the AllDocs server.
///
/// Each phone compares its library with what it last wrote and sends the
/// difference, field by field, as an encrypted batch; the server numbers
/// the batches, so every phone applies them in the same order. Document
/// files go as encrypted blobs: sent as soon as a document is added when
/// other devices exist, and on request otherwise (a device that joins asks
/// for every file it lacks). A document shows up on a phone once its file
/// has arrived.
class SyncService {
  SyncService._();

  static final instance = SyncService._();

  final status = ValueNotifier<SyncStatus>(const SyncStatus());
  final _api = SyncApi();
  final _store = const LocalDocumentsStore();
  static const _secure = FlutterSecureStorage();
  static const stateFileName = 'sync_state.json';
  static const _invitePrefix = 'alldocs-sync:1:';

  // Batches are split to stay well under the server's limit (8 MB sealed).
  static const _batchJsonBytes = 2 * 1024 * 1024;

  DocumentsService? _documents;
  Future<void>? _running;
  bool _again = false;
  Timer? _timer;
  Timer? _debounce;
  _Lifecycle? _lifecycle;
  bool _hurry = false;

  String get _keyName => CurrentUser.scoped('sync.key.v1');

  // ---------------------------------------------------------------------
  // Turning it on and off
  // ---------------------------------------------------------------------

  /// Whether this phone takes part in sync (for the signed-in account).
  Future<bool> isEnabled() async {
    final local = await _load();
    _api.deviceId = local?.deviceId;
    return local != null;
  }

  Future<SyncAccountStatus> accountStatus() => _api.status();

  /// This phone starts the account's sync (the first device).
  Future<void> turnOn() async {
    final key = SyncCrypto.newKey();
    final crypto = SyncCrypto(key);
    final info = await _deviceInfo();
    _api.deviceId = null;
    final deviceId = await _api.register(
      name: info.name,
      platform: info.platform,
      keyCheck: crypto.keyCheck,
    );
    await _secure.write(key: _keyName, value: base64UrlEncode(key));
    await _save(_LocalSync(deviceId: deviceId));
    status.value = status.value.copyWith(enabled: true, clearProblem: true);
    unawaited(syncNow());
  }

  /// What the QR code shown to a new device holds: this account, a
  /// one-time code, and the key.
  Future<({String payload, DateTime expiresAt, String code})>
  createInvite() async {
    final local = await _load();
    final key = await _readKey();
    if (local == null || key == null) {
      throw const SyncApiException(SyncProblem.deviceRemoved);
    }
    _api.deviceId = local.deviceId;
    final pairing = await _api.createPairing();
    return (
      payload:
          '$_invitePrefix${CurrentUser.key}:${pairing.code}:${base64UrlEncode(key)}',
      expiresAt: pairing.expiresAt,
      code: pairing.code,
    );
  }

  Future<({bool joined, String? deviceName, bool expired})> invitationStatus(
    String code,
  ) => _api.pairingStatus(code);

  static bool looksLikeInvite(String value) => value.startsWith(_invitePrefix);

  /// Joins the account's sync with what another device's QR code holds.
  Future<void> join(String payload) async {
    if (!looksLikeInvite(payload)) {
      throw const SyncJoinException(SyncJoinError.notAnInvite);
    }
    final parts = payload.substring(_invitePrefix.length).split(':');
    if (parts.length != 3) {
      throw const SyncJoinException(SyncJoinError.notAnInvite);
    }
    if (parts[0] != CurrentUser.key) {
      throw const SyncJoinException(SyncJoinError.otherAccount);
    }
    final List<int> key;
    try {
      key = base64Url.decode(parts[2]);
    } on FormatException {
      throw const SyncJoinException(SyncJoinError.notAnInvite);
    }
    if (key.length != SyncCrypto.keyLength) {
      throw const SyncJoinException(SyncJoinError.notAnInvite);
    }
    final info = await _deviceInfo();
    _api.deviceId = null;
    final deviceId = await _api.register(
      name: info.name,
      platform: info.platform,
      keyCheck: SyncCrypto(key).keyCheck,
      pairingCode: parts[1],
    );
    await _secure.write(key: _keyName, value: base64UrlEncode(key));
    await _save(_LocalSync(deviceId: deviceId, joining: true));
    status.value = status.value.copyWith(
      enabled: true,
      waitingForLibrary: true,
      clearProblem: true,
    );
    unawaited(syncNow());
  }

  /// Takes [deviceId] out of the account's sync — this phone included.
  Future<void> removeDevice(String deviceId) async {
    final local = await _load();
    _api.deviceId = local?.deviceId;
    await _api.removeDevice(deviceId);
    if (deviceId == local?.deviceId) await _forget();
  }

  /// This phone stops syncing; its documents stay.
  Future<void> leave() async {
    final local = await _load();
    if (local != null) {
      try {
        _api.deviceId = local.deviceId;
        await _api.removeDevice(local.deviceId);
      } on SyncApiException {
        // Offline: the device stays listed until removed from another one.
      }
    }
    await _forget();
  }

  Future<void> _forget() async {
    await _secure.delete(key: _keyName);
    final file = await _stateFile();
    if (await file.exists()) await file.delete();
    _api.deviceId = null;
    status.value = const SyncStatus();
  }

  String? get thisDeviceId => _api.deviceId;

  // ---------------------------------------------------------------------
  // Running
  // ---------------------------------------------------------------------

  /// Syncs on app start, when the app comes back, a few seconds after the
  /// library changes, and every minute while open.
  void start(DocumentsService documents) {
    _documents = documents;
    LocalDocumentsStore.onLocalChange = _onLocalChange;
    _lifecycle ??= _Lifecycle(onResume: () => unawaited(syncNow()));
    WidgetsBinding.instance.addObserver(_lifecycle!);
    _schedule();
    unawaited(_refreshEnabled().then((_) => syncNow()));
  }

  void stop() {
    if (LocalDocumentsStore.onLocalChange == _onLocalChange) {
      LocalDocumentsStore.onLocalChange = null;
    }
    if (_lifecycle != null) WidgetsBinding.instance.removeObserver(_lifecycle!);
    _timer?.cancel();
    _debounce?.cancel();
    _documents = null;
  }

  void _onLocalChange() {
    if (!status.value.enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => unawaited(syncNow()));
  }

  void _schedule() {
    _timer?.cancel();
    // Faster while files are on their way or a device waits for the library.
    _timer = Timer.periodic(
      _hurry ? const Duration(seconds: 10) : const Duration(seconds: 60),
      (_) => unawaited(syncNow()),
    );
  }

  Future<void> _refreshEnabled() async {
    final local = await _load();
    status.value = status.value.copyWith(
      enabled: local != null,
      lastSyncAt: local?.lastSyncAt,
      waitingForLibrary: local?.joining ?? false,
    );
  }

  /// Runs a sync now (or right after the one running).
  Future<void> syncNow() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _runLoop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _runLoop() async {
    do {
      _again = false;
      await _runOnce();
    } while (_again);
  }

  Future<void> _runOnce() async {
    final local = await _load();
    final key = await _readKey();
    if (local == null || key == null) {
      status.value = const SyncStatus();
      return;
    }
    if (!PlanService.current.value.has(PlanFeature.deviceSync)) {
      status.value = status.value.copyWith(
        enabled: true,
        problem: SyncProblem.notIncluded,
      );
      return;
    }
    status.value = status.value.copyWith(enabled: true, running: true);
    final wasHurrying = _hurry;
    try {
      await _cycle(local, SyncCrypto(key));
      status.value = status.value.copyWith(
        running: false,
        lastSyncAt: local.lastSyncAt,
        clearProblem: true,
      );
    } on SyncApiException catch (error) {
      if (error.problem == SyncProblem.deviceRemoved) {
        await _forget();
        status.value = const SyncStatus(problem: SyncProblem.deviceRemoved);
        return;
      }
      status.value = status.value.copyWith(
        running: false,
        problem: error.problem,
      );
    } catch (error, stack) {
      debugPrint('Sync failed: $error\n$stack');
      status.value = status.value.copyWith(
        running: false,
        problem: SyncProblem.unavailable,
      );
    }
    if (_hurry != wasHurrying && _timer != null) _schedule();
  }

  // ---------------------------------------------------------------------
  // One sync
  // ---------------------------------------------------------------------

  Future<void> _cycle(_LocalSync local, SyncCrypto crypto) async {
    _api.deviceId = local.deviceId;
    final documentsDir = (await _store.documentsDirectory()).path;

    // 1. What changed here since the last write.
    final first = await _store.exportStateForSync();
    _capture(local, entitiesFromState(first.state));
    await _save(local);

    // 2. What changed elsewhere.
    var pull = await _pullAll(local, crypto, documentsDir);
    if (pull.needsSnapshot) {
      // Waiting for another device to send the library (this phone just
      // joined, or was away so long the changes it missed are gone).
      status.value = status.value.copyWith(waitingForLibrary: true);
      _hurry = true;
      await _save(local);
      return;
    }
    status.value = status.value.copyWith(waitingForLibrary: false);

    // 3. Files: the ones others asked for, and new ones everybody needs.
    await _sendFiles(local, crypto, pull);

    // 4. The library for devices that just joined.
    for (final deviceId in pull.snapshotFor) {
      final sealed = await crypto.sealJson({'v': 1, 'entities': local.server});
      try {
        await _api.putSnapshot(deviceId, local.cursor, sealed);
      } on SyncApiException catch (error) {
        if (error.problem != SyncProblem.unavailable) continue;
        rethrow;
      }
    }

    // 5. This phone's changes, in order after everyone else's.
    for (var attempt = 0; local.outbox.isNotEmpty; attempt++) {
      try {
        await _push(local, crypto);
      } on SyncApiException catch (error) {
        if (error.problem != SyncProblem.behind || attempt >= 5) rethrow;
        pull = await _pullAll(local, crypto, documentsDir);
      }
    }
    await _save(local);

    // 6. Files that aren't here yet.
    await _receiveFiles(local, crypto, documentsDir);

    // 7. Write the library.
    await _write(local, documentsDir);
    local.lastSyncAt = DateTime.now();
    await _save(local);

    _hurry =
        pull.requestedBlobs.isNotEmpty ||
        pull.snapshotFor.isNotEmpty ||
        status.value.toReceive > 0;
  }

  /// Records what the user changed since [local.base] as outgoing changes.
  void _capture(_LocalSync local, SyncEntities current) {
    final changes = diffEntities(local.base, current);
    if (changes.isEmpty) return;
    local.outbox.addAll(changes);
    local.base = current;
    // Whatever file a local document has is, by definition, here.
    for (final entry in current.entries) {
      if (isDocumentKey(entry.key)) {
        local.files[idOfKey(entry.key)] = fileKeyOf(entry.value);
      }
    }
  }

  Future<SyncPull> _pullAll(
    _LocalSync local,
    SyncCrypto crypto,
    String documentsDir,
  ) async {
    while (true) {
      final pull = await _api.pull(local.cursor);
      if (pull.needsSnapshot) {
        if (!pull.snapshotReady) return pull;
        await _loadSnapshot(local, crypto, documentsDir);
        continue;
      }
      for (final change in pull.changes) {
        final Object? batch;
        try {
          batch = await crypto.openJson(change.payload);
        } on SyncDecryptException {
          // Not ours to read (shouldn't happen): skip rather than stall.
          local.cursor = change.seq;
          continue;
        }
        applyChanges(local.server, _changesOf(batch));
        local.cursor = change.seq;
      }
      if (!pull.hasMore) return pull;
    }
  }

  Iterable<SyncChange> _changesOf(Object? batch) sync* {
    if (batch is! Map) return;
    for (final raw in (batch['changes'] as List? ?? const [])) {
      if (raw is Map) yield SyncChange.fromJson(Map<String, dynamic>.from(raw));
    }
  }

  Future<void> _loadSnapshot(
    _LocalSync local,
    SyncCrypto crypto,
    String documentsDir,
  ) async {
    final snapshot = await _api.getSnapshot();
    final data = await crypto.openJson(snapshot.sealed);
    final entities = data is Map && data['entities'] is Map
        ? _LocalSync._entities(data['entities'])
        : <String, Map<String, dynamic>>{};
    local.server = entities;
    local.cursor = snapshot.upto;
    if (local.joining) {
      // This phone's own library joins the one the others have: what it
      // adds is all that it sends.
      final merged = mergeJoiningLibrary(entities, local.base);
      local.outbox = diffEntities(entities, merged.merged);
      for (final entry in merged.sameDocument.entries) {
        await _adoptTwin(local, entry.key, entry.value, documentsDir);
      }
      local.joining = false;
    }
    await _save(local);
    await _api.ackSnapshot();
  }

  /// A document this phone had is the same file as [twinId] on the other
  /// devices: its file serves as the twin's, so it isn't downloaded again.
  Future<void> _adoptTwin(
    _LocalSync local,
    String localId,
    String twinId,
    String documentsDir,
  ) async {
    final mine = local.base[documentKey(localId)];
    final twin = local.server[documentKey(twinId)];
    final from = mine?['stored_name']?.toString();
    final to = twin?['stored_name']?.toString();
    if (mine == null || twin == null || from == null || to == null) return;
    final source = File('$documentsDir/$from');
    final target = File('$documentsDir/$to');
    if (!await source.exists()) return;
    if (from != to && !await target.exists()) await source.copy(target.path);
    local.files[twinId] = fileKeyOf(twin);
  }

  Future<void> _push(_LocalSync local, SyncCrypto crypto) async {
    // As many changes as fit in one batch.
    var size = 0;
    var count = 0;
    for (final change in local.outbox) {
      size += jsonEncode(change.toJson()).length;
      if (count > 0 && size > _batchJsonBytes) break;
      count++;
    }
    final batch = local.outbox.sublist(0, count);
    final sealed = await crypto.sealJson({
      'v': 1,
      'changes': [for (final change in batch) change.toJson()],
    });
    final seq = await _api.push(local.cursor, sealed);
    applyChanges(local.server, batch);
    local.cursor = seq;
    local.outbox = local.outbox.sublist(count);
    await _save(local);
  }

  /// The view of the library once this phone's changes are in.
  SyncEntities _view(_LocalSync local) {
    final view = copyEntities(local.server);
    applyChanges(view, local.outbox);
    return view;
  }

  Future<void> _sendFiles(
    _LocalSync local,
    SyncCrypto crypto,
    SyncPull pull,
  ) async {
    final documentsDir = (await _store.documentsDirectory()).path;
    // Files on this phone, by the id they have on the server.
    final here = <String, File>{};
    for (final entry in local.base.entries) {
      if (!isDocumentKey(entry.key)) continue;
      final stored = entry.value['stored_name']?.toString();
      if (stored == null) continue;
      here[crypto.blobIdFor(fileKeyOf(entry.value))] = File(
        '$documentsDir/$stored',
      );
    }

    final wanted = <String, bool>{
      for (final id in pull.requestedBlobs)
        if (here.containsKey(id)) id: false,
    };
    if (pull.otherDevices > 0) {
      // New or changed files in what this phone is about to send.
      for (final change in local.outbox) {
        if (!isDocumentKey(change.key) || change.deleted) continue;
        if (!change.full && !(change.set?.containsKey('checksum') ?? false)) {
          continue;
        }
        final document = local.base[change.key];
        if (document == null) continue;
        final id = crypto.blobIdFor(fileKeyOf(document));
        if (here.containsKey(id)) wanted.putIfAbsent(id, () => true);
      }
    }
    if (wanted.isEmpty) return;
    final everyone = [
      for (final entry in wanted.entries)
        if (entry.value) entry.key,
    ];
    final already = await _api.existingBlobs(everyone);
    for (final entry in wanted.entries) {
      if (entry.value && already.contains(entry.key)) continue;
      final file = here[entry.key]!;
      if (!await file.exists()) continue;
      try {
        await _api.putBlob(
          entry.key,
          crypto.sealFile(file),
          SyncCrypto.sealedLength(await file.length()),
          forEveryone: entry.value,
        );
      } on SyncApiException catch (error) {
        // Too much waiting on the server, or too big: the others ask again
        // later, and this phone sends it then.
        if (error.problem == SyncProblem.quota) return;
        if (error.problem == SyncProblem.unavailable) rethrow;
      }
    }
  }

  /// Downloads (or asks for) every file this phone is missing.
  Future<void> _receiveFiles(
    _LocalSync local,
    SyncCrypto crypto,
    String documentsDir,
  ) async {
    final view = _view(local);
    final missing = <String, List<Map<String, dynamic>>>{};
    for (final entry in view.entries) {
      if (!isDocumentKey(entry.key)) continue;
      final id = idOfKey(entry.key);
      if (local.files[id] == fileKeyOf(entry.value)) continue;
      missing
          .putIfAbsent(crypto.blobIdFor(fileKeyOf(entry.value)), () => [])
          .add(entry.value);
    }
    status.value = status.value.copyWith(toReceive: missing.length);
    if (missing.isEmpty) return;

    final ids = missing.keys.toList();
    final available = <String>{};
    for (var i = 0; i < ids.length; i += 500) {
      available.addAll(
        await _api.requestBlobs(ids.sublist(i, (i + 500).clamp(0, ids.length))),
      );
    }
    final temp = await Directory.systemTemp.createTemp('alldocs_sync_');
    try {
      var done = 0;
      for (final blobId in available) {
        final documents = missing[blobId]!;
        final sealed = File('${temp.path}/$blobId.sealed');
        final plain = File('${temp.path}/$blobId');
        try {
          await _api.getBlob(blobId, sealed);
          await crypto.openFile(sealed, plain);
        } on SyncApiException catch (error) {
          if (error.problem == SyncProblem.missing) continue;
          rethrow;
        } on SyncDecryptException {
          continue;
        }
        final checksum = documents.first['checksum']?.toString();
        if (checksum != null && checksum.isNotEmpty) {
          if (await _sha256Of(plain) != checksum) continue;
        }
        for (final document in documents) {
          final stored = document['stored_name']?.toString();
          if (stored == null || stored.isEmpty || stored.contains('/')) {
            continue;
          }
          await plain.copy('$documentsDir/$stored');
          local.files[document['id'].toString()] = fileKeyOf(document);
        }
        await _api.ackBlob(blobId);
        await sealed.delete();
        await plain.delete();
        done++;
        status.value = status.value.copyWith(toReceive: missing.length - done);
        if (done % 10 == 0) {
          await _save(local);
          // Show what arrived so far.
          await _write(local, documentsDir);
        }
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }

  /// Writes the library as sync sees it — after recording anything the
  /// user changed while sync ran, so nothing they did is lost.
  Future<void> _write(_LocalSync local, String documentsDir) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final now = await _store.exportStateForSync();
      final before = local.outbox.length;
      _capture(local, entitiesFromState(now.state));
      if (local.outbox.length != before) _again = true;

      final view = _view(local);
      final withheld = <String>{
        for (final entry in view.entries)
          if (isDocumentKey(entry.key) &&
              local.files[idOfKey(entry.key)] != fileKeyOf(entry.value))
            idOfKey(entry.key),
      };
      status.value = status.value.copyWith(toReceive: withheld.length);
      final next = stateFromEntities(
        view,
        current: now.state,
        documentsDirectory: documentsDir,
        withheld: withheld,
      );
      if (sameJson(next, now.state)) return;
      if (await _store.applySyncedState(next, now.revision)) {
        local.base = entitiesFromState(next);
        _documents?.refreshProfile();
        unawaited(_store.syncAllReminders());
        return;
      }
    }
  }

  // ---------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------

  Future<File> _stateFile() async =>
      File('${(await _store.appDirectory()).path}/$stateFileName');

  Future<_LocalSync?> _load() async {
    final file = await _stateFile();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final json = await Isolate.run(() => jsonDecode(raw));
      return _LocalSync.fromJson(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(_LocalSync local) async {
    final file = await _stateFile();
    final json = local.toJson();
    final encoded = await Isolate.run(() => jsonEncode(json));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoded, flush: true);
    await temp.rename(file.path);
  }

  Future<Uint8List?> _readKey() async {
    try {
      final raw = await _secure.read(key: _keyName);
      return raw == null ? null : base64Url.decode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sha256Of(File file) {
    final path = file.path;
    return Isolate.run(() async {
      final digest = await hashes.sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
  }

  static Future<({String name, String platform})> _deviceInfo() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return (name: ios.modelName, platform: 'ios');
      }
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final brand = android.manufacturer.isEmpty
            ? ''
            : '${android.manufacturer[0].toUpperCase()}${android.manufacturer.substring(1)} ';
        return (name: '$brand${android.model}'.trim(), platform: 'android');
      }
    } catch (_) {}
    return (name: 'AllDocs', platform: Platform.operatingSystem);
  }
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

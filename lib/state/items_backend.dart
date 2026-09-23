import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

/// Where an account's items are stored. One row per item; see `supabase/schema.sql`.
abstract class ItemsBackend {
  /// True when items live only on this phone (no account).
  bool get isLocal;

  Future<List<Item>> fetchAll();
  Future<void> upsert(Item it);
  Future<void> upsertAll(List<Item> items);
  Future<void> remove(String id);

  /// Stores a photo for the item and returns its storage path (saved in the item).
  Future<String> uploadPhoto(String itemId, Uint8List jpeg);

  /// Something an image widget can show: an absolute file path or a short-lived link.
  Future<String> photoUrl(String path);

  Future<void> removePhotos(List<String> paths);
}

class SupabaseItemsBackend implements ItemsBackend {
  SupabaseItemsBackend(this._db, this._userId);

  final SupabaseClient _db;
  final String _userId;

  @override
  bool get isLocal => false;

  Map<String, Object?> _row(Item it) => {
    'user_id': _userId,
    'id': it.id,
    'data': it.toJson(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  @override
  Future<List<Item>> fetchAll() async {
    final rows = await _db.from('items').select('data');
    return [
      for (final r in rows)
        Item.fromJson((r['data'] as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> upsert(Item it) =>
      _db.from('items').upsert(_row(it), onConflict: 'user_id,id');

  @override
  Future<void> upsertAll(List<Item> items) async {
    if (items.isEmpty) return;
    await _db.from('items').upsert([
      for (final it in items) _row(it),
    ], onConflict: 'user_id,id');
  }

  static const _bucket = 'item-photos';

  @override
  Future<String> uploadPhoto(String itemId, Uint8List jpeg) async {
    // The first folder must be the user's id: the storage rules check it.
    final path =
        '$_userId/$itemId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from(_bucket)
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  @override
  Future<String> photoUrl(String path) =>
      _db.storage.from(_bucket).createSignedUrl(path, 3600);

  @override
  Future<void> removePhotos(List<String> paths) async {
    if (paths.isNotEmpty) await _db.storage.from(_bucket).remove(paths);
  }

  @override
  Future<void> remove(String id) =>
      _db.from('items').delete().eq('user_id', _userId).eq('id', id);
}

/// Items and photos kept on this phone only, used while accounts are switched off.
/// Photos are stored as `local:<file name>` and resolved against the app's documents
/// folder, because iOS changes that folder's absolute path between app updates.
class LocalItemsBackend implements ItemsBackend {
  static const _key = 'owned/items/local/v1';
  static const _prefix = 'local:';

  @override
  bool get isLocal => true;

  Future<List<Item>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    return [
      for (final j in jsonDecode(raw) as List)
        Item.fromJson((j as Map).cast<String, Object?>()),
    ];
  }

  Future<void> _write(List<Item> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final i in items) i.toJson()]),
    );
  }

  @override
  Future<List<Item>> fetchAll() => _read();

  @override
  Future<void> upsert(Item it) => upsertAll([it]);

  @override
  Future<void> upsertAll(List<Item> items) async {
    final all = await _read();
    for (final it in items) {
      final ix = all.indexWhere((i) => i.id == it.id);
      if (ix >= 0) {
        all[ix] = it;
      } else {
        all.add(it);
      }
    }
    await _write(all);
  }

  @override
  Future<void> remove(String id) async =>
      _write((await _read()).where((i) => i.id != id).toList());

  Future<Directory> _photoDir() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/photos',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> uploadPhoto(String itemId, Uint8List jpeg) async {
    final name = '${itemId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File('${(await _photoDir()).path}/$name').writeAsBytes(jpeg);
    return '$_prefix$name';
  }

  @override
  Future<String> photoUrl(String path) async =>
      '${(await _photoDir()).path}/${path.substring(_prefix.length)}';

  @override
  Future<void> removePhotos(List<String> paths) async {
    final dir = await _photoDir();
    for (final p in paths) {
      final f = File('${dir.path}/${p.substring(_prefix.length)}');
      if (f.existsSync()) await f.delete();
    }
  }
}

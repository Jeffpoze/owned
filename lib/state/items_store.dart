import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/constants.dart';
import '../domain/example.dart';
import '../domain/models.dart';
import 'items_backend.dart';

/// - [StoreMode.account]: the signed-in user's items, saved to their account.
/// - [StoreMode.example]: the example home, held in memory and never saved.
enum StoreMode { loading, account, example }

class ItemsStore extends ChangeNotifier {
  /// Items saved on the device before accounts existed; moved into the account on first sign-in.
  static const _legacyKey = 'owned/items/v1';
  static String _cacheKey(String userId) => 'owned/items/cache/$userId';

  StoreMode mode = StoreMode.loading;
  List<Item> items = [];

  /// Set when the latest refresh from the account failed; the cached copy is shown meanwhile.
  bool offline = false;

  ItemsBackend? _backend;
  String? _userId;

  /// The user's own items, kept aside while they browse the example home.
  List<Item>? _ownItems;

  /// Search and filter are shared so Home can open Items with a query or filter applied.
  String query = '';
  ItemFilter filter = ItemFilter.all;

  String? get userId => _userId;

  /// Items are kept on this phone only (accounts switched off).
  bool get isLocal => _backend?.isLocal ?? false;
  List<Item> get active => items.where((i) => !i.sold).toList();

  Item? byId(String id) => items.where((i) => i.id == id).firstOrNull;

  /// Show the account's items: the cached copy immediately, then the latest from the server.
  Future<void> attach(String userId, ItemsBackend backend) async {
    _userId = userId;
    _backend = backend;
    _ownItems = null;
    mode = StoreMode.account;
    query = '';
    filter = ItemFilter.all;
    final prefs = await SharedPreferences.getInstance();
    items = _decode(prefs.getString(_cacheKey(userId)));
    notifyListeners();
    await _migrateLegacy(prefs);
    await refresh();
  }

  /// Signed out: forget the account's items (the cache stays for the next sign-in).
  void detach() {
    _userId = null;
    _backend = null;
    _ownItems = null;
    items = [];
    mode = StoreMode.loading;
    notifyListeners();
  }

  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final remote = await backend.fetchAll();
      if (_backend != backend) return; // signed out meanwhile
      offline = false;
      if (mode == StoreMode.account) items = remote;
      if (mode == StoreMode.example) _ownItems = remote;
      await _cache(remote);
    } catch (_) {
      offline = true;
    }
    notifyListeners();
  }

  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final legacy = _decode(prefs.getString(_legacyKey));
    if (legacy.isEmpty) return;
    try {
      await _backend!.upsertAll(legacy);
      await prefs.remove(_legacyKey);
    } catch (_) {
      // Try again on the next sign-in.
    }
  }

  List<Item> _decode(String? raw) {
    try {
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      return [
        for (final j in list) Item.fromJson((j as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _cache(List<Item> list) async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(_userId!),
      jsonEncode([for (final i in list) i.toJson()]),
    );
  }

  /// Saves to the account first, so the phone never shows something the account doesn't have.
  /// Returns false when the save failed.
  Future<bool> saveItem(Item it) async {
    if (mode == StoreMode.account) {
      try {
        await _backend!.upsert(it);
      } catch (_) {
        return false;
      }
    }
    final ix = items.indexWhere((i) => i.id == it.id);
    items = [...items];
    if (ix >= 0) {
      items[ix] = it;
    } else {
      items.add(it);
    }
    notifyListeners();
    if (mode == StoreMode.account) await _cache(items);
    return true;
  }

  Future<bool> deleteItem(String id) async {
    if (mode == StoreMode.account) {
      try {
        await _backend!.remove(id);
      } catch (_) {
        return false;
      }
      final it = byId(id);
      final photos = [
        it?.userPhoto,
        it?.officialImage,
        ...?it?.evidence.map((e) => e.assetId),
      ].whereType<String>().where(_isStored).toList();
      if (photos.isNotEmpty) unawaited(_removePhotos(photos));
    }
    items = items.where((i) => i.id != id).toList();
    notifyListeners();
    if (mode == StoreMode.account) await _cache(items);
    return true;
  }

  // ---- photos ----

  /// Stored photos are storage paths; the example home uses local file paths or web links.
  static bool _isStored(String ref) =>
      !ref.startsWith('/') && !ref.startsWith('http');

  final Map<String, (String, DateTime)> _urlCache = {};

  /// Saves a photo (the user's own, or a product picture) and returns the reference to keep in
  /// the item, or null when it couldn't be saved. The example home only keeps a temporary file.
  Future<String?> storePhoto(String itemId, Uint8List jpeg) async {
    try {
      if (mode != StoreMode.account) {
        final dir = await getTemporaryDirectory();
        final f = File(
          '${dir.path}/example_${itemId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await f.writeAsBytes(jpeg);
        return f.path;
      }
      return await _backend!.uploadPhoto(itemId, jpeg);
    } catch (_) {
      return null;
    }
  }

  /// Something [Image] can show for a photo reference: a file path, or a link valid for about an hour.
  Future<String?> photoUrl(String ref) async {
    if (!_isStored(ref)) return ref;
    final cached = _urlCache[ref];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    try {
      final url = await _backend!.photoUrl(ref);
      _urlCache[ref] = (url, DateTime.now().add(const Duration(minutes: 50)));
      return url;
    } catch (_) {
      return null;
    }
  }

  /// Best effort: an orphaned file costs a little storage but never shows up anywhere.
  Future<void> discardPhoto(String? ref) async {
    if (ref != null && _isStored(ref) && mode == StoreMode.account) {
      await _removePhotos([ref]);
    }
  }

  Future<void> _removePhotos(List<String> refs) async {
    try {
      await _backend?.removePhotos(refs);
    } catch (_) {}
  }

  void enterExample() {
    if (mode == StoreMode.example) return;
    _ownItems = items;
    items = exampleItems();
    mode = StoreMode.example;
    query = '';
    filter = ItemFilter.all;
    notifyListeners();
  }

  void leaveExample() {
    items = _ownItems ?? [];
    _ownItems = null;
    mode = StoreMode.account;
    query = '';
    filter = ItemFilter.all;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setFilter(ItemFilter f) {
    filter = f;
    query = '';
    notifyListeners();
  }
}

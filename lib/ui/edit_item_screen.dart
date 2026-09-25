import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:text_reader/text_reader.dart';

import '../domain/constants.dart';
import '../domain/dates.dart';
import '../domain/label_parser.dart';
import '../domain/models.dart';
import '../domain/receipt_parser.dart';
import '../domain/valuation.dart';
import '../domain/warranty.dart';
import '../services/catalog.dart';
import '../services/label_reader.dart';
import '../state/items_store.dart';
import '../theme.dart';
import 'barcode_scan_screen.dart';
import 'widgets.dart';

String _newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    Object().hashCode.toRadixString(36);

String _numText(num? n) =>
    n == null ? '' : (n % 1 == 0 ? n.toInt().toString() : n.toString());

double? _parseNum(String s) {
  final n = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  return n != null && n > 0 ? n : null;
}

class _MaintRow {
  _MaintRow(String task, String every, this.lastDone)
    : task = TextEditingController(text: task),
      every = TextEditingController(text: every);
  final TextEditingController task;
  final TextEditingController every;
  final IsoDate? lastDone;
}

class EditItemScreen extends StatefulWidget {
  const EditItemScreen({super.key, this.id});
  final String? id;

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  late final Item? _existing = widget.id == null
      ? null
      : context.read<ItemsStore>().byId(widget.id!);
  late Item _draft =
      _existing ??
      Item(
        id: _newId(),
        acquired: toIsoDate(today()),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

  late final _name = TextEditingController(text: _draft.name);
  late final _brand = TextEditingController(text: _draft.brand);
  late final _model = TextEditingController(text: _draft.model);
  late final _serial = TextEditingController(text: _draft.serial);
  late final _room = TextEditingController(text: _draft.room);
  late final _price = TextEditingController(text: _numText(_draft.price));
  late final _qty = TextEditingController(text: '${_draft.quantity}');
  late final _retailer = TextEditingController(text: _draft.retailer);
  late final _originalRetailer = TextEditingController(
    text: _draft.originalRetailer,
  );
  late final _value = TextEditingController(text: _numText(_draft.value));
  late final _warrantyMonths = TextEditingController(
    text: _numText(_draft.warrantyMonths),
  );
  late final _returnDays = TextEditingController(
    text: _numText(_draft.returnDays),
  );
  late final _notes = TextEditingController(text: _draft.notes);
  late final List<_MaintRow> _maint = [
    for (final m in _draft.maintenance)
      _MaintRow(m.task, '${m.everyMonths}', m.lastDone),
  ];
  bool _saving = false;

  /// A newly taken or chosen photo, not saved yet.
  XFile? _picked;

  /// The photo the item will have: the saved one, or null once the user removes it.
  late String? _photo = _draft.userPhoto;

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() {
          _picked = file;
          _cutOut = null;
          _beforeCutOut = null;
        });
      }
    } catch (_) {
      if (mounted) {
        toast(
          context,
          source == ImageSource.camera
              ? "Couldn't open the camera. Check Owned is allowed to use it in Settings."
              : "Couldn't open your photos. Check Owned is allowed to use them in Settings.",
        );
      }
    }
  }

  /// Background clean-up: null when not done, true while working, false when done
  /// (with the photo before it kept for Undo).
  bool? _cutOut;
  XFile? _beforeCutOut;
  bool _beforeCutOutWasSaved = false;

  Future<void> _cleanBackground() async {
    final store = context.read<ItemsStore>();
    // A photo taken now is a file already; a saved one is looked up on the phone.
    final source =
        _picked?.path ??
        (_photo == null ? null : await store.photoUrl(_photo!));
    if (source == null || !source.startsWith('/') || !mounted) return;
    setState(() => _cutOut = true);
    final lifted = await liftSubject(source);
    if (!mounted) return;
    if (lifted == null) {
      setState(() => _cutOut = null);
      toast(
        context,
        "Couldn't find the item in that photo. Try one with the item filling most of the frame. "
        '(Needs iOS 17 or later.)',
      );
      return;
    }
    setState(() {
      _beforeCutOut = _picked;
      _beforeCutOutWasSaved = _picked == null;
      _picked = XFile(lifted);
      _cutOut = false;
    });
  }

  void _undoCutOut() => setState(() {
    _picked = _beforeCutOutWasSaved ? null : _beforeCutOut;
    _beforeCutOut = null;
    _cutOut = null;
  });

  /// Removes the user's photo if there is one, otherwise the product picture.
  void _removePhoto() => setState(() {
    _cutOut = null;
    _beforeCutOut = null;
    if (_picked != null || _photo != null) {
      _picked = null;
      _photo = null;
    } else {
      _officialBytes = null;
      _official = null;
    }
  });

  // ---- product lookup ----

  /// A product picture downloaded from the catalog, not saved yet.
  Uint8List? _officialBytes;

  /// The saved product picture, or null once removed.
  late String? _official = _draft.officialImage;

  final _nameKey = GlobalKey();
  final _modelKey = GlobalKey();

  /// Scrolls the field to the top of the screen so its suggestions show above the keyboard.
  void _revealSuggestions(TextEditingController field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = (field == _name ? _nameKey : _modelKey).currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.02,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Which field the suggestion list belongs to (Name or Model), if any.
  TextEditingController? _suggestFor;
  List<ProductMatch> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  Timer? _debounce;
  int _searchSeq = 0;

  /// One line of progress or results for scanning and lookups.
  String? _status;
  bool _statusWarn = false;
  bool _scanning = false;

  void _setStatus(String? msg, {bool warn = false}) => setState(() {
    _status = msg;
    _statusWarn = warn;
  });

  void _hideSuggestions() => setState(() {
    _debounce?.cancel();
    _searchSeq++;
    _suggestFor = null;
    _suggestions = [];
    _searching = false;
    _searchError = null;
  });

  /// Called as the user types in Name or Model: search the catalog once typing pauses.
  void _onTyped(TextEditingController field, String text) {
    _debounce?.cancel();
    final q = text.trim();
    // Lookups are limited per day: wait for a few letters, and don't search while naming
    // an item whose model is already known (e.g. after a scan).
    if (q.length < 4 || (field == _name && _model.text.trim().isNotEmpty)) {
      if (_suggestFor == field) _hideSuggestions();
      return;
    }
    final opening = _suggestFor != field;
    setState(() {
      _suggestFor = field;
      _searching = true;
      _searchError = null;
    });
    if (opening) _revealSuggestions(field);
    // A model number alone is often ambiguous; the brand narrows it down.
    final brand = _brand.text.trim();
    final query = field == _model && brand.isNotEmpty ? '$brand $q' : q;
    _debounce = Timer(const Duration(milliseconds: 900), () => _search(query));
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    try {
      final results = await productCatalog.search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = results.take(6).toList();
        _searching = false;
      });
    } on CatalogException catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestions = [];
        _searching = false;
        _searchError = e.message;
      });
    }
  }

  Future<void> _chooseProduct(ProductMatch m) async {
    FocusScope.of(context).unfocus();
    _hideSuggestions();
    _applyProduct(m, overwriteName: true);
    await _fetchProductImage(m);
  }

  static String _brandName(String b) {
    for (final k in knownBrands) {
      if (k.toLowerCase() == b.toLowerCase()) return k;
    }
    // "SAMSUNG" -> "Samsung"; keep mixed case as the catalog wrote it.
    return b == b.toUpperCase() && b.length > 3
        ? b[0] + b.substring(1).toLowerCase()
        : b;
  }

  void _applyProduct(ProductMatch m, {required bool overwriteName}) {
    if (overwriteName || _name.text.trim().isEmpty) _name.text = m.displayName;
    if (m.brand.isNotEmpty) _brand.text = _brandName(m.brand);
    // Bundle listings have made-up model codes.
    if (m.model.isNotEmpty && !m.model.toUpperCase().startsWith('BNDL')) {
      _model.text = m.model.toUpperCase();
    }
    if (m.category != Category.other) {
      _set((d) => d.copyWith(category: m.category));
    }
  }

  Future<bool> _fetchProductImage(ProductMatch m) async {
    _setStatus('Getting the product picture…');
    final bytes = await productCatalog.downloadImage(m);
    if (!mounted) return false;
    setState(() {
      if (bytes != null) _officialBytes = bytes;
      _status = bytes == null
          ? 'No picture found for this product. You can add your own photo.'
          : null;
      _statusWarn = bytes == null;
    });
    return bytes != null;
  }

  // ---- scanning ----

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const BarcodeScanScreen(),
      ),
    );
    if (code == null || !mounted) return;
    await _applyLabel(parseLabel('', barcodes: [code]));
  }

  /// Asks camera or library, then returns the photo (or null if cancelled or unavailable).
  Future<XFile?> _photoOf(String what) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Take a photo of the $what'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose a photo of the $what'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return null;
    try {
      return await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
    } catch (_) {
      if (mounted) {
        _setStatus(
          "Couldn't open the camera or photos. Check Owned's access in Settings.",
          warn: true,
        );
      }
      return null;
    }
  }

  Future<void> _photographLabel() async {
    final file = await _photoOf('label');
    if (file == null || !mounted) return;
    setState(() => _scanning = true);
    _setStatus('Reading the label…');
    final fields = await readLabelPhoto(file.path);
    if (!mounted) return;
    await _applyLabel(fields);
  }

  // ---- receipt ----

  /// A receipt photo taken in this session, saved as proof when the item is saved.
  XFile? _receiptFile;

  Future<void> _photographReceipt() async {
    final file = await _photoOf('receipt');
    if (file == null || !mounted) return;
    _hideSuggestions();
    setState(() => _scanning = true);
    _setStatus('Reading the receipt…');
    final r = await readReceiptPhoto(file.path);
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _receiptFile = file;
    });
    await _applyReceipt(r);
  }

  Future<void> _applyReceipt(ReceiptFields r) async {
    final filled = <String>[];
    final isNew = !_used;

    // The receipt itself is strong proof, whatever could be read from it.
    if (!_draft.evidence.any((e) => e.kind == EvidenceKind.receipt)) {
      _set(
        (d) => d.copyWith(
          evidence: [...d.evidence, const Evidence(EvidenceKind.receipt)],
        ),
      );
    }
    if (r.retailer != null) {
      (isNew ? _retailer : _originalRetailer).text = r.retailer!;
      filled.add('store');
    }
    if (r.date != null) {
      final iso = toIsoDate(r.date!);
      _set(
        (d) => isNew
            ? d.copyWith(acquired: iso)
            : d.copyWith(originalPurchase: iso),
      );
      filled.add('date');
    }

    var line = pickLine(r.lines, name: _name.text, model: _model.text);
    if (line == null && r.lines.length > 1) {
      line = await _chooseReceiptLine(r.lines);
    }
    if (!mounted) return;
    if (line != null) {
      if (isNew) {
        // With several of the same thing, the receipt line is usually the total for all of them.
        final q = _quantity;
        _price.text = _numText(
          q > 1 ? (line.price / q * 100).round() / 100 : line.price,
        );
        filled.add(
          q > 1 ? 'price each (the receipt line split across $q)' : 'price',
        );
      }
      if (_name.text.trim().isEmpty) {
        _name.text = line.description;
        filled.add('name');
      }
    }
    if (isNew && r.returnDays != null) {
      _returnDays.text = '${r.returnDays}';
      filled.add('return window');
    }
    if (r.warrantyMonths != null) {
      _warrantyMonths.text = '${r.warrantyMonths}';
      _set((d) => d.copyWith(warrantySource: WarrantySource.receipt));
      filled.add('warranty');
    }

    if (filled.isEmpty) {
      _setStatus(
        "Couldn't read that receipt. It's still saved as proof; fill in the details yourself, "
        'or try a flatter, sharper photo.',
        warn: true,
      );
    } else {
      final list = filled.length == 1
          ? filled.first
          : '${filled.sublist(0, filled.length - 1).join(', ')} and ${filled.last}';
      _setStatus(
        'Filled in $list, and saved the receipt as proof. Check them before saving.',
      );
    }
  }

  /// Several items on the receipt and nothing to match them against: ask which one this is.
  Future<ReceiptLine?> _chooseReceiptLine(List<ReceiptLine> lines) =>
      showModalBottomSheet<ReceiptLine>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Which item on the receipt is this?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ),
                for (final l in lines)
                  ListTile(
                    title: Text(l.description),
                    trailing: Text(
                      money(l.price),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => Navigator.pop(ctx, l),
                  ),
                ListTile(
                  title: Text(
                    'None of these',
                    style: TextStyle(color: ctx.palette.ink2),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      );

  /// Fills the form from a label or barcode, then looks the product up for its name and picture.
  Future<void> _applyLabel(LabelFields f) async {
    _hideSuggestions();
    setState(() => _scanning = true);
    final filled = <String>[];
    if (f.brand != null) {
      _brand.text = f.brand!;
      filled.add('brand');
    }
    if (f.model != null) {
      _model.text = f.model!;
      filled.add('model');
    }
    if (f.serial != null) {
      _serial.text = f.serial!;
      filled.add('serial number');
    }

    ProductMatch? product;
    String? lookupProblem;
    if (f.upc != null || f.model != null) {
      _setStatus('Looking up the product…');
      try {
        if (f.upc != null) product = await productCatalog.lookupBarcode(f.upc!);
        if (product == null && f.model != null) {
          product = await productCatalog.findByModel(f.brand ?? '', f.model!);
        }
        if (product == null) {
          lookupProblem = "The catalog doesn't have this product.";
        }
      } on CatalogException catch (e) {
        lookupProblem = e.message;
      }
    }
    if (!mounted) return;

    if (product != null) {
      _applyProduct(product, overwriteName: _name.text.trim().isEmpty);
      // What's printed on the label is exact; keep it over the catalog's version.
      if (f.model != null) _model.text = f.model!;
      if (f.brand != null) _brand.text = f.brand!;
      filled.insert(0, 'name');
      if (!filled.contains('brand') && _brand.text.isNotEmpty) {
        filled.insert(1, 'brand');
      }
      if (!filled.contains('model') && _model.text.isNotEmpty) {
        filled.add('model');
      }
      if (await _fetchProductImage(product)) filled.add('product picture');
      if (!mounted) return;
    }

    setState(() => _scanning = false);
    if (filled.isEmpty) {
      _setStatus(
        lookupProblem ?? "Couldn't find a model or serial number in that. Try a closer, sharper photo, or type them in.",
        warn: true,
      );
    } else {
      final list = filled.length == 1
          ? filled.first
          : '${filled.sublist(0, filled.length - 1).join(', ')} and ${filled.last}';
      _setStatus(
        'Filled in $list. Check them before saving.${lookupProblem != null ? ' $lookupProblem' : ''}',
        warn: lookupProblem != null,
      );
    }
  }

  bool get _used => _draft.acquisition != Acquisition.newItem;

  /// How many the user bought, from the quantity box (at least 1).
  int get _quantity {
    final n = int.tryParse(_qty.text.trim());
    return n == null || n < 1 ? 1 : n;
  }

  /// Price each × quantity, while the form is being filled in.
  double? _liveTotal() {
    final each = _parseNum(_price.text);
    return each == null ? null : (each * _quantity * 100).round() / 100;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _model,
      _serial,
      _room,
      _price,
      _qty,
      _retailer,
      _originalRetailer,
      _value, //
      _warrantyMonths, _returnDays, _notes,
    ]) {
      c.dispose();
    }
    for (final m in _maint) {
      m.task.dispose();
      m.every.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _set(Item Function(Item d) f) => setState(() => _draft = f(_draft));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Give the item a name');
      if (_stepped) _goTo(0);
      return;
    }
    setState(() => _saving = true);
    final used = _used;
    final store = context.read<ItemsStore>();
    var photo = _photo;
    var official = _official;
    if (_picked != null) {
      photo = await store.storePhoto(_draft.id, await _picked!.readAsBytes());
    }
    if (_officialBytes != null) {
      official = await store.storePhoto(_draft.id, _officialBytes!);
    }
    // The receipt photo goes with the "Original receipt" proof, if that's still ticked.
    final oldReceipt = _draft.evidence
        .where((e) => e.kind == EvidenceKind.receipt)
        .firstOrNull
        ?.assetId;
    String? receipt = oldReceipt;
    final keepsReceipt = _draft.evidence.any(
      (e) => e.kind == EvidenceKind.receipt,
    );
    if (_receiptFile != null && keepsReceipt) {
      receipt = await store.storePhoto(
        _draft.id,
        await _receiptFile!.readAsBytes(),
      );
    }
    if (!mounted) return;
    if ((_picked != null && photo == null) ||
        (_officialBytes != null && official == null) ||
        (_receiptFile != null && keepsReceipt && receipt == null)) {
      setState(() => _saving = false);
      toast(
        context,
        "Couldn't save the photo. Check your connection and try again.",
      );
      return;
    }
    final it = _draft.copyWith(
      evidence: [
        for (final e in _draft.evidence)
          e.kind == EvidenceKind.receipt
              ? Evidence(EvidenceKind.receipt, assetId: receipt)
              : e,
      ],
      userPhoto: photo,
      officialImage: official,
      name: name,
      brand: _brand.text.trim(),
      model: _model.text.trim(),
      serial: _serial.text.trim(),
      room: _room.text.trim(),
      retailer: _retailer.text.trim(),
      price: _parseNum(_price.text),
      quantity: _quantity,
      value: _parseNum(_value.text),
      warrantyMonths: _parseNum(_warrantyMonths.text)?.round(),
      // Original purchase and transferability only apply to used and gifted items; return windows only to new ones.
      originalPurchase: used ? _draft.originalPurchase : null,
      originalRetailer: used ? _originalRetailer.text.trim() : '',
      transfer: used ? _draft.transfer : Transfer.unknown,
      returnDays: used ? null : _parseNum(_returnDays.text)?.round(),
      notes: _notes.text.trim(),
      maintenance: [
        for (final m in _maint)
          if (m.task.text.trim().isNotEmpty &&
              (int.tryParse(m.every.text) ?? 0) > 0)
            MaintenanceTask(
              task: m.task.text.trim(),
              everyMonths: int.parse(m.every.text),
              lastDone: m.lastDone,
            ),
      ],
    );
    final ok = await store.saveItem(it);
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      toast(context, saveFailedMessage);
      return;
    }
    // The item no longer points at its old photo, so the file can go.
    if (_existing?.userPhoto != null && _existing!.userPhoto != photo) {
      store.discardPhoto(_existing.userPhoto);
    }
    if (_existing?.officialImage != null &&
        _existing!.officialImage != official) {
      store.discardPhoto(_existing.officialImage);
    }
    final savedReceipt = it.evidence
        .where((e) => e.kind == EvidenceKind.receipt)
        .firstOrNull
        ?.assetId;
    if (oldReceipt != null && oldReceipt != savedReceipt) {
      store.discardPhoto(oldReceipt);
    }
    if (_existing == null) {
      // Show what was added, with the status the rules give it.
      setState(() {
        _saving = false;
        _added = it;
      });
      return;
    }
    toast(context, 'Saved');
    context.pop();
  }

  /// The automatic estimate for what's in the form right now, if there's enough to go on.
  double? _liveEstimate() => valueEstimate(
    _draft.copyWith(price: _parseNum(_price.text), quantity: _quantity),
  );

  String _valueHint() {
    final e = _liveEstimate();
    return e == null ? 'Estimated from price and age' : 'About ${money(e)}';
  }

  String? _valueHintNote() => _liveEstimate() == null
      ? null
      : "Leave empty to use this estimate from the price, age and kind of item. Type a value if you know what it's worth.";

  Widget _suggestionList() => _Suggestions(
    searching: _searching,
    error: _searchError,
    results: _suggestions,
    onChoose: _chooseProduct,
    onClose: _hideSuggestions,
  );

  // ---- layout ----

  /// Adding a new item goes step by step; editing shows the whole form.
  bool get _stepped => _existing == null;

  int _step = 0;

  /// "More details" on the last step: value, maintenance and notes.
  bool _moreOpen = false;

  /// Set once a new item is saved: the screen then shows what was added.
  Item? _added;

  static const _steps = [
    (
      'What is it?',
      'Scan it and Owned fills in what it can, or type the name.',
    ),
    (
      'How did you get it?',
      'Photograph the receipt to fill this in, or add the details yourself.',
    ),
    (
      'Proof and warranty',
      "No receipt is fine. It just means Owned is less sure about coverage.",
    ),
    ('Where is it?', 'Last step. Everything under More details is optional.'),
  ];

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    _hideSuggestions();
    setState(() {
      _step = step;
      if (!_scanning) _status = null;
    });
  }

  void _next() {
    if (_step == 0 && _name.text.trim().isEmpty) {
      toast(context, 'Scan the item or type its name to continue');
      return;
    }
    _goTo(_step + 1);
  }

  Widget _statusLine(BuildContext context) {
    final p = context.palette;
    if (_status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanning) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _status!,
              style: labelStyle(context).copyWith(
                color: _statusWarn ? p.status[WarrantyState.estimated] : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPicker() => _PhotoPicker(
    picked: _picked,
    saved: _photo,
    officialBytes: _officialBytes,
    official: _official,
    onTake: () => _pickPhoto(ImageSource.camera),
    onChoose: () => _pickPhoto(ImageSource.gallery),
    onRemove: _removePhoto,
    cutOut: _cutOut,
    onCutOut: _cleanBackground,
    onUndoCutOut: _undoCutOut,
  );

  Widget _scanButtons({
    bool barcode = true,
    bool label = true,
    bool receipt = true,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (ix, b) in [
        if (barcode)
          _ScanButton(
            icon: Icons.qr_code_scanner,
            title: 'Scan barcode',
            sub: 'Box or serial label',
            onTap: _scanning ? null : _scanBarcode,
          ),
        if (label)
          _ScanButton(
            icon: Icons.sell_outlined,
            title: 'Photograph label',
            sub: 'Model and serial',
            onTap: _scanning ? null : _photographLabel,
          ),
        if (receipt)
          _ScanButton(
            icon: Icons.receipt_long_outlined,
            title: 'Photograph receipt',
            sub: 'Store, date, price',
            onTap: _scanning ? null : _photographReceipt,
          ),
      ].indexed) ...[if (ix > 0) const SizedBox(width: 8), Expanded(child: b)],
    ],
  );

  /// Name, brand, model and serial number.
  List<Widget> _identityFields() => [
    _Field(
      key: _nameKey,
      'Name',
      _TextBox(
        _name,
        hint: 'Start typing, e.g. Samsung QN90',
        capitalize: true,
        onChanged: (t) => _onTyped(_name, t),
      ),
    ),
    if (_suggestFor == _name) _suggestionList(),
    _Row(key: _modelKey, [
      _Field('Brand', _TextBox(_brand, capitalize: true)),
      _Field(
        'Model',
        _TextBox(_model, caps: true, onChanged: (t) => _onTyped(_model, t)),
      ),
    ]),
    if (_suggestFor == _model) _suggestionList(),
    _Field('Serial number', _TextBox(_serial, caps: true)),
  ];

  /// Kind and room.
  List<Widget> _placeFields() {
    final rooms = {for (final i in context.read<ItemsStore>().items) i.room}
      ..remove('');
    final typed = _room.text.trim().toLowerCase();
    final roomHints = rooms
        .where((r) => r != _room.text && r.toLowerCase().startsWith(typed))
        .toList();
    return [
      _Field(
        'Kind',
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in Category.values)
              PillChip(
                categories[c]!.label,
                selected: _draft.category == c,
                onTap: () => _set((d) => d.copyWith(category: c)),
              ),
          ],
        ),
      ),
      _Field(
        'Room',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TextBox(
              _room,
              hint: 'Living room',
              capitalize: true,
              onChanged: (_) => setState(() {}),
            ),
            if (roomHints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in roomHints)
                    PillChip(r, onTap: () => setState(() => _room.text = r)),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// New, used or gift; date, price, quantity and where it came from.
  List<Widget> _purchaseFields() {
    final qty = _quantity;
    final total = _liveTotal();
    return [
      _Segmented<Acquisition>(
        value: _draft.acquisition,
        options: const [
          (Acquisition.newItem, 'New'),
          (Acquisition.used, 'Used'),
          (Acquisition.gift, 'Gift'),
        ],
        onChanged: (a) => _set((d) => d.copyWith(acquisition: a)),
      ),
      _Row([
        _Field(
          'Date you got it',
          _DateButton(
            value: _draft.acquired,
            onChanged: (v) => _set((d) => d.copyWith(acquired: v)),
          ),
        ),
        _Field(
          qty > 1 ? 'Price each' : 'Price paid',
          _TextBox(
            _price,
            hint: '0',
            number: true,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      _Field(
        'How many',
        Row(
          children: [
            _QuantityStepper(
              controller: _qty,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(width: 14),
            if (qty > 1 && total != null)
              Expanded(
                child: Text(
                  'Total ${money(total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              )
            else if (qty > 1)
              Expanded(
                child: Text(
                  'Add the price of one to get the total.',
                  style: labelStyle(context),
                ),
              ),
          ],
        ),
      ),
      _Field(
        switch (_draft.acquisition) {
          Acquisition.used => 'Where or who from',
          Acquisition.gift => 'From',
          Acquisition.newItem => 'Store',
        },
        _TextBox(_retailer, hint: _used ? null : 'Best Buy', capitalize: true),
      ),
      if (_used) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'A warranty starts at the original purchase, not the day you got it.',
            style: labelStyle(context),
          ),
        ),
        _Row([
          _Field(
            'Original purchase date',
            _DateButton(
              value: _draft.originalPurchase,
              optional: true,
              onChanged: (v) => _set((d) => d.copyWith(originalPurchase: v)),
            ),
          ),
          _Field(
            'Original store',
            _TextBox(_originalRetailer, capitalize: true),
          ),
        ]),
      ],
    ];
  }

  Widget _valueField() => _Field(
    _quantity > 1
        ? 'Value now, all $_quantity (optional)'
        : 'Value now (optional)',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextBox(
          _value,
          hint: _valueHint(),
          number: true,
          onChanged: (_) => setState(() {}),
        ),
        if (_value.text.trim().isEmpty && _valueHintNote() != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_valueHintNote()!, style: labelStyle(context)),
          ),
      ],
    ),
  );

  List<Widget> _warrantyFields() => [
    _Field(
      'Length in months',
      _TextBox(_warrantyMonths, hint: '12', number: true),
    ),
    _Radios<WarrantySource>(
      label: 'Where that comes from',
      value: _draft.warrantySource,
      options: const [
        (WarrantySource.receipt, 'Receipt or warranty card'),
        (WarrantySource.typical, "Manufacturer's usual length"),
        (WarrantySource.guess, 'Not sure'),
      ],
      onChanged: (v) => _set((d) => d.copyWith(warrantySource: v)),
    ),
    if (_used)
      _Radios<Transfer>(
        label: 'Does it transfer to you?',
        value: _draft.transfer,
        options: const [
          (Transfer.unknown, "Don't know"),
          (Transfer.transferable, 'Yes, transferable'),
          (Transfer.conditional, 'Only with proof of original purchase'),
          (Transfer.non, 'No, tied to the original buyer'),
        ],
        onChanged: (v) => _set((d) => d.copyWith(transfer: v)),
      )
    else
      _Field(
        'Return window in days (optional)',
        _TextBox(_returnDays, hint: '30', number: true),
      ),
    _Box([
      _Check(
        label: 'The manufacturer confirmed my coverage',
        value: _draft.mfrConfirmed,
        onChanged: (v) => _set((d) => d.copyWith(mfrConfirmed: v)),
      ),
    ]),
  ];

  List<Widget> _proofFields() => [
    _Box([
      for (final k in EvidenceKind.values)
        _Check(
          label: evidenceInfo[k]!.label,
          aside: evidenceInfo[k]!.strength.name,
          value: _draft.evidence.any((e) => e.kind == k),
          onChanged: (on) => _set(
            (d) => d.copyWith(
              evidence: on
                  ? [...d.evidence, Evidence(k)]
                  : d.evidence.where((e) => e.kind != k).toList(),
            ),
          ),
        ),
    ]),
  ];

  List<Widget> _maintenanceFields(BuildContext context) {
    final p = context.palette;
    return [
      for (final (ix, m) in _maint.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _TextBox(
                  m.task,
                  hint: 'Replace water filter',
                  capitalize: true,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: _TextBox(m.every, hint: 'Months', number: true),
              ),
              IconButton(
                tooltip: 'Remove task',
                icon: Icon(Icons.close, color: p.ink2),
                onPressed: () => setState(() => _maint.removeAt(ix)),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: p.status[WarrantyState.documented],
          ),
          onPressed: () => setState(() => _maint.add(_MaintRow('', '6', null))),
          child: const Text(
            '+ Add a recurring task',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ];
  }

  /// The whole form, for editing an item.
  List<Widget> _fullForm(BuildContext context) => [
    _photoPicker(),
    const SizedBox(height: 18),
    _scanButtons(),
    _statusLine(context),
    _Section('What it is', [..._identityFields(), ..._placeFields()]),
    _Section('How you got it', [..._purchaseFields(), _valueField()]),
    _Section('Warranty', _warrantyFields()),
    _Section('Proof you have', _proofFields()),
    _Section('Maintenance', _maintenanceFields(context)),
    _Section('Notes', [_TextBox(_notes, lines: 3, capitalize: true)]),
  ];

  /// One step of adding a new item.
  List<Widget> _stepContent(BuildContext context) => switch (_step) {
    0 => [
      _scanButtons(receipt: false),
      _statusLine(context),
      const SizedBox(height: 16),
      _photoPicker(),
      const SizedBox(height: 16),
      ..._identityFields(),
    ],
    1 => [
      _scanButtons(barcode: false, label: false),
      _statusLine(context),
      const SizedBox(height: 16),
      ..._purchaseFields(),
    ],
    2 => [
      _Section('Proof you have', [
        if (!_draft.evidence.any((e) => e.kind == EvidenceKind.receipt)) ...[
          _scanButtons(barcode: false, label: false),
          _statusLine(context),
          const SizedBox(height: 12),
        ],
        ..._proofFields(),
      ]),
      _Section('Warranty', _warrantyFields()),
    ],
    _ => [
      ..._placeFields(),
      _MoreToggle(
        open: _moreOpen,
        onTap: () => setState(() => _moreOpen = !_moreOpen),
      ),
      if (_moreOpen) ...[
        _valueField(),
        _Section('Maintenance', _maintenanceFields(context)),
        _Section('Notes', [_TextBox(_notes, lines: 3, capitalize: true)]),
      ],
    ],
  };

  Widget _stepHeader(BuildContext context) {
    final p = context.palette;
    final (title, sub) = _steps[_step];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${_step + 1} of ${_steps.length}',
            style: labelStyle(context),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_step + 1) / _steps.length,
              minHeight: 4,
              backgroundColor: p.rule,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(sub, style: mutedStyle(context)),
        ],
      ),
    );
  }

  /// Next on every step but the last; Add item or Save changes at the end.
  void _primaryAction() {
    if (_stepped && _step < _steps.length - 1) {
      _next();
    } else {
      _save();
    }
  }

  Widget _bottomBar(BuildContext context) {
    final p = context.palette;
    final last = !_stepped || _step == _steps.length - 1;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.rule, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 8),
      child: Row(
        children: [
          Expanded(
            child: AppButton(
              _stepped && _step > 0 ? 'Back' : 'Cancel',
              kind: ButtonKind.ghost,
              onPressed: _saving
                  ? null
                  : _stepped && _step > 0
                  ? () => _goTo(_step - 1)
                  : () => context.pop(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(
              _saving
                  ? 'Saving…'
                  : !last
                  ? 'Next'
                  : _existing == null
                  ? 'Add item'
                  : 'Save changes',
              onPressed: _saving || _scanning ? null : _primaryAction,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final added = _added;
    if (added != null) return _AddedScreen(added);

    return PopScope<Object?>(
      // The system back gesture steps back through the steps before leaving.
      canPop: !_stepped || _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _goTo(_step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? 'Add an item' : 'Edit item'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  // A fresh scroll position for each step.
                  key: ValueKey(_stepped ? _step : -1),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
                  children: _stepped
                      ? [_stepHeader(context), ..._stepContent(context)]
                      : _fullForm(context),
                ),
              ),
              _bottomBar(context),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.child, {super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label, style: labelStyle(context)),
        ),
        child,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (ix, c) in children.indexed) ...[
        if (ix > 0) const SizedBox(width: 10),
        Expanded(child: c),
      ],
    ],
  );
}

class _TextBox extends StatelessWidget {
  const _TextBox(
    this.controller, {
    this.hint,
    this.number = false,
    this.caps = false,
    this.capitalize = false,
    this.lines = 1,
    this.onChanged,
  });
  final TextEditingController controller;
  final String? hint;
  final bool number;
  final bool caps;
  final bool capitalize;
  final int lines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    minLines: lines,
    maxLines: lines == 1 ? 1 : null,
    autocorrect: !caps && !number,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    textCapitalization: caps
        ? TextCapitalization.characters
        : capitalize
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    style: const TextStyle(fontSize: 16),
    decoration: InputDecoration(hintText: hint),
  );
}

class _Box extends StatelessWidget {
  const _Box(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: children),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.onChanged,
    this.aside,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Checkbox.adaptive(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: p.ink,
              checkColor: p.paper,
              side: BorderSide(color: p.ink3, width: 1.5),
            ),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            if (aside != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  aside!,
                  style: TextStyle(fontSize: 12, color: p.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Radios<T> extends StatelessWidget {
  const _Radios({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Field(
      label,
      RadioGroup<T>(
        groupValue: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        child: _Box([
          for (final (v, l) in options)
            InkWell(
              onTap: () => onChanged(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Radio<T>.adaptive(value: v, activeColor: p.ink),
                    Expanded(
                      child: Text(l, style: const TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final (v, l) in options)
            Expanded(
              child: Semantics(
                selected: v == value,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? p.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: v == value ? p.paper : p.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A calendar date. Optional dates can be cleared, which the warranty logic treats as unknown.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.value,
    required this.onChanged,
    this.optional = false,
  });
  final IsoDate? value;
  final ValueChanged<IsoDate?> onChanged;
  final bool optional;

  Future<void> _pick(BuildContext context) async {
    final initial = parseDate(value) ?? today();
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      var picked = initial;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => Container(
          height: 300,
          color: ctx.palette.card,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: CupertinoButton(
                    child: const Text('Done'),
                    onPressed: () {
                      onChanged(toIsoDate(picked));
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initial,
                    maximumDate: today().add(const Duration(days: 1)),
                    onDateTimeChanged: (d) => picked = d,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1970),
        lastDate: today(),
      );
      if (d != null) onChanged(toIsoDate(d));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final date = parseDate(value);
    return Row(
      children: [
        Expanded(
          child: Material(
            color: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: p.rule),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _pick(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                child: Text(
                  date == null ? 'Add date' : formatDate(date),
                  style: TextStyle(
                    fontSize: 16,
                    color: date == null ? p.ink3 : p.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (optional && date != null)
          IconButton(
            tooltip: 'Clear date',
            icon: Icon(Icons.close, color: p.ink2),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.rule, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: p.ink),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  textAlign: TextAlign.center,
                  style: labelStyle(context).copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Catalog matches for what the user is typing. Text only: pictures are fetched
/// and saved once a product is chosen, never shown straight from the catalog.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.searching,
    required this.error,
    required this.results,
    required this.onChoose,
    required this.onClose,
  });
  final bool searching;
  final String? error;
  final List<ProductMatch> results;
  final ValueChanged<ProductMatch> onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget note(String text, {Widget? leading}) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          Expanded(child: Text(text, style: labelStyle(context))),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.focus.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    'From the product catalog',
                    style: labelStyle(context).copyWith(fontSize: 12),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Hide suggestions',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: p.ink3),
                  onPressed: onClose,
                ),
              ],
            ),
            Divider(height: 1, color: p.rule),
            if (searching)
              note(
                'Searching…',
                leading: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (error != null)
              note(error!)
            else if (results.isEmpty)
              note('No matches. Keep typing, or fill in the details yourself.')
            else
              for (final (ix, m) in results.indexed) ...[
                if (ix > 0) Divider(height: 1, color: p.rule, indent: 14),
                InkWell(
                  onTap: () => onChoose(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                              if (m.brand.isNotEmpty || m.model.isNotEmpty)
                                Text(
                                  [
                                    m.brand,
                                    m.model,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: labelStyle(context)
                                      .copyWith(fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.north_west, size: 16, color: p.ink3),
                      ],
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// The item's pictures: the product picture from the catalog, and the user's own photo
/// (take one, choose one, or remove it). The user's photo is shown large when there is one.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.picked,
    required this.saved,
    required this.officialBytes,
    required this.official,
    required this.onTake,
    required this.onChoose,
    required this.onRemove,
    required this.cutOut,
    required this.onCutOut,
    required this.onUndoCutOut,
  });

  /// Cut-out state: null when not started, true while working, false when done.
  final bool? cutOut;
  final VoidCallback onCutOut;
  final VoidCallback onUndoCutOut;
  final XFile? picked;
  final String? saved;
  final Uint8List? officialBytes;
  final String? official;
  final VoidCallback onTake;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final own = picked != null
        ? FittedPhoto(picked!.path, height: 240)
        : saved != null
        ? FittedPhoto(saved!, height: 240)
        : null;
    Widget? product(double h, {BoxFit fit = BoxFit.contain}) =>
        officialBytes != null
        ? Image.memory(officialBytes!, height: h, fit: fit)
        : official != null
        ? ItemImage(official!, height: h, fit: fit)
        : null;
    final hasOwn = own != null;
    final hasProduct = officialBytes != null || official != null;

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(
            fontFamily: 'Archivo',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );

    Widget caption(String text) => Positioned(
      left: 10,
      bottom: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    final Widget top;
    if (hasOwn) {
      top = Stack(
        children: [
          SizedBox(width: double.infinity, child: own),
          caption('Your photo'),
          Positioned(
            top: 10,
            right: 10,
            child: _PhotoPill(
              busy: cutOut == true,
              icon: cutOut == false ? Icons.undo : Icons.auto_awesome,
              label: cutOut == true
                  ? 'Cleaning up…'
                  : cutOut == false
                  ? 'Undo'
                  : 'Clean background',
              onTap: cutOut == true
                  ? null
                  : (cutOut == false ? onUndoCutOut : onCutOut),
            ),
          ),
          if (hasProduct)
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: product(64),
              ),
            ),
        ],
      );
    } else if (hasProduct) {
      top = Stack(
        children: [
          Container(
            width: double.infinity,
            height: 220,
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: product(196),
          ),
          caption('Product picture'),
        ],
      );
    } else {
      top = Container(
        height: 120,
        color: p.tag,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, color: p.ink2, size: 28),
            const SizedBox(height: 6),
            Text(
              'Add a photo, or pick a product below',
              style: mutedStyle(context),
            ),
          ],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          Divider(height: 1, color: p.rule),
          Row(
            children: [
              action(
                Icons.photo_camera_outlined,
                hasOwn ? 'Retake' : 'Take photo',
                onTake,
              ),
              action(Icons.photo_library_outlined, 'Choose', onChoose),
              if (hasOwn || hasProduct)
                action(Icons.delete_outline, 'Remove', onRemove),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoPill extends StatelessWidget {
  const _PhotoPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.6),
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// − [3] + : how many of the same thing. Never below 1.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

  int get _value {
    final n = int.tryParse(controller.text.trim());
    return n == null || n < 1 ? 1 : n;
  }

  void _set(int n) {
    controller.text = '${n < 1 ? 1 : n}';
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: p.ink,
      disabledColor: p.ink3,
    );
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.remove,
            'One fewer',
            _value > 1 ? () => _set(_value - 1) : null,
          ),
          SizedBox(
            width: 48,
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          button(Icons.add, 'One more', () => _set(_value + 1)),
        ],
      ),
    );
  }
}

class _MoreToggle extends StatelessWidget {
  const _MoreToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More details',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Value now, maintenance and notes',
                      style: labelStyle(context),
                    ),
                  ],
                ),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: p.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown right after adding an item: what Owned now knows about it. Every status is
/// the one the warranty and proof rules give; nothing is rounded up.
class _AddedScreen extends StatelessWidget {
  const _AddedScreen(this.it);
  final Item it;

  static const _proofText = {
    ProofStrength.strong: 'Strong',
    ProofStrength.moderate: 'Moderate',
    ProofStrength.weak: 'Weak',
  };

  @override
  Widget build(BuildContext context) {
    final w = warranty(it);
    final proof = proofLevel(it);
    final value = currentValue(it);
    final rw = returnWindow(it);
    final price = it.price ?? 0;

    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: mutedStyle(context))),
          Expanded(child: child),
        ],
      ),
    );
    Widget body(String text, {bool bold = false}) => Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Added'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
                children: [
                  Center(child: ItemThumb(it, size: 120, radius: 14)),
                  const SizedBox(height: 14),
                  Text(
                    it.quantity > 1 ? '${it.quantity} × ${it.name}' : it.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      height: 1.2,
                    ),
                  ),
                  if (it.brand.isNotEmpty || it.model.isNotEmpty)
                    Text(
                      [it.brand, it.model].where((s) => s.isNotEmpty).join(' '),
                      textAlign: TextAlign.center,
                      style: mutedStyle(context),
                    ),
                  const SizedBox(height: 18),
                  CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        row(
                          'Warranty',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StatusChip(w.state),
                              const SizedBox(height: 4),
                              body(w.why),
                              if (w.caveat != null) ...[
                                const SizedBox(height: 4),
                                Text(w.caveat!, style: labelStyle(context)),
                              ],
                              if (w.fix != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'To make it exact: ${w.fix!.toLowerCase()}.',
                                  style: labelStyle(context),
                                ),
                              ],
                            ],
                          ),
                        ),
                        row(
                          'Proof',
                          proof == null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    body('None yet', bold: true),
                                    Text(
                                      'Add a receipt later from Edit. It stays usable without one.',
                                      style: labelStyle(context),
                                    ),
                                  ],
                                )
                              : body(_proofText[proof]!, bold: true),
                        ),
                        if (price > 0)
                          row(
                            'Paid',
                            body(
                              it.quantity > 1
                                  ? '${money(it.totalPrice)} (${it.quantity} × ${money(price)})'
                                  : money(price),
                              bold: true,
                            ),
                          ),
                        if (value > 0)
                          row(
                            'Value now',
                            body(
                              (it.value ?? 0) > 0
                                  ? '${money(value)} (your figure)'
                                  : 'About ${money(value)}',
                            ),
                          ),
                        if (rw != null && rw.days >= 0)
                          row('Return by', body(formatDate(rw.end))),
                        if (it.room.isNotEmpty) row('Room', body(it.room)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      'Add another',
                      kind: ButtonKind.ghost,
                      onPressed: () => context.pushReplacement('/edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      'View item',
                      onPressed: () =>
                          context.pushReplacement('/item/${it.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

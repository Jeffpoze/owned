/// Dates are local calendar dates stored as "YYYY-MM-DD" strings.
typedef IsoDate = String;

enum Category {
  appliance,
  electronics,
  smarthome,
  furniture,
  kitchen,
  tools,
  gear,
  other,
}

enum Acquisition { newItem, used, gift }

enum WarrantySource { receipt, typical, guess }

enum Transfer { unknown, transferable, conditional, non }

enum EvidenceKind {
  receipt,
  invoice,
  registration,
  marketplace,
  card,
  email,
  seller,
  photo,
  user,
}

enum ProofStrength { weak, moderate, strong }

enum WarrantyState { verified, documented, estimated, unknown, expired }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// Acquisition.newItem is stored as "new" to match the data model.
String _acqToJson(Acquisition a) => a == Acquisition.newItem ? 'new' : a.name;
Acquisition _acqFromJson(Object? s) => s == 'new'
    ? Acquisition.newItem
    : _enumByName(Acquisition.values, s, Acquisition.newItem);

class Evidence {
  const Evidence(this.kind, {this.assetId});

  final EvidenceKind kind;
  final String? assetId;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (assetId != null) 'assetId': assetId,
  };

  factory Evidence.fromJson(Map<String, Object?> j) => Evidence(
    _enumByName(EvidenceKind.values, j['kind'], EvidenceKind.user),
    assetId: j['assetId'] as String?,
  );
}

class MaintenanceTask {
  const MaintenanceTask({
    required this.task,
    required this.everyMonths,
    this.lastDone,
  });

  final String task;
  final int everyMonths;
  final IsoDate? lastDone;

  MaintenanceTask withLastDone(IsoDate? d) =>
      MaintenanceTask(task: task, everyMonths: everyMonths, lastDone: d);

  Map<String, Object?> toJson() => {
    'task': task,
    'everyMonths': everyMonths,
    'lastDone': lastDone,
  };

  factory MaintenanceTask.fromJson(Map<String, Object?> j) => MaintenanceTask(
    task: j['task'] as String? ?? '',
    everyMonths: (j['everyMonths'] as num?)?.toInt() ?? 0,
    lastDone: j['lastDone'] as String?,
  );
}

const _unset = Object();

class Item {
  const Item({
    required this.id,
    this.name = '',
    this.brand = '',
    this.model = '',
    this.serial = '',
    this.category = Category.electronics,
    this.room = '',
    this.acquisition = Acquisition.newItem,
    this.acquired,
    this.price,
    this.retailer = '',
    this.originalPurchase,
    this.originalRetailer = '',
    this.value,
    this.warrantyMonths,
    this.warrantySource = WarrantySource.receipt,
    this.mfrConfirmed = false,
    this.transfer = Transfer.unknown,
    this.returnDays,
    this.evidence = const [],
    this.maintenance = const [],
    this.notes = '',
    this.officialImage,
    this.userPhoto,
    this.sold = false,
    this.soldOn,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String brand;
  final String model;
  final String serial;
  final Category category;
  final String room;
  final Acquisition acquisition;

  /// The date the user got the item.
  final IsoDate? acquired;
  final double? price;
  final String retailer;

  /// For used or gifted items: when the item was first bought new.
  final IsoDate? originalPurchase;
  final String originalRetailer;
  final double? value;
  final int? warrantyMonths;
  final WarrantySource warrantySource;
  final bool mfrConfirmed;
  final Transfer transfer;
  final int? returnDays;
  final List<Evidence> evidence;
  final List<MaintenanceTask> maintenance;
  final String notes;
  final String? officialImage;
  final String? userPhoto;
  final bool sold;
  final IsoDate? soldOn;
  final int createdAt;

  bool get isNew => acquisition == Acquisition.newItem;

  Item copyWith({
    String? name,
    String? brand,
    String? model,
    String? serial,
    Category? category,
    String? room,
    Acquisition? acquisition,
    Object? acquired = _unset,
    Object? price = _unset,
    String? retailer,
    Object? originalPurchase = _unset,
    String? originalRetailer,
    Object? value = _unset,
    Object? warrantyMonths = _unset,
    WarrantySource? warrantySource,
    bool? mfrConfirmed,
    Transfer? transfer,
    Object? returnDays = _unset,
    List<Evidence>? evidence,
    List<MaintenanceTask>? maintenance,
    String? notes,
    Object? officialImage = _unset,
    Object? userPhoto = _unset,
    bool? sold,
    Object? soldOn = _unset,
  }) {
    T? pick<T>(Object? v, T? current) =>
        identical(v, _unset) ? current : v as T?;
    return Item(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      serial: serial ?? this.serial,
      category: category ?? this.category,
      room: room ?? this.room,
      acquisition: acquisition ?? this.acquisition,
      acquired: pick<String>(acquired, this.acquired),
      price: pick<double>(price, this.price),
      retailer: retailer ?? this.retailer,
      originalPurchase: pick<String>(originalPurchase, this.originalPurchase),
      originalRetailer: originalRetailer ?? this.originalRetailer,
      value: pick<double>(value, this.value),
      warrantyMonths: pick<int>(warrantyMonths, this.warrantyMonths),
      warrantySource: warrantySource ?? this.warrantySource,
      mfrConfirmed: mfrConfirmed ?? this.mfrConfirmed,
      transfer: transfer ?? this.transfer,
      returnDays: pick<int>(returnDays, this.returnDays),
      evidence: evidence ?? this.evidence,
      maintenance: maintenance ?? this.maintenance,
      notes: notes ?? this.notes,
      officialImage: pick<String>(officialImage, this.officialImage),
      userPhoto: pick<String>(userPhoto, this.userPhoto),
      sold: sold ?? this.sold,
      soldOn: pick<String>(soldOn, this.soldOn),
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'model': model,
    'serial': serial,
    'category': category.name,
    'room': room,
    'acquisition': _acqToJson(acquisition),
    'acquired': acquired,
    'price': price,
    'retailer': retailer,
    'originalPurchase': originalPurchase,
    'originalRetailer': originalRetailer,
    'value': value,
    'warrantyMonths': warrantyMonths,
    'warrantySource': warrantySource.name,
    'mfrConfirmed': mfrConfirmed,
    'transfer': transfer.name,
    'returnDays': returnDays,
    'evidence': [for (final e in evidence) e.toJson()],
    'maintenance': [for (final m in maintenance) m.toJson()],
    'notes': notes,
    'officialImage': officialImage,
    'userPhoto': userPhoto,
    'sold': sold,
    'soldOn': soldOn,
    'createdAt': createdAt,
  };

  factory Item.fromJson(Map<String, Object?> j) => Item(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    brand: j['brand'] as String? ?? '',
    model: j['model'] as String? ?? '',
    serial: j['serial'] as String? ?? '',
    category: _enumByName(Category.values, j['category'], Category.other),
    room: j['room'] as String? ?? '',
    acquisition: _acqFromJson(j['acquisition']),
    acquired: j['acquired'] as String?,
    price: (j['price'] as num?)?.toDouble(),
    retailer: j['retailer'] as String? ?? '',
    originalPurchase: j['originalPurchase'] as String?,
    originalRetailer: j['originalRetailer'] as String? ?? '',
    value: (j['value'] as num?)?.toDouble(),
    warrantyMonths: (j['warrantyMonths'] as num?)?.toInt(),
    warrantySource: _enumByName(
      WarrantySource.values,
      j['warrantySource'],
      WarrantySource.guess,
    ),
    mfrConfirmed: j['mfrConfirmed'] as bool? ?? false,
    transfer: _enumByName(Transfer.values, j['transfer'], Transfer.unknown),
    returnDays: (j['returnDays'] as num?)?.toInt(),
    evidence: [
      for (final e in (j['evidence'] as List? ?? const []))
        Evidence.fromJson((e as Map).cast<String, Object?>()),
    ],
    maintenance: [
      for (final m in (j['maintenance'] as List? ?? const []))
        MaintenanceTask.fromJson((m as Map).cast<String, Object?>()),
    ],
    notes: j['notes'] as String? ?? '',
    officialImage: j['officialImage'] as String?,
    userPhoto: j['userPhoto'] as String?,
    sold: j['sold'] as bool? ?? false,
    soldOn: j['soldOn'] as String?,
    createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
  );
}

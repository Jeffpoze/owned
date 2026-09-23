import 'models.dart';

class CategoryInfo {
  const CategoryInfo(this.label, this.emoji, this.words);
  final String label;
  final String emoji;
  final List<String> words;
}

const categories = <Category, CategoryInfo>{
  Category.appliance: CategoryInfo('Appliance', '🧊', [
    'appliance',
    'appliances',
    'fridge',
    'refrigerator',
    'washer',
    'dryer',
    'dishwasher',
    'oven',
    'stove',
    'microwave',
  ]),
  Category.electronics: CategoryInfo('Electronics', '📺', [
    'electronics',
    'tv',
    'tvs',
    'television',
    'laptop',
    'phone',
    'computer',
    'monitor',
    'camera',
    'console',
    'speaker',
  ]),
  Category.smarthome: CategoryInfo('Smart home', '🔌', [
    'smart',
    'plug',
    'sensor',
    'hub',
    'matter',
    'thermostat',
    'lock',
  ]),
  Category.furniture: CategoryInfo('Furniture', '🪑', [
    'furniture',
    'chair',
    'table',
    'sofa',
    'couch',
    'desk',
    'bed',
    'shelf',
    'dresser',
  ]),
  Category.kitchen: CategoryInfo('Kitchenware', '🍳', [
    'kitchen',
    'kitchenware',
    'blender',
    'kettle',
    'cookware',
    'pan',
    'knife',
  ]),
  Category.tools: CategoryInfo('Tools', '🛠️', [
    'tool',
    'tools',
    'drill',
    'saw',
  ]),
  Category.gear: CategoryInfo('Gear & instruments', '🎸', [
    'guitar',
    'instrument',
    'instruments',
    'gear',
    'keyboard',
    'microphone',
    'bike',
  ]),
  Category.other: CategoryInfo('Other', '📦', []),
};

CategoryInfo categoryOf(Item it) => categories[it.category]!;

class EvidenceInfo {
  const EvidenceInfo(this.label, this.strength);
  final String label;
  final ProofStrength strength;
}

const evidenceInfo = <EvidenceKind, EvidenceInfo>{
  EvidenceKind.receipt: EvidenceInfo('Original receipt', ProofStrength.strong),
  EvidenceKind.invoice: EvidenceInfo('Retailer invoice', ProofStrength.strong),
  EvidenceKind.registration: EvidenceInfo(
    'Manufacturer registration',
    ProofStrength.strong,
  ),
  EvidenceKind.marketplace: EvidenceInfo(
    'Marketplace transaction',
    ProofStrength.moderate,
  ),
  EvidenceKind.card: EvidenceInfo(
    'Card or bank statement',
    ProofStrength.moderate,
  ),
  EvidenceKind.email: EvidenceInfo(
    'Order confirmation email',
    ProofStrength.moderate,
  ),
  EvidenceKind.seller: EvidenceInfo(
    'Receipt from the seller',
    ProofStrength.moderate,
  ),
  EvidenceKind.photo: EvidenceInfo('Photo of the product', ProofStrength.weak),
  EvidenceKind.user: EvidenceInfo(
    'My own record of the date',
    ProofStrength.weak,
  ),
};

const stateLabel = <WarrantyState, String>{
  WarrantyState.verified: 'Verified',
  WarrantyState.documented: 'Documented',
  WarrantyState.estimated: 'Estimated',
  WarrantyState.unknown: 'Unknown',
  WarrantyState.expired: 'Expired',
};

const stateMeaning = <WarrantyState, String>{
  WarrantyState.verified: 'Manufacturer confirmed it.',
  WarrantyState.documented: 'A receipt or invoice sets the dates.',
  WarrantyState.estimated: "Warranty length is known, exact coverage isn't.",
  WarrantyState.unknown: 'Not enough information yet.',
  WarrantyState.expired: 'Coverage has ended.',
};

enum ItemFilter {
  all,
  covered,
  expiring,
  returns,
  noreceipt,
  maint,
  used,
  sold,
}

const filterLabel = <ItemFilter, String>{
  ItemFilter.all: 'All',
  ItemFilter.covered: 'Under warranty',
  ItemFilter.expiring: 'Expiring soon',
  ItemFilter.returns: 'Return window',
  ItemFilter.noreceipt: 'Missing receipt',
  ItemFilter.maint: 'Maintenance due',
  ItemFilter.used: 'Bought used',
  ItemFilter.sold: 'Sold',
};

/// Attention thresholds, in days.
const expiringWithinDays = 60;
const returnEndingWithinDays = 7;
const maintenanceDueWithinDays = 14;

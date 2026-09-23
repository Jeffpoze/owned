/// Official websites for brands, used to link an item to its maker's product page.
/// Linking only: nothing is copied from these sites.
const brandSites = <String, String>{
  'samsung': 'samsung.com',
  'lg': 'lg.com',
  'sony': 'sony.com',
  'apple': 'apple.com',
  'dyson': 'dyson.com',
  'whirlpool': 'whirlpool.com',
  'ge': 'geappliances.com',
  'ge appliances': 'geappliances.com',
  'bosch': 'bosch-home.com',
  'kitchenaid': 'kitchenaid.com',
  'frigidaire': 'frigidaire.com',
  'maytag': 'maytag.com',
  'panasonic': 'panasonic.com',
  'philips': 'philips.com',
  'dell': 'dell.com',
  'hp': 'hp.com',
  'lenovo': 'lenovo.com',
  'asus': 'asus.com',
  'acer': 'acer.com',
  'microsoft': 'microsoft.com',
  'nintendo': 'nintendo.com',
  'canon': 'canon.com',
  'nikon': 'nikon.com',
  'bose': 'bose.com',
  'sonos': 'sonos.com',
  'irobot': 'irobot.com',
  'breville': 'breville.com',
  'vizio': 'vizio.com',
  'tcl': 'tcl.com',
  'hisense': 'hisense.com',
  'dewalt': 'dewalt.com',
  'makita': 'makitatools.com',
  'milwaukee': 'milwaukeetool.com',
  'ryobi': 'ryobitools.com',
  'yamaha': 'yamaha.com',
  'fender': 'fender.com',
  'google': 'store.google.com',
  'amazon': 'amazon.com',
  'electrolux': 'electrolux.com',
  'miele': 'miele.com',
  'haier': 'haier.com',
  'sharp': 'sharp.com',
  'toshiba': 'toshiba.com',
  'jbl': 'jbl.com',
  'garmin': 'garmin.com',
  'gopro': 'gopro.com',
  'logitech': 'logitech.com',
  'ninja': 'ninjakitchen.com',
  'shark': 'sharkclean.com',
  'cuisinart': 'cuisinart.com',
  'vitamix': 'vitamix.com',
  'keurig': 'keurig.com',
  'nespresso': 'nespresso.com',
  "de'longhi": 'delonghi.com',
  'delonghi': 'delonghi.com',
  'instant pot': 'instanthome.com',
  'weber': 'weber.com',
  'traeger': 'traeger.com',
  'eufy': 'eufy.com',
  'anker': 'anker.com',
  'ring': 'ring.com',
  'nest': 'store.google.com',
  'ikea': 'ikea.com',
  'eve': 'evehome.com',
};

/// Where to look the item up: the brand's own site when we know it (a web search limited
/// to that site, since model numbers differ by country), otherwise a general web search.
/// Returns null without a brand or model.
({Uri url, String label})? productPageLink(
  String brand,
  String model,
  String name,
) {
  final b = brand.trim();
  final site = brandSites[b.toLowerCase()];
  final what = [if (model.trim().isNotEmpty) model.trim() else name.trim()]
      .where((s) => s.isNotEmpty)
      .join(' ');
  // Without a brand or model there's nothing specific to look up.
  if (b.isEmpty && model.trim().isEmpty) return null;
  if (site != null && what.isNotEmpty) {
    return (
      url: Uri.https('www.google.com', '/search', {'q': 'site:$site $what'}),
      label: 'Look it up on $site',
    );
  }
  return (
    url: Uri.https('www.google.com', '/search', {
      'q': [b, what].where((s) => s.isNotEmpty).join(' '),
    }),
    label: 'Look it up online',
  );
}

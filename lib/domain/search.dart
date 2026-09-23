import 'constants.dart';
import 'dates.dart';
import 'models.dart';
import 'warranty.dart';

const _stopWords = {
  'show',
  'me',
  'everything',
  'all',
  'my',
  'the',
  'i',
  'what',
  'which',
  'do',
  'have',
  'own',
  'things', //
  'stuff',
  'items',
  'bought',
  'is',
  'are',
  'still',
  'that',
  'a',
  'an',
  'of',
  'list',
  'find',
  'get',
  'with',
  'any',
};

String _titleCase(String s) =>
    s.replaceAllMapped(RegExp(r'\b\w'), (m) => m[0]!.toUpperCase());

class QueryResult {
  const QueryResult(this.list, this.tags);
  final List<Item> list;

  /// The filters the query was understood as, to show the user.
  final List<String> tags;
}

/// Plain-language search with no AI: pattern rules over the data.
QueryResult runQuery(List<Item> items, String q, [DateTime? now]) {
  now ??= today();
  var list = items.where((i) => !i.sold).toList();
  final tags = <String>[];
  var s =
      ' ${q.toLowerCase().replaceAll(RegExp(r'[?.!]'), ' ').replaceAll(RegExp(r'\s+'), ' ')} ';

  RegExpMatch? take(RegExp re) {
    final m = re.firstMatch(s);
    if (m != null) s = s.replaceFirst(m[0]!, ' ');
    return m;
  }

  if (take(RegExp(r'\b(sold|got rid of)\b')) != null) {
    list = items.where((i) => i.sold).toList();
    tags.add('Sold');
  }
  if (take(RegExp(r'\b(expired|out of warranty|no longer covered)\b')) !=
      null) {
    list = list
        .where((i) => warranty(i, now).state == WarrantyState.expired)
        .toList();
    tags.add('Warranty expired');
  } else if (take(RegExp(r'\bexpir\w*( soon)?\b')) != null) {
    list = list.where((i) => isExpiring(i, now)).toList();
    tags.add('Expiring within 60 days');
  } else if (take(
        RegExp(
          r'\b(still )?(under|in) warranty\b|\bcovered\b|\bwarrant(y|ies) (active|valid)\b',
        ),
      ) !=
      null) {
    list = list.where((i) => isCovered(i, now)).toList();
    tags.add('Under warranty');
  }
  if (take(RegExp(r'\b(no|missing|without)( a| any)? (receipts?|proof)\b')) !=
      null) {
    list = list.where(isMissingReceipt).toList();
    tags.add('Missing receipt');
  }
  if (take(RegExp(r'\b(used|second ?hand|pre-?owned)\b')) != null) {
    list = list.where((i) => i.acquisition == Acquisition.used).toList();
    tags.add('Bought used');
  }
  if (take(RegExp(r'\bmaintenance|\bdue\b')) != null) {
    list = list.where((i) => isMaintenanceDue(i, now)).toList();
    tags.add('Maintenance due');
  }

  final from = take(
    RegExp(
      r"\b(?:from|at|bought at|bought from|by|made by)\s+([a-z0-9&' .-]+?)(?=\s+(?:in|that|which|with|under|over)\b|\s*$)",
    ),
  );
  if (from != null) {
    final who = from[1]!.trim();
    list = list
        .where(
          (i) =>
              [i.retailer, i.brand].any((v) => v.toLowerCase().contains(who)),
        )
        .toList();
    tags.add('From ${_titleCase(who)}');
  }

  final rooms = {for (final i in items) i.room.toLowerCase()}..remove('');
  final inRoom = RegExp(r'\bin (?:the |my )?([a-z ]+?)(?=\s|$)').firstMatch(s);
  if (inRoom != null) {
    final said = inRoom[1]!.trim();
    final r = rooms
        .where((r) => r.startsWith(said) || said.startsWith(r))
        .firstOrNull;
    if (r != null) {
      final rx = RegExp('\\bin (?:the |my )?${RegExp.escape(r)}\\b');
      s = rx.hasMatch(s)
          ? s.replaceFirst(rx, ' ')
          : s.replaceFirst(inRoom[0]!, ' ');
      list = list.where((i) => i.room.toLowerCase() == r).toList();
      tags.add('In ${_titleCase(r)}');
    }
  }

  final over = take(RegExp(r'\b(?:over|more than|above)\s+\$?(\d[\d,]*)'));
  if (over != null) {
    final n = double.parse(over[1]!.replaceAll(',', ''));
    list = list.where((i) => estimatedValue(i) > n).toList();
    tags.add('Over ${money(n)}');
  }

  for (final entry in categories.entries) {
    final w = entry.value.words
        .where((w) => RegExp('\\b$w\\b').hasMatch(s))
        .firstOrNull;
    if (w != null) {
      final exact = RegExp('\\b$w\\b');
      final catHit = list.where((i) => i.category == entry.key);
      final textHit = list.where(
        (i) => exact.hasMatch('${i.name} ${i.model}'.toLowerCase()),
      );
      list = {...catHit, ...textHit}.toList();
      s = s.replaceFirst(exact, ' ');
      tags.add(entry.value.label);
      break;
    }
  }

  final words = s
      .split(' ')
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .toList();
  if (words.isNotEmpty) {
    list = list.where((i) {
      final hay = [
        i.name,
        i.brand,
        i.model,
        i.serial,
        i.retailer,
        i.room,
        i.notes,
        categoryOf(i).label,
      ].join(' ').toLowerCase();
      return words.every(hay.contains);
    }).toList();
    tags.add('Matching "${words.join(' ')}"');
  }
  return QueryResult(list, tags);
}

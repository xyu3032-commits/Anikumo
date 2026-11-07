/// Keyword cleanup for Bangumi searches.
///
/// Users often paste full display titles such as
/// 「葬送的芙莉莲 第二季（2025）」. Bangumi's index matches core titles far
/// better than decorated ones, so when a search comes back empty the
/// caller can retry once with the stripped keyword produced here.
class KeywordNormalizer {
KeywordNormalizer._();

static final RegExp _seasonCn =
RegExp(r'\s*第\s*[0-9一二三四五六七八九十]+\s*[季期部篇章]\s*$');
static final RegExp _seasonEn =
RegExp(r'\s*(season|part|series)\s*[0-9]+\s*$', caseSensitive: false);
static final RegExp _seasonShort =
RegExp(r'\s+s[0-9]+\s*$', caseSensitive: false);
static final RegExp _trailingParens =
RegExp(r'\s*[（(\[【][^（(\[]*[）)\]】]\s*$');
static final RegExp _trailingDecor = RegExp(r'\s*[·・~～!！?？:：、,，.。]\s*$');
static final RegExp _multiSpace = RegExp(r'\s+');

/// Strips decorations from the end of [input]. Returns the cleaned
/// keyword, which may equal the input when nothing matched.
static String normalize(String input) {
var result = input.trim().replaceAll(_multiSpace, ' ');
// Repeat the passes: decorations stack, e.g. 「标题 第二季（2025）」
// needs the bracket pass before the season suffix becomes trailing.
for (var i = 0; i < 3; i++) {
final before = result;
result = result.replaceAll(_trailingParens, '');
result = result.replaceAll(_seasonCn, '');
result = result.replaceAll(_seasonEn, '');
result = result.replaceAll(_seasonShort, '');
result = result.replaceAll(_trailingDecor, '');
result = result.trim();
if (result == before) break;
}
return result;
}

/// The fallback keyword to retry with, or null when cleaning [input]
/// would not change it (or would erase it entirely).
static String? fallbackKeyword(String input) {
final cleaned = normalize(input);
if (cleaned.isEmpty || cleaned == input.trim()) return null;
return cleaned;
}
}

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Batch 279 (#8): reader auto-trim. Scanned manga pages
/// usually carry a near-uniform solid margin (white gutters
/// or black scan borders) that wastes screen area. When the
/// reader's 自动裁边 switch is on, each page's border is
/// measured and cut before display.
///
/// The measurement half ([computeTrimRect]) is pure: it
/// works over a pixel sampler, so it is unit-tested without
/// decoding real images. The byte half decodes with
/// package:image, crops, re-encodes as PNG, and memoizes
/// by content hash so flipping back and forth over the
/// same page never re-pays the decode.

/// A crop rectangle in pixel coordinates; [right] and
/// [bottom] are exclusive.
class TrimRect {
  const TrimRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  @override
  bool operator ==(Object other) =>
      other is TrimRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'TrimRect($left, $top, $right, $bottom)';
}

/// Returns the ARGB pixel at (x, y) as a 32-bit int
/// (alpha in the top byte).
typedef TrimPixelAt = int Function(int x, int y);

int _channelDiff(int a, int b, int shift) =>
    (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs();

/// Whether [pixel] counts as "the border color": fully
/// transparent pixels always count (PNG margins), otherwise
/// every channel must be within [tolerance] of [ref].
bool _matchesBorder(int pixel, int ref, int tolerance) {
  if (((pixel >> 24) & 0xFF) < 8) return true;
  return _channelDiff(pixel, ref, 16) <= tolerance &&
      _channelDiff(pixel, ref, 8) <= tolerance &&
      _channelDiff(pixel, ref, 0) <= tolerance;
}

/// Measures the content rectangle of a page whose border
/// is one near-uniform color.
///
/// The reference color is the top-left corner patch's
/// mean, trusted only when at least one other corner
/// shares it (within twice [tolerance]): a border may
/// exist on as few as one side, so corners on the
/// content side legitimately disagree — but if NO other
/// corner matches, the top-left is artwork, not border,
/// and there is no trustworthy reference. A row or
/// column counts as border when at least [uniformRatio]
/// of its sampled pixels match the reference. Rows and
/// columns are sampled at a stride, so this costs
/// O(perimeter × samples), never a full scan.
///
/// Returns null when nothing should be cut: no border,
/// a border so thick the "content" would be a sliver, or
/// a page that is border color all the way through.
TrimRect? computeTrimRect({
  required int width,
  required int height,
  required TrimPixelAt pixelAt,
  int tolerance = 32,
  double uniformRatio = 0.99,
}) {
  if (width < 8 || height < 8) return null;

  final patch = (width < height ? width : height) ~/ 64 + 1;
  int cornerMean(int cx, int cy) {
    var sumA = 0, sumR = 0, sumG = 0, sumB = 0, count = 0;
    for (var y = cy; y < cy + patch && y < height; y++) {
      for (var x = cx; x < cx + patch && x < width; x++) {
        final p = pixelAt(x, y);
        sumA += (p >> 24) & 0xFF;
        sumR += (p >> 16) & 0xFF;
        sumG += (p >> 8) & 0xFF;
        sumB += p & 0xFF;
        count++;
      }
    }
    if (count == 0) return 0;
    return ((sumA ~/ count) << 24) |
        ((sumR ~/ count) << 16) |
        ((sumG ~/ count) << 8) |
        (sumB ~/ count);
  }

  final corners = [
    cornerMean(0, 0),
    cornerMean(width - patch, 0),
    cornerMean(0, height - patch),
    cornerMean(width - patch, height - patch),
  ];
  final ref = corners.first;
  if (!corners
      .skip(1)
      .any((c) => _matchesBorder(c, ref, tolerance * 2))) {
    return null;
  }

  bool rowIsBorder(int y) {
    final stride = width ~/ 96 + 1;
    var samples = 0, hits = 0;
    for (var x = 0; x < width; x += stride) {
      samples++;
      if (_matchesBorder(pixelAt(x, y), ref, tolerance)) hits++;
    }
    return samples > 0 && hits / samples >= uniformRatio;
  }

  bool columnIsBorder(int x) {
    final stride = height ~/ 96 + 1;
    var samples = 0, hits = 0;
    for (var y = 0; y < height; y += stride) {
      samples++;
      if (_matchesBorder(pixelAt(x, y), ref, tolerance)) hits++;
    }
    return samples > 0 && hits / samples >= uniformRatio;
  }

  var top = 0;
  while (top < height && rowIsBorder(top)) {
    top++;
  }
  var bottom = height;
  while (bottom > top && rowIsBorder(bottom - 1)) {
    bottom--;
  }
  var left = 0;
  while (left < width && columnIsBorder(left)) {
    left++;
  }
  var right = width;
  while (right > left && columnIsBorder(right - 1)) {
    right--;
  }

  if (top == 0 && left == 0 && right == width && bottom == height) {
    return null; // No border at all.
  }
  final rect = TrimRect(left: left, top: top, right: right, bottom: bottom);
  // A sliver of "content" means the page was effectively
  // one solid color — trimming would leave nothing sane.
  if (rect.width < width ~/ 4 || rect.height < height ~/ 4) return null;
  return rect;
}

/// Decodes [bytes], measures the border and returns PNG
/// bytes of the cropped page. Null when the bytes do not
/// decode or there is nothing worth cutting (callers then
/// show the original bytes untouched).
Uint8List? trimImageBytes(Uint8List bytes, {int tolerance = 32}) {
  // decodeImage throws (not null) on some garbage input.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final image = decoded;
  final rect = computeTrimRect(
    width: image.width,
    height: image.height,
    tolerance: tolerance,
    pixelAt: (x, y) {
      final p = image.getPixel(x, y);
      return (p.a.toInt() << 24) |
          (p.r.toInt() << 16) |
          (p.g.toInt() << 8) |
          p.b.toInt();
    },
  );
  if (rect == null) return null;
  final cropped = img.copyCrop(
    image,
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
  );
  return img.encodePng(cropped);
}

/// Session-level memo of [trimImageBytes] results, keyed
/// by the SHA-256 of the source bytes. A null value is a
/// remembered "no trim for this page" so borderless pages
/// are not re-decoded on every flip either.
abstract final class MangaTrim {
  static final Map<String, Uint8List?> _memo = {};
  static const int _memoCap = 24;

  static Future<Uint8List?> trimmed(Uint8List bytes) async {
    final key = sha256.convert(bytes).toString();
    if (_memo.containsKey(key)) return _memo[key];
    final result = await compute(trimImageBytes, bytes);
    if (_memo.length >= _memoCap) {
      _memo.remove(_memo.keys.first);
    }
    _memo[key] = result;
    return result;
  }

  /// Test seam: drop the memo between cases.
  static void clearMemo() => _memo.clear();
}

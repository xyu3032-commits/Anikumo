import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Batch 279 (#10): export one downloaded chapter as a
/// single long image (all pages stitched vertically) or
/// as a PDF with one image per page. The CBZ export
/// (batch 234) stays as it is; these are the two formats
/// that did not exist yet.
///
/// Long-image strategy: every page is scaled to the
/// widest page's width and stacked. The canvas height is
/// capped at [defaultLongImageMaxHeight]; when a chapter
/// would exceed it, the whole strip is scaled down by
/// one uniform factor (width shrinks with it) instead of
/// being cut into pieces, so the export is always one
/// file in reading order. Undecodable pages are skipped;
/// the stitch returns null only when no page decodes.

/// Default cap for the stitched canvas height, in pixels.
const int defaultLongImageMaxHeight = 30000;

/// The geometry of a long-image export: canvas size plus
/// each page's scaled height in stacking order.
class LongImagePlan {
  const LongImagePlan({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.pageHeights,
  });

  final int canvasWidth;
  final int canvasHeight;
  final List<int> pageHeights;
}

/// Pure layout math behind [buildLongImageBytes].
/// [pageSizes] are (width, height) per page in reading
/// order; empty or degenerate entries are dropped.
LongImagePlan? planLongImage(
  List<({int width, int height})> pageSizes, {
  int maxHeight = defaultLongImageMaxHeight,
}) {
  final usable = [
    for (final s in pageSizes)
      if (s.width > 0 && s.height > 0) s,
  ];
  if (usable.isEmpty) return null;
  var width = 0;
  for (final s in usable) {
    if (s.width > width) width = s.width;
  }
  var heights = [
    for (final s in usable) (s.height * width / s.width).round(),
  ];
  var total = heights.fold<int>(0, (a, b) => a + b);
  if (total > maxHeight && total > 0) {
    final factor = maxHeight / total;
    width = (width * factor).round().clamp(1, 1 << 30);
    heights = [for (final h in heights) (h * factor).round()];
    total = heights.fold<int>(0, (a, b) => a + b);
  }
  if (width <= 0 || total <= 0) return null;
  return LongImagePlan(
    canvasWidth: width,
    canvasHeight: total,
    pageHeights: heights,
  );
}

/// Stitches [pages] (image bytes in reading order) into
/// one JPEG. Null when no page decodes.
Uint8List? buildLongImageBytes(
  List<Uint8List> pages, {
  int maxHeight = defaultLongImageMaxHeight,
}) {
  final decoded = <img.Image>[];
  for (final bytes in pages) {
    // decodeImage throws (not null) on some garbage input.
    try {
      final image = img.decodeImage(bytes);
      if (image != null) decoded.add(image);
    } catch (_) {
      // An undecodable page is skipped, never fatal.
    }
  }
  if (decoded.isEmpty) return null;
  final plan = planLongImage(
    [for (final d in decoded) (width: d.width, height: d.height)],
    maxHeight: maxHeight,
  );
  if (plan == null) return null;
  final canvas = img.Image(width: plan.canvasWidth, height: plan.canvasHeight);
  // Pages sit on black where a narrower page leaves a
  // gap after scaling — fill first so JPEG does not
  // invent edge colors.
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  var y = 0;
  for (var i = 0; i < decoded.length; i++) {
    final resized = decoded[i].width == plan.canvasWidth &&
            plan.pageHeights[i] == decoded[i].height
        ? decoded[i]
        : img.copyResize(
            decoded[i],
            width: plan.canvasWidth,
            height: plan.pageHeights[i],
          );
    img.compositeImage(canvas, resized, dstY: y);
    y += plan.pageHeights[i];
  }
  return img.encodeJpg(canvas, quality: 90);
}

/// Builds a PDF with one chapter page per document page,
/// each page sized exactly to its image. Pages the pdf
/// package cannot parse as images are skipped; an empty
/// (or all-bad) input still yields a valid blank PDF, so
/// callers check the page count before offering the file.
Future<Uint8List> buildChapterPdfBytes(List<Uint8List> pages) async {
  final doc = pw.Document();
  for (final bytes in pages) {
    final pw.MemoryImage image;
    try {
      image = pw.MemoryImage(bytes);
    } catch (_) {
      continue;
    }
    final width = (image.width ?? 0).toDouble();
    final height = (image.height ?? 0).toDouble();
    if (width <= 0 || height <= 0) continue;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height, marginAll: 0),
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}

/// A filesystem-safe export file name (the CBZ naming
/// rule, with another extension).
String chapterExportFileName(
  String mangaTitle,
  String chapterLabel,
  String extension,
) {
  final safe = ('$mangaTitle $chapterLabel')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${safe.isEmpty ? 'manga' : safe}.$extension';
}

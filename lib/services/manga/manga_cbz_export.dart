import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// Batch 234 （章节导出 pack): packs downloaded chapter
/// pages into a CBZ (a zip of images) — the counterpart
/// of the Batch 102 CBZ import, which this app already
/// ships.

/// The image extension for [bytes] from its magic
/// numbers; falls back to 'jpg'.
String mangaImageExtension(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'gif';
  }
  return 'jpg';
}

/// Builds CBZ bytes from page image bytes in reading
/// order. Pages are named 001, 002, … with their real
/// extensions so any reader opens them in order.
Uint8List buildCbzBytes(List<Uint8List> pages) {
  final archive = Archive();
  for (var i = 0; i < pages.length; i++) {
    final name =
        '${(i + 1).toString().padLeft(3, '0')}.${mangaImageExtension(pages[i])}';
    archive.addFile(ArchiveFile(name, pages[i].length, pages[i]));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

/// A filesystem-safe CBZ file name for an export.
String cbzFileName(String mangaTitle, String chapterLabel) {
  final safe = ('$mangaTitle $chapterLabel')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${safe.isEmpty ? 'manga' : safe}.cbz';
}

import 'dart:convert';

import 'package:image/image.dart' as img;

/// Batch 198: decoded-image registry backing MangaKit's
/// synchronous Image API (used by modifyImage snippets to
/// descramble pages), extracted from the legacy engine so
/// both runtimes speak the identical op protocol
/// ({method:'image', function, ...} -> {ok, v, fmt}). JS
/// only ever holds integer keys, exactly like the reference
/// runtime. Entries are released wholesale after each
/// modifyImage run, and the map self-caps as a backstop.
final Map<int, img.Image> _registry = <int, img.Image>{};
int _seq = 0;

String _reply({required bool ok, Object? v, String? fmt}) {
  return jsonEncode(<String, Object?>{'ok': ok, 'v': v, 'fmt': ?fmt});
}

String _sniffImageFormat(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'jpeg';
  }
  if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'png';
  }
  if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49) {
    return 'gif';
  }
  if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45) {
    return 'webp';
  }
  return 'other';
}

/// Handles one image-op message SYNCHRONOUSLY (all ops are
/// CPU work in the `image` package) and returns the JSON
/// envelope string the JS side unwraps.
String mangakitImageOpSync(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return _reply(ok: false);
    final msg = decoded.cast<String, dynamic>();
    final fn = msg['function']?.toString() ?? '';
    int intOf(String name) => (msg[name] as num?)?.toInt() ?? 0;
    img.Image? imageOf(String name) =>
        _registry[(msg[name] as num?)?.toInt()];
    int register(img.Image image) {
      if (_registry.length >= 32) {
        _registry.clear();
      }
      final key = ++_seq;
      _registry[key] = image;
      return key;
    }

    switch (fn) {
      case 'createFromBytes':
        final bytes = base64Decode(msg['dataB64']?.toString() ?? '');
        final image = img.decodeImage(bytes);
        if (image == null) return _reply(ok: false);
        return _reply(
          ok: true,
          v: register(image),
          fmt: _sniffImageFormat(bytes),
        );
      case 'encode':
        final image = imageOf('key');
        if (image == null) return _reply(ok: false);
        final bytes = msg['fmt']?.toString() == 'jpeg'
            ? img.encodeJpg(image, quality: 96)
            : img.encodePng(image);
        return _reply(ok: true, v: base64Encode(bytes));
      case 'copyRange':
        final image = imageOf('key');
        if (image == null) return _reply(ok: true);
        final copy = img.copyCrop(
          image,
          x: intOf('x'),
          y: intOf('y'),
          width: intOf('width'),
          height: intOf('height'),
        );
        return _reply(ok: true, v: register(copy));
      case 'copyAndRotate90':
        final image = imageOf('key');
        if (image == null) return _reply(ok: true);
        return _reply(
          ok: true,
          v: register(img.copyRotate(image, angle: 90)),
        );
      case 'fillImageAt':
        final dst = imageOf('key');
        final src = imageOf('image');
        if (dst == null || src == null) return _reply(ok: true);
        img.compositeImage(dst, src, dstX: intOf('x'), dstY: intOf('y'));
        return _reply(ok: true);
      case 'fillImageRangeAt':
        final dst = imageOf('key');
        final src = imageOf('image');
        if (dst == null || src == null) return _reply(ok: true);
        img.compositeImage(
          dst,
          src,
          dstX: intOf('x'),
          dstY: intOf('y'),
          srcX: intOf('srcX'),
          srcY: intOf('srcY'),
          srcW: intOf('width'),
          srcH: intOf('height'),
        );
        return _reply(ok: true);
      case 'getWidth':
        return _reply(ok: true, v: imageOf('key')?.width);
      case 'getHeight':
        return _reply(ok: true, v: imageOf('key')?.height);
      case 'emptyImage':
        return _reply(
          ok: true,
          v: register(
            img.Image(width: intOf('width'), height: intOf('height')),
          ),
        );
      case 'releaseAll':
        _registry.clear();
        return _reply(ok: true);
      default:
        return _reply(ok: false);
    }
  } catch (_) {
    return _reply(ok: false);
  }
}

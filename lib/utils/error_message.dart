/// Batch 41: turns raw exception dumps into the short,
/// human messages the home sections show. Device reports
/// had full `DioException [connection error]: The connection
/// errored: Failed host lookup: 'www.deqixs.com'...` strings
/// rendered in red across the novel home — accurate for a
/// log file, useless on screen. Known network failure shapes
/// map to one-line Chinese; everything else keeps its own
/// message minus the noisy Dart type prefixes.
String friendlyError(Object error) {
  final raw = error.toString();
  if (raw.contains('Failed host lookup')) {
    return '站点无法访问（域名解析失败，站点可能已停运或改域名）';
  }
  if (raw.contains('HandshakeException') ||
      raw.contains('CERTIFICATE') ||
      raw.contains('certificate')) {
    return '站点连接失败（安全握手错误）';
  }
  if (raw.contains('Connection refused')) return '站点拒绝连接';
  if (raw.contains('Connection reset') ||
      raw.contains('Connection closed') ||
      raw.contains('Broken pipe')) {
    return '连接被站点中断，请重试';
  }
  if (raw.contains('TimeoutException') ||
      raw.contains('timed out') ||
      raw.contains('receiveTimeout') || raw.contains('receive timeout') || raw.contains('connection timeout') || raw.contains('send timeout') ||
      raw.contains('connectionTimeout') ||
      raw.contains('sendTimeout')) {
    return '加载超时，请重试';
  }
  if (raw.contains('SocketException') || raw.contains('DioException')) {
    return '网络连接失败，请检查网络后重试';
  }
  var s = raw;
  // Strip chained prefixes the layers add: "Bad state: " from
  // StateError.toString(), and the JS dispatcher's nested
  // "JS 源调用失败：Error: " / "Error: " repeats.
  if (s.startsWith('Bad state: ')) s = s.substring('Bad state: '.length);
  s = s.replaceFirst('JS 源调用失败：Error: ', 'JS 源调用失败：');
  s = s.replaceFirst('JS 源调用失败：Error：', 'JS 源调用失败：');
  return s;
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture mangadex feed request uri', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://api.mangadex.org',
      headers: const {'user-agent': 'anikumo-manga/1.0 (Anikumo fork)'},
    ));
    try {
      final r = await dio.get<dynamic>(
        '/manga/aa6c76f7-5f5f-46b6-a800-911145f81b9b/feed',
        queryParameters: {
          'translatedLanguage[]': ['zh', 'zh-hk', 'en'],
          'order[volume]': 'asc',
          'order[chapter]': 'asc',
          'limit': 500,
          'offset': 0,
        },
      );
      print('== status ${r.statusCode} uri=${r.requestOptions.uri}');
    } on DioException catch (e) {
      print('== ERR ${e.response?.statusCode} uri=${e.requestOptions.uri}');
      print('== body: ${e.response?.data}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

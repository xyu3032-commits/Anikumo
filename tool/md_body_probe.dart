import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mangadex feed error body', () async {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://api.mangadex.org',
      headers: const {'user-agent': 'anikumo-manga/1.0 (Anikumo fork)'},
    ));
    for (var i = 0; i < 4; i++) {
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
        print('== try $i: ${r.statusCode} total=${(r.data as Map)['total']}');
      } on DioException catch (e) {
        print('== try $i: ERR ${e.response?.statusCode} body=${e.response?.data}');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/library/user_library.dart';

void main() {
  group('UserListsCodec', () {
    test('round-trips lists with ids in add order', () {
      final lists = [
        UserList(id: 'a1', name: '本季度神作', bangumiIds: [3, 1, 2]),
        UserList(id: 'b2', name: '补番计划'),
      ];
      final decoded = UserListsCodec.decode(UserListsCodec.encode(lists));
      expect(decoded.length, 2);
      expect(decoded.first.name, '本季度神作');
      expect(decoded.first.bangumiIds, [3, 1, 2]);
      expect(decoded.last.bangumiIds, isEmpty);
    });

    test('tolerates empty and malformed input', () {
      expect(UserListsCodec.decode(''), isEmpty);
      expect(UserListsCodec.decode('not json'), isEmpty);
      expect(UserListsCodec.decode('{"a":1}'), isEmpty);
    });

    test('drops entries without an id', () {
      final decoded = UserListsCodec.decode(
        '[{"name":"无名","bangumiIds":[]},{"id":"x","name":"有名","bangumiIds":[7]}]',
      );
      expect(decoded.length, 1);
      expect(decoded.single.bangumiIds, [7]);
    });
  });

  group('BangumiNotesCodec', () {
    test('round-trips notes keyed by bangumi id', () {
      final notes = {101: '第 8 集封神', 202: '等第二季一起看'};
      final decoded = BangumiNotesCodec.decode(BangumiNotesCodec.encode(notes));
      expect(decoded, notes);
    });

    test('skips empty texts and unparsable keys', () {
      final decoded = BangumiNotesCodec.decode(
        '{"1":"有内容","x":"键不对","2":""}',
      );
      expect(decoded, {1: '有内容'});
    });

    test('tolerates malformed input', () {
      expect(BangumiNotesCodec.decode(''), isEmpty);
      expect(BangumiNotesCodec.decode('[1,2]'), isEmpty);
    });
  });
}

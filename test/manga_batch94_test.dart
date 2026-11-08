import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/pages/manga/manga_search_page.dart';
import 'package:anikumo/services/storage/storage.dart';

class _TestPaths extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

/// Batch 94: leaving the manga search page for a result
/// and coming back must NOT hand focus back to the search
/// field (which is what popped the keyboard up over the
/// results). The page drops the field's focus when a route
/// is pushed over it and again when it resurfaces.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PathProviderPlatform previous;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('b94_');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(dir.path);
    await Hive.initFlutter('${dir.path}/hive');
    await GStorage.init();
  });

  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await Hive.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('field focus is dropped on push and stays dropped on pop',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [rootRouteObserver],
        home: const MangaSearchPage(),
      ),
    );
    await tester.pump();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.tap(field);
    await tester.pump();
    final focusNode = tester.widget<TextField>(field).focusNode;
    expect(focusNode, isNotNull);
    expect(focusNode!.hasFocus, isTrue);

    // Open a "result" over the search page.
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('DETAIL')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);
    expect(focusNode.hasFocus, isFalse);

    // Back to the results: focus must stay down (no
    // keyboard resurrection).
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(MangaSearchPage), findsOneWidget);
    expect(focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}

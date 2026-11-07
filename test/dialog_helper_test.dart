import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/dialog/dialog_helper.dart';
import 'package:anikumo/navigation.dart';
import 'package:anikumo/services/player/timed_shutdown_service.dart';

Future<void> mountApp(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: rootNavigatorKey,
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    navigatorObservers: [AnikumoDialog.observer],
    home: const Scaffold(body: Text('home')),
  ));
  await tester.pumpAndSettle();
}

Future<void> pushPage(WidgetTester tester) async {
  unawaited(rootNavigatorKey.currentState!.push<void>(MaterialPageRoute(
    builder: (_) => const Scaffold(body: Text('new page')),
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('observer navigation and scoped toasts work without global keys',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [AnikumoDialog.observer],
      home: Builder(builder: (context) {
        pageContext = context;
        return const Scaffold(body: Text('home'));
      }),
    ));
    await tester.pumpAndSettle();
    final result = AnikumoDialog.show<bool>(
      builder: (_) => const AlertDialog(title: Text('operation')),
    );
    await tester.pumpAndSettle();
    expect(find.text('operation'), findsOneWidget);
    AnikumoDialog.dismiss(popWith: true);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    AnikumoDialog.showToast(context: pageContext, message: 'scoped result');
    await tester.pumpAndSettle();
    expect(find.text('scoped result'), findsOneWidget);
  });

  testWidgets('dismiss removes the tracked dialog beneath a newer page',
      (tester) async {
    await mountApp(tester);
    final result = AnikumoDialog.show<bool>(
      builder: (_) => const AlertDialog(title: Text('operation')),
    );
    await tester.pumpAndSettle();
    await pushPage(tester);

    AnikumoDialog.dismiss(popWith: true);
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.text('new page'), findsOneWidget);
    expect(AnikumoDialog.observer.hasAnikumoDialog, isFalse);
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('handles preserve another dialog and return the correct type',
      (tester) async {
    await mountApp(tester);
    final first = AnikumoDialogHandle<bool>();
    final firstResult = AnikumoDialog.show<bool>(
      handle: first,
      builder: (_) => const AlertDialog(title: Text('first')),
    );
    await tester.pumpAndSettle();
    final second = AnikumoDialogHandle<int>();
    final secondResult = AnikumoDialog.show<int>(
      handle: second,
      builder: (_) => const AlertDialog(title: Text('second')),
    );
    await tester.pumpAndSettle();

    first.dismiss(popWith: true);
    await tester.pumpAndSettle();
    expect(await firstResult, isTrue);
    expect(second.isActive, isTrue);
    expect(find.text('second'), findsOneWidget);
    first.dismiss();
    expect(second.isActive, isTrue);
    second.dismiss(popWith: 42);
    await tester.pumpAndSettle();
    expect(await secondResult, 42);
  });

  testWidgets('a dialog can finish before its builder is first called',
      (tester) async {
    await mountApp(tester);
    final dialog = AnikumoDialogHandle<int>();
    final result = AnikumoDialog.show<int>(
      handle: dialog,
      builder: (_) => const AlertDialog(title: Text('fast operation')),
    );
    expect(dialog.isActive, isTrue);
    dialog.dismiss(popWith: 7);
    await tester.pumpAndSettle();
    expect(await result, 7);
    expect(dialog.isActive, isFalse);
    expect(find.text('fast operation'), findsNothing);
  });

  testWidgets('context dismissal targets its own dialog beneath another',
      (tester) async {
    await mountApp(tester);
    late BuildContext firstContext;
    final first = AnikumoDialog.show<bool>(builder: (context) {
      firstContext = context;
      return const AlertDialog(title: Text('first'));
    });
    await tester.pumpAndSettle();
    final second = AnikumoDialogHandle<int>();
    final secondResult = AnikumoDialog.show<int>(
      handle: second,
      builder: (_) => const AlertDialog(title: Text('second')),
    );
    await tester.pumpAndSettle();
    AnikumoDialog.dismiss(context: firstContext, popWith: true);
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(second.isActive, isTrue);
    second.dismiss();
    await tester.pumpAndSettle();
    await secondResult;
  });

  testWidgets('back invalidates a handle immediately and awaits cleanup once',
      (tester) async {
    await mountApp(tester);
    final dialog = AnikumoDialogHandle<void>();
    final cleanup = Completer<void>();
    var cleanupCalls = 0;
    var finished = false;
    final result = AnikumoDialog.show<void>(
      handle: dialog,
      builder: (_) => const AlertDialog(title: Text('operation')),
      onDismiss: () async {
        cleanupCalls++;
        await cleanup.future;
      },
    ).then((_) => finished = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await rootNavigatorKey.currentState!.maybePop();
    expect(dialog.isActive, isFalse);
    await tester.pumpAndSettle();
    expect(cleanupCalls, 1);
    expect(finished, isFalse);
    cleanup.complete();
    await result;
    dialog.dismiss();
    expect(cleanupCalls, 1);
  });

  testWidgets('reusing an active handle does not orphan the first dialog',
      (tester) async {
    await mountApp(tester);
    final dialog = AnikumoDialogHandle<void>();
    final result = AnikumoDialog.show<void>(
      handle: dialog,
      builder: (_) => const AlertDialog(title: Text('first')),
    );
    await tester.pumpAndSettle();
    await expectLater(
      AnikumoDialog.show<void>(handle: dialog, builder: (_) => const SizedBox()),
      throwsStateError,
    );
    expect(dialog.isActive, isTrue);
    dialog.dismiss();
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('a toast posted after closing a dialog remains visible',
      (tester) async {
    await mountApp(tester);
    final dialog = AnikumoDialog.show<void>(
      builder: (_) => const AlertDialog(title: Text('share rule')),
    );
    await tester.pumpAndSettle();
    AnikumoDialog.dismiss();
    AnikumoDialog.showToast(message: 'rule copied');
    await tester.pumpAndSettle();
    await dialog;
    expect(find.text('rule copied'), findsOneWidget);
  });

  testWidgets('page pop clears its old toast', (tester) async {
    await mountApp(tester);
    await pushPage(tester);
    AnikumoDialog.showToast(message: 'old page');
    await tester.pumpAndSettle();
    rootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('old page'), findsNothing);
  });

  testWidgets('page pop preserves a toast posted after navigation',
      (tester) async {
    await mountApp(tester);
    await pushPage(tester);
    AnikumoDialog.showToast(message: 'old page');
    await tester.pumpAndSettle();
    rootNavigatorKey.currentState!.pop();
    AnikumoDialog.showToast(message: 'new result');
    await tester.pumpAndSettle();
    expect(find.text('new result'), findsOneWidget);
  });

  testWidgets('an action can replace its toast with progress feedback',
      (tester) async {
    await mountApp(tester);
    AnikumoDialog.showToast(
      message: 'updates available',
      showActionButton: true,
      actionLabel: 'update all',
      onActionPressed: () => AnikumoDialog.showToast(message: 'updating'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('update all'));
    await tester.pumpAndSettle();
    expect(find.text('updating'), findsOneWidget);
  });

  testWidgets('cancelling a timer only closes its own expiry dialog',
      (tester) async {
    await mountApp(tester);
    final timer = TimedShutdownService();
    timer.start(1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('定时关闭'), findsOneWidget);

    final second = AnikumoDialogHandle<int>();
    final result = AnikumoDialog.show<int>(
      handle: second,
      builder: (_) => const AlertDialog(title: Text('unrelated')),
    );
    await tester.pumpAndSettle();
    timer.cancel();
    await tester.pumpAndSettle();
    expect(second.isActive, isTrue);
    expect(find.text('unrelated'), findsOneWidget);
    second.dismiss();
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets('repeating the timer preserves its duration and expiry callback',
      (tester) async {
    await mountApp(tester);
    final timer = TimedShutdownService();
    addTearDown(timer.cancel);
    var expirations = 0;
    timer.start(1, onExpired: () => expirations++);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(expirations, 1);
    await tester.tap(find.text('重复'));
    await tester.pumpAndSettle();
    expect(timer.isActive, isTrue);
    expect(timer.setMinutes, 1);
    expect(find.text('重复'), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(expirations, 2);
    expect(find.text('重复'), findsOneWidget);
    timer.cancel();
    await tester.pumpAndSettle();
  });
}

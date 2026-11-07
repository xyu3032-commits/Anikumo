import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/bean/settings/settings_list.dart';

/// Batch 84: the font-size settings tile put its label and
/// a four-segment switch on ONE row. The switch's
/// intrinsic width starved the label's Expanded down to a
/// sliver — on device the label wrapped one character per
/// line (a tall vertical strip) and the tile ballooned.
/// Stacked tiles now give the control its own full-width
/// row; this pumps the exact worst case (portrait width,
/// the largest 1.3 text scale) and asserts the label keeps
/// its natural one-line height.
void main() {
  testWidgets('stacked tile: label stays one line, control below',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(720, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsTile(
            leading: Icons.format_size_rounded,
            title: const Text('字体大小'),
            description: const Text('全应用文字缩放'),
            stackTrailing: true,
            trailing: SizedBox(
              width: double.infinity,
              child: SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.85, label: Text('小')),
                  ButtonSegment(value: 1.0, label: Text('标准')),
                  ButtonSegment(value: 1.15, label: Text('大')),
                  ButtonSegment(value: 1.3, label: Text('特大')),
                ],
                selected: {1.3},
                onSelectionChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.text('字体大小'));
    // One line at 1.3 scale is ~27dp tall; a crushed
    // vertical strip would be hundreds of dp tall.
    expect(titleRect.height, lessThan(40));
    expect(titleRect.width, greaterThan(60));
    final controlRect = tester.getRect(find.text('特大'));
    expect(controlRect.top, greaterThan(titleRect.bottom));
    expect(controlRect.right, lessThanOrEqualTo(360));
  });

  testWidgets('same-row tile still renders for narrow controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsTile(
            title: Text('普通行'),
            description: Text('说明'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('普通行'), findsOneWidget);
  });
}

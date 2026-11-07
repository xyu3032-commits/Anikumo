// Batch 14: two-page spread math for landscape reading.
import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/services/manga/reader_spread.dart';

void main() {
  test('counts and identity pages', () {
    expect(spreadCount(0), 0);
    expect(spreadCount(1), 1);
    expect(spreadCount(10), 5);
    expect(spreadCount(11), 6);
    expect(spreadIndexOfPage(7), 3);
    expect(spreadFirstPage(3), 6);
  });

  test('visual order flips for RTL, trailing single page stays', () {
    expect(spreadVisualPages(1, 10, rtl: false), [2, 3]);
    expect(spreadVisualPages(1, 10, rtl: true), [3, 2]);
    expect(spreadVisualPages(5, 11, rtl: false), [10]);
    expect(spreadVisualPages(5, 11, rtl: true), [10]);
    expect(spreadVisualPages(6, 11, rtl: false), isEmpty);
  });
}

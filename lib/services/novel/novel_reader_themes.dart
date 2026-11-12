import 'package:flutter/painting.dart';

/// Batch 235 （排版主题 pack): reader paper themes for
/// the novel zone. A theme fixes the page background,
/// the body text color and the line height; font size
/// stays the reader's own setting.
class NovelReaderTheme {
  const NovelReaderTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.foreground,
    required this.lineHeight,
  });

  final String id;
  final String name;
  final Color background;
  final Color foreground;
  final double lineHeight;

  static const themes = <NovelReaderTheme>[
    NovelReaderTheme(
      id: 'paper',
      name: '纸黄',
      background: Color(0xFFF7F0DC),
      foreground: Color(0xFF3E3226),
      lineHeight: 1.85,
    ),
    NovelReaderTheme(
      id: 'eye',
      name: '护眼绿',
      background: Color(0xFFDCE8D5),
      foreground: Color(0xFF2E4038),
      lineHeight: 1.85,
    ),
    NovelReaderTheme(
      id: 'night',
      name: '夜间',
      background: Color(0xFF121212),
      foreground: Color(0xFFB8B8B8),
      lineHeight: 1.85,
    ),
  ];

  static NovelReaderTheme? byId(String id) {
    for (final theme in themes) {
      if (theme.id == id) return theme;
    }
    return null;
  }
}

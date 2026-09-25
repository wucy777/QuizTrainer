// 主题与配色。
//
// 采用「全局可变调色板」：切换主题时在根部 setState，整棵树重建后读取新配色。
// 好处是所有组件仍写 T.surface 这种短名字，改动面小；代价是它不是
// ThemeExtension 那套 idiomatic 写法，但本应用规模下足够清晰。
import 'package:flutter/material.dart';

/// 强调色预设
class Accent {
  final String name;
  final Color c1;
  final Color c2;
  const Accent(this.name, this.c1, this.c2);
}

const kAccents = <Accent>[
  Accent('靛紫', Color(0xFF6C8CFF), Color(0xFF9C7BFF)),
  Accent('青绿', Color(0xFF2DD4BF), Color(0xFF22C55E)),
  Accent('暖橙', Color(0xFFFB923C), Color(0xFFF59E0B)),
  Accent('玫红', Color(0xFFF472B6), Color(0xFFA855F7)),
  Accent('天蓝', Color(0xFF38BDF8), Color(0xFF6366F1)),
  Accent('石墨', Color(0xFF94A3B8), Color(0xFF64748B)),
];

/// 主题模式
enum ThemeMode2 { dark, light, system }

class T {
  static ThemeMode2 mode = ThemeMode2.dark;
  static int accentIndex = 0;
  static double fontScale = 1.0;

  static Accent get accentDef => kAccents[accentIndex.clamp(0, kAccents.length - 1)];
  static Color get accent => accentDef.c1;
  static Color get accent2 => accentDef.c2;

  /// 由平台亮度 + 用户选择决定当前是否深色
  static bool _dark = true;
  static bool get isDark => _dark;
  static void resolveDark(Brightness platform) {
    _dark = switch (mode) {
      ThemeMode2.dark => true,
      ThemeMode2.light => false,
      ThemeMode2.system => platform == Brightness.dark,
    };
  }

  static Color get bg => _dark ? const Color(0xFF0B0F14) : const Color(0xFFF3F6FA);
  static Color get surface => _dark ? const Color(0xFF141A22) : const Color(0xFFFFFFFF);
  static Color get surfaceHi => _dark ? const Color(0xFF1B232D) : const Color(0xFFE9EEF5);
  static Color get border => _dark ? const Color(0xFF243040) : const Color(0xFFD5DEE9);
  static Color get text => _dark ? const Color(0xFFE8EEF6) : const Color(0xFF17202C);
  static Color get muted => _dark ? const Color(0xFF8B9AAC) : const Color(0xFF57687C);
  static Color get dim => _dark ? const Color(0xFF5C6B7E) : const Color(0xFF8B98A8);

  static Color get green => _dark ? const Color(0xFF34D399) : const Color(0xFF0E9F6E);
  static Color get red => _dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get amber => _dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);

  static const radius = 16.0;

  /// 字号（随 fontScale 缩放）
  static double fs(double base) => base * fontScale;
}

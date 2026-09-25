// 配置与持久化：运行期配置、题库存储、刷题进度。
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'theme.dart';

/// 运行期配置
class Cfg {
  bool instant; // 单击选项即提交为答案
  bool feedback; // 立即显示对错并展示答案（instant 时）
  bool autoNextOnCorrect; // 答对后自动进入下一题（instant 时）
  bool autoNext; // 选择选项后自动进入下一题（非 instant 时）
  bool shuffle; // 切换题库时打乱顺序
  bool chineseFirst; // 中文说明放题目上方
  bool rememberProgress; // 记住每套题库的作答进度
  ThemeMode2 theme; // 明 / 暗 / 跟随系统
  int accent; // 强调色预设下标
  double fontScale; // 字号缩放

  Cfg({
    this.instant = true,
    this.feedback = true,
    this.autoNextOnCorrect = true,
    this.autoNext = true,
    this.shuffle = false,
    this.chineseFirst = false,
    this.rememberProgress = true,
    this.theme = ThemeMode2.dark,
    this.accent = 0,
    this.fontScale = 1.0,
  });

  static ThemeMode2 _theme(String? s) => switch (s) {
        'light' => ThemeMode2.light,
        'system' => ThemeMode2.system,
        _ => ThemeMode2.dark,
      };

  static String themeName(ThemeMode2 m) => switch (m) {
        ThemeMode2.light => 'light',
        ThemeMode2.system => 'system',
        ThemeMode2.dark => 'dark',
      };

  static Cfg fromMap(Map<String, dynamic> m) => Cfg(
        instant: m['instant'] as bool? ?? true,
        feedback: m['feedback'] as bool? ?? true,
        autoNextOnCorrect: m['autoNextOnCorrect'] as bool? ?? true,
        autoNext: m['autoNext'] as bool? ?? true,
        shuffle: m['shuffle'] as bool? ?? false,
        chineseFirst: m['chineseFirst'] as bool? ?? false,
        rememberProgress: m['rememberProgress'] as bool? ?? true,
        theme: _theme(m['theme'] as String?),
        accent: (m['accent'] as num?)?.toInt() ?? 0,
        fontScale: (m['fontScale'] as num?)?.toDouble() ?? 1.0,
      );

  Map<String, dynamic> toMap() => {
        'instant': instant,
        'feedback': feedback,
        'autoNextOnCorrect': autoNextOnCorrect,
        'autoNext': autoNext,
        'shuffle': shuffle,
        'chineseFirst': chineseFirst,
        'rememberProgress': rememberProgress,
        'theme': themeName(theme),
        'accent': accent,
        'fontScale': fontScale,
      };

  /// 把主题相关设置应用到全局调色板
  void applyTheme() {
    T.mode = theme;
    T.accentIndex = accent;
    T.fontScale = fontScale;
  }
}

/// 用户导入的题库保存在应用数据目录，下次启动自动载入。
class BankStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}banks');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();

  static Future<List<Bank>> loadAll() async {
    final d = await _dir();
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.json')) files.add(e);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final banks = <Bank>[];
    for (final f in files) {
      try {
        banks.add(loadBankFromString(await f.readAsString(), path: f.path));
      } catch (_) {
        // 单个文件坏了不影响其它
      }
    }
    return banks;
  }

  static Future<String> save(String name, String jsonText) async {
    final d = await _dir();
    final f = File('${d.path}${Platform.pathSeparator}${_safeName(name)}.json');
    await f.writeAsString(jsonText);
    return f.path;
  }

  static Future<void> remove(Bank bank) async {
    final p = bank.path;
    if (p == null) return;
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// 每套题库的作答进度（题号 / 已选 / 错题），用于「下次接着刷」。
class Progress {
  int idx;
  Map<String, List<String>> picks;
  List<String> wrong;
  Progress({this.idx = 0, Map<String, List<String>>? picks, List<String>? wrong})
      : picks = picks ?? {},
        wrong = wrong ?? [];

  Map<String, dynamic> toMap() => {'idx': idx, 'picks': picks, 'wrong': wrong};

  static Progress fromMap(Map<String, dynamic> m) => Progress(
        idx: (m['idx'] as num?)?.toInt() ?? 0,
        picks: (m['picks'] as Map?)?.map(
              (k, v) => MapEntry('$k', List<String>.from(v as List)),
            ) ??
            {},
        wrong: List<String>.from((m['wrong'] as List?) ?? const []),
      );
}

class ProgressStore {
  static String _key(String bank) => 'progress::$bank';

  static Future<Progress?> load(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(bank));
    if (raw == null) return null;
    try {
      return Progress.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String bank, Progress p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(bank), jsonEncode(p.toMap()));
  }

  static Future<void> clear(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(bank));
  }
}

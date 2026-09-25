// QuizTrainer —— 通用选择题刷题工具（Windows / Android）
//
// 本程序只做刷题工具，**不内嵌任何题库**，题库一律由用户以 JSON 文件导入。
//
// 两种作答模式（配置页联动勾选框）：
//   勾选「单击选项即提交为答案」→ 点一下就算作答
//       ├ 立即显示对错并展示答案
//       └ 答对后自动进入下一题（先短暂显示对错，答错则停留）
//   不勾选                      → 先选好，最后统一交卷
//       └ 选择选项后自动进入下一题
//
// 其他：方向键翻页、手势滑动翻页、按分类筛选、题库内搜索、进度记忆、
//       明暗主题与强调色、字号调节。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HapticFeedback,
        KeyDownEvent,
        LogicalKeyboardKey;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  runApp(const QuizTrainerApp());
}

class QuizTrainerApp extends StatefulWidget {
  /// 仅测试用：直接注入题库与配置。
  final List<Bank>? testBanks;
  final Cfg? testCfg;
  const QuizTrainerApp({super.key, this.testBanks, this.testCfg});

  @override
  State<QuizTrainerApp> createState() => _QuizTrainerAppState();
}

class _QuizTrainerAppState extends State<QuizTrainerApp> {
  Cfg _cfg = Cfg();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.testCfg != null) {
      _cfg = widget.testCfg!;
    } else {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cfg');
      if (raw != null) {
        try {
          _cfg = Cfg.fromMap(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          // 配置坏了就用默认值
        }
      }
    }
    _cfg.applyTheme();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _setCfg(Cfg c) async {
    setState(() {
      _cfg = c;
      _cfg.applyTheme();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cfg', jsonEncode(_cfg.toMap()));
  }

  ThemeData _theme() {
    T.resolveDark(WidgetsBinding.instance.platformDispatcher.platformBrightness);
    final dark = T.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: T.accent,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(surface: T.surface, primary: T.accent),
      scaffoldBackgroundColor: T.bg,
      dialogTheme: DialogThemeData(
        backgroundColor: T.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: T.surfaceHi,
        contentTextStyle: TextStyle(color: T.text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    return MaterialApp(
      title: 'QuizTrainer',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: _ready
          ? QuizHome(cfg: _cfg, onCfg: _setCfg, testBanks: widget.testBanks)
          : Scaffold(
              backgroundColor: T.bg,
              body: Center(child: CircularProgressIndicator(color: T.accent)),
            ),
    );
  }
}

class QuizHome extends StatefulWidget {
  final Cfg cfg;
  final Future<void> Function(Cfg) onCfg;
  final List<Bank>? testBanks;
  const QuizHome({
    super.key,
    required this.cfg,
    required this.onCfg,
    this.testBanks,
  });

  @override
  State<QuizHome> createState() => _QuizHomeState();
}

class _QuizHomeState extends State<QuizHome> {
  final List<Bank> _banks = [];
  int _bankIdx = 0;
  List<Question> _all = []; // 当前题库全部题目（可能已打乱）
  List<Question> _qs = []; // 当前可见题目（按分类筛选后）
  String? _category; // null = 全部
  int _idx = 0;
  final Map<String, Set<String>> _picks = {};
  final List<String> _wrong = [];
  bool _revealed = false;
  bool _loading = true;
  String? _loadError;

  Cfg get _cfg => widget.cfg;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final banks = widget.testBanks ?? await BankStore.loadAll();
      if (!mounted) return;
      setState(() {
        _banks
          ..clear()
          ..addAll(banks);
        _loading = false;
      });
      if (_banks.isNotEmpty) await _selectBank(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  // ── 题库与筛选 ──
  Future<void> _selectBank(int i) async {
    if (i < 0 || i >= _banks.length) return;
    final list = List<Question>.from(_banks[i].questions);
    if (_cfg.shuffle) list.shuffle();
    setState(() {
      _bankIdx = i;
      _all = list;
      _category = null;
      _qs = List<Question>.from(_all);
      _idx = 0;
      _picks.clear();
      _wrong.clear();
      _revealed = false;
    });
    await _restoreProgress();
  }

  List<String> get _categories {
    final seen = <String>[];
    for (final q in _all) {
      if (q.category.isNotEmpty && !seen.contains(q.category)) {
        seen.add(q.category);
      }
    }
    return seen;
  }

  void _applyFilter(String? cat) {
    setState(() {
      _category = cat;
      _qs = cat == null
          ? List<Question>.from(_all)
          : _all.where((q) => q.category == cat).toList();
      _idx = 0;
      _revealed = false;
    });
    _saveProgress();
  }

  // ── 进度记忆 ──
  Future<void> _restoreProgress() async {
    if (!_cfg.rememberProgress) return;
    final p = await ProgressStore.load(_banks[_bankIdx].name);
    if (p == null || !mounted) return;
    setState(() {
      _picks
        ..clear()
        ..addAll(p.picks.map((k, v) => MapEntry(k, v.toSet())));
      _wrong
        ..clear()
        ..addAll(p.wrong);
      if (p.idx > 0 && p.idx < _qs.length) _idx = p.idx;
      _revealed = false;
    });
  }

  void _saveProgress() {
    if (!_cfg.rememberProgress || _banks.isEmpty) return;
    ProgressStore.save(
      _banks[_bankIdx].name,
      Progress(
        idx: _idx,
        picks: _picks.map((k, v) => MapEntry(k, v.toList())),
        wrong: List<String>.from(_wrong),
      ),
    );
  }

  // ── 作答 ──
  void _onOption(Question q, String letter) {
    HapticFeedback.selectionClick(); // 桌面端为空操作
    if (_cfg.instant) {
      if (_revealed) return;
      final ok = q.isCorrect({letter});
      setState(() {
        _picks[q.key] = {letter};
        _judge(q, {letter});
      });
      _saveProgress();
      if (ok && _cfg.autoNextOnCorrect && _idx < _qs.length - 1) {
        Future.delayed(const Duration(milliseconds: 750), () {
          if (mounted && _revealed) _go(_idx + 1);
        });
      }
      return;
    }
    setState(() {
      final cur = Set<String>.from(_picks[q.key] ?? <String>{});
      if (q.multi) {
        cur.contains(letter) ? cur.remove(letter) : cur.add(letter);
        _picks[q.key] = cur;
      } else {
        _picks[q.key] = {letter};
        if (_cfg.autoNext && _idx < _qs.length - 1) {
          Future.delayed(const Duration(milliseconds: 160), () {
            if (mounted) _go(_idx + 1);
          });
        }
      }
    });
    _saveProgress();
  }

  void _judge(Question q, Set<String> chosen) {
    _revealed = true;
    if (q.isCorrect(chosen)) {
      _wrong.remove(q.key);
    } else if (!_wrong.contains(q.key)) {
      _wrong.add(q.key);
    }
  }

  void _go(int i) {
    if (i < 0 || i >= _qs.length) return;
    setState(() {
      _idx = i;
      _revealed = false;
    });
    _saveProgress();
  }

  Future<void> _grade() async {
    if (_qs.isEmpty) return;
    final answered = _picks.keys.where((k) => (_picks[k] ?? {}).isNotEmpty).length;
    if (!_cfg.instant && answered < _qs.length) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('确认交卷'),
          content: Text('还有 ${_qs.length - answered} 题未作答，确定现在交卷？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('交卷')),
          ],
        ),
      );
      if (go != true) return;
    }
    var correct = 0;
    final wrongKeys = <String>[];
    for (final q in _qs) {
      final ch = _picks[q.key] ?? <String>{};
      if (ch.isEmpty) {
        wrongKeys.add(q.key);
      } else if (q.isCorrect(ch)) {
        correct++;
      } else {
        wrongKeys.add(q.key);
      }
    }
    setState(() {
      _wrong
        ..clear()
        ..addAll(wrongKeys);
    });
    _saveProgress();
    if (!mounted) return;
    final pct = _qs.isEmpty ? 0 : (correct / _qs.length * 100).round();
    _showSheet(
      title: '成绩单与错题',
      score: '得分 $correct / ${_qs.length}（$pct%）· 错题 ${wrongKeys.length} 题',
      questions: _wrongQuestions(),
    );
  }

  List<Question> _wrongQuestions() {
    final byKey = {for (final q in _all) q.key: q};
    return _wrong.map((k) => byKey[k]).whereType<Question>().toList();
  }

  // ── 搜索 ──
  Future<void> _openSearch() async {
    if (_all.isEmpty) return;
    final picked = await showModalBottomSheet<Question>(
      context: context,
      isScrollControlled: true,
      backgroundColor: T.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => _SearchSheet(questions: _all),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _category = null;
      _qs = List<Question>.from(_all);
      final i = _qs.indexWhere((q) => q.key == picked.key);
      _idx = i < 0 ? 0 : i;
      _revealed = false;
    });
    _saveProgress();
  }

  // ── 弹窗 ──
  void _showSheet({
    required String title,
    String? score,
    required List<Question> questions,
    bool showRedo = true,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: T.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => _Sheet(
        title: title,
        score: score,
        questions: questions,
        onExport: () => _export(questions),
        onRedo: (showRedo && questions.isNotEmpty)
            ? () {
                Navigator.pop(c);
                setState(() {
                  _banks.add(Bank('错题重刷（${questions.length} 题）', questions));
                });
                _selectBank(_banks.length - 1);
              }
            : null,
      ),
    );
  }

  Future<void> _export(List<Question> questions) async {
    if (questions.isEmpty) {
      _toast('没有题目可导出');
      return;
    }
    final name = '${_banks[_bankIdx].name} · 错题';
    final text = bankToJsonString(questions, name);
    try {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出错题为 JSON',
        fileName: 'QuizTrainer_错题.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path != null) {
        _toast('已导出 ${questions.length} 题：\n$path');
        return;
      }
    } catch (_) {
      // 落回剪贴板
    }
    await Clipboard.setData(ClipboardData(text: text));
    _toast('已复制 ${questions.length} 题 JSON 到剪贴板');
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: '导入题库 JSON',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final String text;
      if (f.bytes != null) {
        text = utf8.decode(f.bytes!, allowMalformed: true);
      } else if (f.path != null) {
        text = await File(f.path!).readAsString();
      } else {
        _showErrors(['无法读取所选文件']);
        return;
      }
      final bank = loadBankFromString(text, path: f.path);
      String? saved;
      try {
        saved = await BankStore.save(bank.name, text);
      } catch (_) {
        saved = null;
      }
      final stored =
          saved == null ? bank : Bank(bank.name, bank.questions, path: saved);
      setState(() {
        _banks.removeWhere((b) => b.name == bank.name);
        _banks.add(stored);
      });
      await _selectBank(_banks.length - 1);
      _toast('已导入：${bank.name}（${bank.questions.length} 题）');
    } on BankFormatException catch (e) {
      _showErrors(e.errors);
    } catch (e) {
      _showErrors(['读取失败：$e']);
    }
  }

  void _showErrors(List<String> errors) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('题库格式错误'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('这个 JSON 不符合题库规范，未加载：\n'),
                ...errors.take(12).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('· $e'),
                    )),
                if (errors.length > 12) Text('· …（共 ${errors.length} 处问题）'),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('知道了')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _openConfig() async {
    final next = await showDialog<Cfg>(
      context: context,
      builder: (c) => _ConfigDialog(
        cfg: _cfg,
        banks: List<Bank>.from(_banks),
        onDeleteBank: _deleteBank,
      ),
    );
    if (next == null) return;
    await widget.onCfg(next);
    if (!mounted) return;
    setState(() => _revealed = false);
    _saveProgress();
  }

  Future<void> _deleteBank(Bank b) async {
    await BankStore.remove(b);
    await ProgressStore.clear(b.name);
    if (!mounted) return;
    setState(() {
      _banks.removeWhere((x) => x.name == b.name);
      if (_banks.isEmpty) {
        _all = [];
        _qs = [];
        _idx = 0;
        _picks.clear();
        _wrong.clear();
      }
    });
    if (_banks.isNotEmpty) await _selectBank(0);
    _toast('已移除题库：${b.name}');
  }

  // ── 构建 ──
  @override
  Widget build(BuildContext context) {
    final q = (_qs.isNotEmpty && _idx < _qs.length) ? _qs[_idx] : null;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _go(_idx - 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _go(_idx + 1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Column(
          children: [
            _TopBar(
              banks: _banks,
              bankIdx: _bankIdx,
              wide: wide,
              hasFilter: _categories.length > 1,
              filterActive: _category != null,
              onSelectBank: _selectBank,
              onSearch: _openSearch,
              onFilter: _openFilter,
              onImport: _import,
              onConfig: _openConfig,
              onWrongBook: () => _showSheet(
                title: '错题本',
                score: '共 ${_wrongQuestions().length} 道错题',
                questions: _wrongQuestions(),
              ),
            ),
            if (_qs.isNotEmpty)
              ProgressStrip(current: _idx + 1, total: _qs.length),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: T.accent))
                  : _loadError != null
                      ? Center(
                          child: Text('加载失败：$_loadError',
                              style: TextStyle(color: T.muted)))
                      : q == null
                          ? EmptyState(onImport: _import)
                          : _buildQuiz(q),
            ),
          ],
        ),
        bottomNavigationBar: _qs.isEmpty ? null : _buildNav(),
      ),
    );
  }

  void _openFilter() {
    final cats = _categories;
    final entries = <MapEntry<String?, int>>[
      MapEntry(null, _all.length),
      for (final c in cats)
        MapEntry(c, _all.where((q) => q.category == c).length),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: T.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text('按分类筛选',
                  style: TextStyle(
                      fontSize: T.fs(16),
                      fontWeight: FontWeight.w700,
                      color: T.text)),
            ),
            for (final e in entries)
              ListTile(
                leading: Icon(
                  e.key == _category
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: e.key == _category ? T.accent : T.dim,
                ),
                title: Text(e.key ?? '全部',
                    style: TextStyle(fontSize: T.fs(14), color: T.text)),
                trailing: Text('${e.value}',
                    style: TextStyle(fontSize: T.fs(12.5), color: T.muted)),
                onTap: () {
                  Navigator.pop(c);
                  _applyFilter(e.key);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuiz(Question q) {
    final chosen = _picks[q.key] ?? <String>{};
    final showAns = _cfg.instant && _cfg.feedback && _revealed;
    return GestureDetector(
      // 手势翻页：手机上滑动，桌面上按住拖动也行
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) {
          _go(_idx + 1);
        } else if (v > 200) {
          _go(_idx - 1);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: ListView(
              key: ValueKey(q.key),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip2(q.qid),
                    if (q.category.isNotEmpty) Chip2(q.category, muted: true),
                    if (q.multi) Chip2('多选', tone: T.amber),
                  ],
                ),
                const SizedBox(height: 16),
                if (_cfg.chineseFirst && q.sub.isNotEmpty) ...[
                  Text(q.text, style: _qStyle),
                  const SizedBox(height: 10),
                  NoteBlock(text: q.sub),
                ] else ...[
                  Text(q.text, style: _qStyle),
                  if (q.sub.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    NoteBlock(text: q.sub),
                  ],
                ],
                const SizedBox(height: 22),
                for (final L in q.options.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OptionTile(
                      letter: L,
                      text: q.options[L]!,
                      state: _optionState(q, L, chosen, showAns),
                      onTap: () => _onOption(q, L),
                    ),
                  ),
                if (_cfg.instant && _revealed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ResultBanner(
                      correct: q.isCorrect(chosen),
                      answerText: q.answerText,
                      showDetail: _cfg.feedback,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _qStyle => TextStyle(
        fontSize: T.fs(22),
        height: 1.4,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: T.text,
      );

  String _optionState(Question q, String L, Set<String> chosen, bool showAns) {
    final isAns = q.answers.contains(L);
    final isChosen = chosen.contains(L);
    if (showAns) {
      if (isAns && isChosen) return 'correct';
      if (isAns) return 'reveal';
      if (isChosen) return 'wrong';
      return 'dim';
    }
    return isChosen ? 'chosen' : 'idle';
  }

  Widget _buildNav() {
    final answered =
        _picks.keys.where((k) => (_picks[k] ?? {}).isNotEmpty).length;
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        border: Border(top: BorderSide(color: T.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            GhostButton(
              icon: Icons.arrow_back_rounded,
              label: '上一题',
              onTap: _idx > 0 ? () => _go(_idx - 1) : null,
            ),
            GhostButton(
              icon: Icons.arrow_forward_rounded,
              label: '下一题',
              trailingIcon: true,
              onTap: _idx < _qs.length - 1 ? () => _go(_idx + 1) : null,
            ),
            PrimaryButton(
              label: _cfg.instant ? '查看成绩' : '交卷',
              onTap: _grade,
            ),
            Text(
                '第 ${_idx + 1} / ${_qs.length} 题'
                '${_category == null ? '' : '（已筛选）'} · 已答 $answered',
                style: TextStyle(fontSize: T.fs(12.5), color: T.muted)),
          ],
        ),
      ),
    );
  }
}

/// 顶部栏
class _TopBar extends StatelessWidget {
  final List<Bank> banks;
  final int bankIdx;
  final bool wide;
  final bool hasFilter;
  final bool filterActive;
  final void Function(int) onSelectBank;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final VoidCallback onImport;
  final VoidCallback onConfig;
  final VoidCallback onWrongBook;

  const _TopBar({
    required this.banks,
    required this.bankIdx,
    required this.wide,
    required this.hasFilter,
    required this.filterActive,
    required this.onSelectBank,
    required this.onSearch,
    required this.onFilter,
    required this.onImport,
    required this.onConfig,
    required this.onWrongBook,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        border: Border(bottom: BorderSide(color: T.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [T.accent, T.accent2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child:
                  const Icon(Icons.bolt_rounded, size: 19, color: Colors.white),
            ),
            if (wide) ...[
              const SizedBox(width: 10),
              Text('QuizTrainer',
                  style: TextStyle(
                      fontSize: T.fs(16.5),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: T.text)),
            ],
            const SizedBox(width: 12),
            if (banks.isNotEmpty)
              Flexible(child: BankPicker(banks, bankIdx, onSelectBank)),
            const Spacer(),
            if (banks.isNotEmpty) ...[
              IconAction(
                  icon: Icons.search_rounded, tip: '搜索题目', onTap: onSearch),
              if (hasFilter)
                IconAction(
                  icon: Icons.filter_alt_outlined,
                  tip: '按分类筛选',
                  active: filterActive,
                  onTap: onFilter,
                ),
            ],
            IconAction(
                icon: Icons.file_open_outlined,
                tip: '导入题库',
                onTap: onImport),
            IconAction(icon: Icons.tune_rounded, tip: '配置', onTap: onConfig),
            IconAction(
                icon: Icons.bookmark_border_rounded,
                tip: '错题本',
                onTap: onWrongBook),
          ],
        ),
      ),
    );
  }
}

/// 题库内搜索
class _SearchSheet extends StatefulWidget {
  final List<Question> questions;
  const _SearchSheet({required this.questions});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  List<Question> get _hits {
    final k = _q.trim().toLowerCase();
    if (k.isEmpty) return const [];
    return widget.questions
        .where((x) =>
            x.text.toLowerCase().contains(k) ||
            x.sub.toLowerCase().contains(k) ||
            x.qid.toLowerCase().contains(k) ||
            x.category.toLowerCase().contains(k))
        .take(200)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (c, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: T.border, borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: TextField(
                controller: _ctl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: TextStyle(fontSize: T.fs(14), color: T.text),
                decoration: InputDecoration(
                  hintText: '搜索题干、说明、题号或分类',
                  hintStyle: TextStyle(color: T.dim, fontSize: T.fs(13.5)),
                  prefixIcon: Icon(Icons.search_rounded, color: T.muted),
                  filled: true,
                  fillColor: T.surfaceHi,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: T.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: T.border),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _q.trim().isEmpty
                  ? Center(
                      child: Text('输入关键词开始搜索',
                          style:
                              TextStyle(color: T.muted, fontSize: T.fs(13))))
                  : hits.isEmpty
                      ? Center(
                          child: Text('没有匹配的题目',
                              style:
                                  TextStyle(color: T.muted, fontSize: T.fs(13))))
                      : ListView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          itemCount: hits.length,
                          itemBuilder: (c, i) {
                            final x = hits[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(context, x),
                                child: Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: T.surfaceHi,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: T.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${x.qid}   ·   ${x.category}',
                                          style: TextStyle(
                                              fontSize: T.fs(11.5),
                                              color: T.dim)),
                                      const SizedBox(height: 5),
                                      Text(x.text,
                                          style: TextStyle(
                                              fontSize: T.fs(14),
                                              height: 1.45,
                                              color: T.text)),
                                      if (x.sub.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Text(x.sub,
                                              style: TextStyle(
                                                  fontSize: T.fs(12.5),
                                                  color: T.muted)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Row(
                children: [
                  Text('匹配 ${hits.length} 题',
                      style: TextStyle(fontSize: T.fs(12.5), color: T.muted)),
                  const Spacer(),
                  PrimaryButton(
                      label: '关闭', onTap: () => Navigator.pop(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错题本 / 成绩单
class _Sheet extends StatelessWidget {
  final String title;
  final String? score;
  final List<Question> questions;
  final VoidCallback onExport;
  final VoidCallback? onRedo;
  const _Sheet({
    required this.title,
    required this.score,
    required this.questions,
    required this.onExport,
    this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (c, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: T.border, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: T.fs(19),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: T.text)),
                if (score != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        T.accent.withValues(alpha: 0.16),
                        T.accent2.withValues(alpha: 0.10),
                      ]),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: T.accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(score!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: T.fs(15.5),
                            fontWeight: FontWeight.w600,
                            color: T.text)),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: questions.isEmpty
                ? Center(
                    child: Text('没有错题，继续保持！',
                        style: TextStyle(color: T.muted)))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: questions.length,
                    itemBuilder: (c, i) {
                      final q = questions[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: T.surfaceHi,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: T.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${q.qid}   ·   ${q.category}',
                                style: TextStyle(
                                    fontSize: T.fs(11.5), color: T.dim)),
                            const SizedBox(height: 6),
                            Text(q.text,
                                style: TextStyle(
                                    fontSize: T.fs(14.5),
                                    height: 1.5,
                                    color: T.text)),
                            if (q.sub.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(q.sub,
                                    style: TextStyle(
                                        fontSize: T.fs(12.5),
                                        height: 1.5,
                                        color: T.muted)),
                              ),
                            const SizedBox(height: 8),
                            Text('✔ ${q.answerText}',
                                style: TextStyle(
                                    fontSize: T.fs(13),
                                    height: 1.45,
                                    color: T.green)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GhostButton(
                    icon: Icons.save_alt_rounded,
                    label: '导出 JSON',
                    onTap: onExport),
                if (onRedo != null)
                  GhostButton(
                      icon: Icons.refresh_rounded,
                      label: '重刷这些题',
                      onTap: onRedo!),
                PrimaryButton(label: '关闭', onTap: () => Navigator.pop(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 配置页
class _ConfigDialog extends StatefulWidget {
  final Cfg cfg;
  final List<Bank> banks;
  final Future<void> Function(Bank) onDeleteBank;
  const _ConfigDialog({
    required this.cfg,
    required this.banks,
    required this.onDeleteBank,
  });

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late Cfg c = Cfg.fromMap(widget.cfg.toMap());
  late List<Bank> banks = List<Bank>.from(widget.banks);

  Widget _check({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    String? subtitle,
    bool enabled = true,
    bool bold = false,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: T.accent,
        title: Text(title,
            style: TextStyle(
                fontSize: T.fs(14),
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: T.text)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: TextStyle(
                    fontSize: T.fs(11.5), height: 1.5, color: T.dim)),
      ),
    );
  }

  Widget _seg<T2>(
      String label, List<(T2, String)> opts, T2 cur, ValueChanged<T2> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(label,
                  style: TextStyle(fontSize: T.fs(13.5), color: T.text)),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (v, name) in opts)
                  GestureDetector(
                    onTap: () => onPick(v),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: v == cur
                            ? T.accent.withValues(alpha: 0.18)
                            : T.surfaceHi,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: v == cur ? T.accent : T.border),
                      ),
                      child: Text(name,
                          style: TextStyle(
                              fontSize: T.fs(12.5),
                              color: v == cur ? T.accent : T.muted,
                              fontWeight: v == cur
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('设置',
          style: TextStyle(fontSize: T.fs(18), fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('外观'),
              _seg<ThemeMode2>('主题', [
                (ThemeMode2.dark, '深色'),
                (ThemeMode2.light, '浅色'),
                (ThemeMode2.system, '跟随系统'),
              ], c.theme, (v) => setState(() => c.theme = v)),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text('强调色',
                            style: TextStyle(
                                fontSize: T.fs(13.5), color: T.text)),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < kAccents.length; i++)
                            Tooltip(
                              message: kAccents[i].name,
                              child: GestureDetector(
                                onTap: () => setState(() => c.accent = i),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        kAccents[i].c1,
                                        kAccents[i].c2
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                      color: c.accent == i
                                          ? T.text
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: c.accent == i
                                      ? const Icon(Icons.check_rounded,
                                          size: 16, color: Colors.white)
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _seg<double>('字号', [
                (0.9, '小'),
                (1.0, '标准'),
                (1.15, '大'),
                (1.3, '特大'),
              ], c.fontScale, (v) => setState(() => c.fontScale = v)),
              Divider(height: 26, color: T.border),
              const _SectionTitle('作答'),
              _check(
                value: c.instant,
                onChanged: (v) => setState(() => c.instant = v),
                title: '单击选项即提交为答案',
                subtitle: '勾选：点一下选项就算作答。\n不勾选：先选好，全部打完点『交卷』统一提交。',
                bold: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Column(
                  children: [
                    _check(
                      value: c.feedback,
                      onChanged: (v) => setState(() => c.feedback = v),
                      title: '立即显示对错并展示答案',
                      enabled: c.instant,
                    ),
                    _check(
                      value: c.autoNextOnCorrect,
                      onChanged: (v) => setState(() => c.autoNextOnCorrect = v),
                      title: '答对后自动进入下一题',
                      subtitle: '答对时先短暂显示对错，再自动翻到下一题；答错则停留供查看。',
                      enabled: c.instant,
                    ),
                    _check(
                      value: c.autoNext,
                      onChanged: (v) => setState(() => c.autoNext = v),
                      title: '选择选项后自动进入下一题',
                      enabled: !c.instant,
                    ),
                  ],
                ),
              ),
              Divider(height: 26, color: T.border),
              const _SectionTitle('其他'),
              _check(
                value: c.shuffle,
                onChanged: (v) => setState(() => c.shuffle = v),
                title: '切换题库时打乱题目顺序',
              ),
              _check(
                value: c.chineseFirst,
                onChanged: (v) => setState(() => c.chineseFirst = v),
                title: '把中文说明放在题目上方',
                subtitle: '默认中文在英文题目下方；勾选后中文在上、英文在下',
              ),
              _check(
                value: c.rememberProgress,
                onChanged: (v) => setState(() => c.rememberProgress = v),
                title: '记住每套题库的作答进度',
                subtitle: '下次打开自动回到上次的位置，并保留已选与错题',
              ),
              Divider(height: 26, color: T.border),
              const _SectionTitle('已导入题库'),
              Text('题库保存在本机，下次启动自动载入。',
                  style: TextStyle(fontSize: T.fs(11.5), color: T.dim)),
              const SizedBox(height: 8),
              if (banks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('还没有导入任何题库',
                      style: TextStyle(fontSize: T.fs(12.5), color: T.muted)),
                )
              else
                for (final b in banks)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(
                      color: T.surfaceHi,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: T.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${b.name}（${b.questions.length} 题）',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: T.fs(13), color: T.text)),
                        ),
                        IconButton(
                          tooltip: '移除',
                          icon: Icon(Icons.delete_outline,
                              size: 19, color: T.muted),
                          onPressed: () async {
                            await widget.onDeleteBank(b);
                            if (mounted) setState(() => banks.remove(b));
                          },
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: T.muted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c),
          style: FilledButton.styleFrom(backgroundColor: T.accent),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: T.fs(14),
                fontWeight: FontWeight.w700,
                color: T.text)),
      );
}

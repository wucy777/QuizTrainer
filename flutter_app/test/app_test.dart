// QuizTrainer UI 交互测试：作答、配置联动、筛选、搜索、翻页、主题。
//
// 程序不内嵌题库，测试通过 testBanks 注入，并单独验证“无题库”空状态。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_trainer/main.dart';
import 'package:quiz_trainer/models.dart';
import 'package:quiz_trainer/store.dart';
import 'package:quiz_trainer/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 造一个 n 题的测试题库（ABCD 四选项，答案为 A，按 10 题一组分类）
Bank makeBank({int n = 60, String name = '测试题库'}) {
  return loadBankFromString(jsonEncode({
    '题库名称': name,
    '题目列表': [
      for (var i = 1; i <= n; i++)
        {
          '题号': 'Q$i',
          '分类': '第${(i - 1) ~/ 10 + 1}组',
          '题目': 'Question $i?',
          '副题目': '第 $i 题的中文说明',
          '正确答案选项': 'A',
          '选项': {
            'A': 'answer A of $i',
            'B': 'answer B of $i',
            'C': 'answer C of $i',
            'D': 'answer D of $i',
          }
        }
    ]
  }));
}

Cfg cfgOf({
  bool instant = true,
  bool feedback = true,
  bool autoNextOnCorrect = false,
  bool autoNext = true,
  bool shuffle = false,
  bool chineseFirst = false,
  bool rememberProgress = false,
  ThemeMode2 theme = ThemeMode2.dark,
  int accent = 0,
  double fontScale = 1.0,
}) =>
    Cfg(
      instant: instant,
      feedback: feedback,
      autoNextOnCorrect: autoNextOnCorrect,
      autoNext: autoNext,
      shuffle: shuffle,
      chineseFirst: chineseFirst,
      rememberProgress: rememberProgress,
      theme: theme,
      accent: accent,
      fontScale: fontScale,
    );

Future<void> boot(
  WidgetTester tester, {
  List<Bank>? banks,
  Cfg? cfg,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.runAsync(() async {
    await tester.pumpWidget(QuizTrainerApp(
      testBanks: banks ?? [makeBank()],
      testCfg: cfg ?? cfgOf(),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() {
    // 全局调色板是静态的，测试之间要复位
    T.mode = ThemeMode2.dark;
    T.accentIndex = 0;
    T.fontScale = 1.0;
    T.resolveDark(Brightness.dark);
  });

  group('基本界面', () {
    testWidgets('显示题目、说明、选项与导航', (tester) async {
      await boot(tester);
      expect(find.text('QuizTrainer'), findsOneWidget);
      expect(find.text('上一题'), findsOneWidget);
      expect(find.text('下一题'), findsOneWidget);
      expect(find.text('Question 1?'), findsOneWidget);
      expect(find.text('第 1 题的中文说明'), findsOneWidget);
      for (final L in ['A', 'B', 'C', 'D']) {
        expect(find.text(L), findsWidgets, reason: '缺少选项 $L');
      }
      expect(find.textContaining('/ 60 题'), findsOneWidget);
    });

    testWidgets('没有题库时显示空状态与导入入口', (tester) async {
      await boot(tester, banks: []);
      expect(find.text('还没有题库'), findsOneWidget);
      expect(find.text('导入题库 JSON'), findsOneWidget);
      expect(find.text('上一题'), findsNothing);
    });
  });

  group('作答', () {
    testWidgets('模式A 点对 -> 显示答对了', (tester) async {
      await boot(tester);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(find.textContaining('答对了'), findsOneWidget);
      expect(find.text('查看成绩'), findsOneWidget);
    });

    testWidgets('模式A 点错 -> 标出正确答案', (tester) async {
      await boot(tester);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(find.textContaining('答错了'), findsOneWidget);
      expect(find.textContaining('正确答案：A)'), findsOneWidget);
    });

    testWidgets('答对后自动下一题：开启时翻页', (tester) async {
      await boot(tester, cfg: cfgOf(autoNextOnCorrect: true));
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(find.textContaining('答对了'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Question 2?'), findsOneWidget);
    });

    testWidgets('答对后自动下一题：答错停留', (tester) async {
      await boot(tester, cfg: cfgOf(autoNextOnCorrect: true));
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(find.textContaining('答错了'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Question 1?'), findsOneWidget);
    });

    testWidgets('统一交卷模式：先选不判分，交卷出成绩单', (tester) async {
      await boot(tester, cfg: cfgOf(instant: false, autoNext: false));
      expect(find.text('交卷'), findsOneWidget);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(find.textContaining('答对了'), findsNothing);
      await tester.tap(find.text('交卷'));
      await tester.pumpAndSettle();
      expect(find.text('确认交卷'), findsOneWidget);
      await tester.tap(find.text('交卷').last);
      await tester.pumpAndSettle();
      expect(find.text('成绩单与错题'), findsOneWidget);
      expect(find.textContaining('得分 1 / 60'), findsOneWidget);
    });
  });

  group('导航', () {
    testWidgets('按钮翻页与进度', (tester) async {
      await boot(tester);
      expect(find.textContaining('第 1 / 60 题'), findsOneWidget);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2?'), findsOneWidget);
      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1?'), findsOneWidget);
    });

    testWidgets('方向键翻页', (tester) async {
      await boot(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Question 2?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Question 1?'), findsOneWidget);
    });

    testWidgets('滑动翻页', (tester) async {
      await boot(tester);
      await tester.fling(find.text('Question 1?'), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('Question 2?'), findsOneWidget);
    });
  });

  group('筛选与搜索', () {
    testWidgets('按分类筛选只留该组', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pumpAndSettle();
      expect(find.text('按分类筛选'), findsOneWidget);
      await tester.tap(find.text('第2组'));
      await tester.pumpAndSettle();
      expect(find.text('Question 11?'), findsOneWidget);
      expect(find.textContaining('/ 10 题'), findsOneWidget);
      expect(find.textContaining('（已筛选）'), findsOneWidget);
    });

    testWidgets('搜索并跳转到命中的题目', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.text('输入关键词开始搜索'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Question 42');
      await tester.pumpAndSettle();
      expect(find.textContaining('匹配 1 题'), findsOneWidget);
      await tester.tap(find.text('Question 42?').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('第 42 / 60 题'), findsOneWidget);
    });

    testWidgets('搜索无结果时提示', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的题目'), findsOneWidget);
    });
  });

  group('设置', () {
    testWidgets('子勾选框按主勾选框互斥联动', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);

      CheckboxListTile tileOf(String label) => tester.widget<CheckboxListTile>(
            find.ancestor(
                of: find.text(label), matching: find.byType(CheckboxListTile)),
          );

      expect(tileOf('立即显示对错并展示答案').onChanged, isNotNull);
      expect(tileOf('答对后自动进入下一题').onChanged, isNotNull);
      expect(tileOf('选择选项后自动进入下一题').onChanged, isNull);

      await tester.tap(find.text('单击选项即提交为答案'));
      await tester.pumpAndSettle();
      expect(tileOf('立即显示对错并展示答案').onChanged, isNull);
      expect(tileOf('答对后自动进入下一题').onChanged, isNull);
      expect(tileOf('选择选项后自动进入下一题').onChanged, isNotNull);
    });

    testWidgets('列出已导入题库并可移除', (tester) async {
      await boot(tester,
          banks: [makeBank(name: '题库甲'), makeBank(name: '题库乙')]);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('已导入题库'), findsOneWidget);
      expect(find.textContaining('题库甲'), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('字号切换会改变题目字号', (tester) async {
      await boot(tester);
      double qFont() =>
          tester.widget<Text>(find.text('Question 1?')).style!.fontSize!;
      final base = qFont();
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('特大'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(qFont(), closeTo(base * 1.3, 0.01));
    });

    testWidgets('主题与强调色可切换', (tester) async {
      await boot(tester);
      expect(T.isDark, isTrue);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('暖橙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(T.isDark, isFalse, reason: '应切到浅色主题');
      expect(T.accentIndex, 2);
    });
  });

  group('错题本', () {
    testWidgets('可打开并显示导出入口', (tester) async {
      await boot(tester);
      await tester.tap(find.byIcon(Icons.bookmark_border_rounded));
      await tester.pumpAndSettle();
      expect(find.text('错题本'), findsOneWidget);
      expect(find.text('导出 JSON'), findsOneWidget);
    });
  });
}

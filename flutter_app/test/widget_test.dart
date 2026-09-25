// QuizTrainer 测试：题库解析与校验规则、配置、进度、主题
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_trainer/models.dart';
import 'package:quiz_trainer/store.dart';
import 'package:quiz_trainer/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('题库解析', () {
    test('最小合法题库可解析', () {
      final bank = loadBankFromString(jsonEncode({
        '题库名称': '测试库',
        '题目列表': [
          {
            '题目': 'Where was the cat found?',
            '副题目': '猫是在哪里被发现的？',
            '正确答案选项': 'B',
            '选项': {
              'A': 'At the gate of a grade school.',
              'B': "Under the engine cover of a man's car.",
              'C': "Inside the car of David King's neighbour.",
              'D': 'Outside the office of a charity foundation.',
            }
          }
        ]
      }));
      expect(bank.name, '测试库');
      expect(bank.questions.length, 1);
      expect(bank.questions.first.answers, ['B']);
      expect(bank.questions.first.multi, false);
      expect(bank.questions.first.options.length, 4);
    });

    test('副题目可以为空', () {
      final bank = loadBankFromString(jsonEncode({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': '光速约为多少？',
            '副题目': '',
            '正确答案选项': 'A',
            '选项': {'A': '3e8 m/s', 'B': '3e6 m/s'}
          }
        ]
      }));
      expect(bank.questions.first.sub, '');
    });

    test('多选答案支持数组', () {
      final bank = loadBankFromString(jsonEncode({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': '哪些是哺乳动物？',
            '副题目': '',
            '正确答案选项': ['A', 'C'],
            '选项': {'A': '鲸', 'B': '鲨鱼', 'C': '蝙蝠', 'D': '鳄鱼'}
          }
        ]
      }));
      final q = bank.questions.first;
      expect(q.multi, true);
      expect(q.isCorrect(['A', 'C']), true);
      expect(q.isCorrect(['C', 'A']), true);
      expect(q.isCorrect(['A']), false);
    });

    test('支持 A-O 共 15 个选项（选词填空）', () {
      final opts = <String, String>{
        for (var i = 0; i < 15; i++) String.fromCharCode(65 + i): 'word$i'
      };
      final bank = loadBankFromString(jsonEncode({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': 'blank ______',
            '副题目': 'chance 机会',
            '正确答案选项': 'C',
            '选项': opts
          }
        ]
      }));
      expect(bank.questions.first.options.length, 15);
    });

    test('题号重复时内部键仍唯一', () {
      final bank = loadBankFromString(jsonEncode({
        '题库名称': 'x',
        '题目列表': [
          for (var i = 0; i < 3; i++)
            {
              '题号': '听力 Q1',
              '题目': 'q$i',
              '副题目': '',
              '正确答案选项': 'A',
              '选项': {'A': '1', 'B': '2'}
            }
        ]
      }));
      final keys = bank.questions.map((q) => q.key).toSet();
      expect(keys.length, 3, reason: '内部键必须唯一，否则答案会互相覆盖');
    });
  });

  group('校验规则（都应被拒绝）', () {
    void expectReject(Map<String, dynamic> obj, String keyword) {
      try {
        parseBank(obj);
        fail('本应被拒绝：$keyword');
      } on BankFormatException catch (e) {
        expect(e.errors.join('；'), contains(keyword));
      }
    }

    test('空题目列表', () {
      expectReject({'题库名称': 'x', '题目列表': <dynamic>[]}, '题目列表');
    });

    test('答案不在选项内（abcd 却答 e）', () {
      expectReject({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': 'x',
            '副题目': '',
            '正确答案选项': 'E',
            '选项': {'A': '1', 'B': '2', 'C': '3', 'D': '4'}
          }
        ]
      }, '不在选项');
    });

    test('选项少于 2 个', () {
      expectReject({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': 'x',
            '副题目': '',
            '正确答案选项': 'A',
            '选项': {'A': '1'}
          }
        ]
      }, '少于 2 个');
    });

    test('选项键小写', () {
      expectReject({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': 'x',
            '副题目': '',
            '正确答案选项': 'A',
            '选项': {'a': '1', 'B': '2'}
          }
        ]
      }, '非法');
    });

    test('题干含整理残留标记', () {
      expectReject({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': 'x ✅ 【B】',
            '副题目': '',
            '正确答案选项': 'A',
            '选项': {'A': '1', 'B': '2'}
          }
        ]
      }, '残留标记');
    });

    test('题干为空', () {
      expectReject({
        '题库名称': 'x',
        '题目列表': [
          {
            '题目': '',
            '副题目': '',
            '正确答案选项': 'A',
            '选项': {'A': '1', 'B': '2'}
          }
        ]
      }, '题目为空');
    });

    test('JSON 语法错误', () {
      expect(
        () => loadBankFromString('{ 不是 json }'),
        throwsA(isA<BankFormatException>()),
      );
    });
  });

  group('导出', () {
    test('导出后可再次导入（往返一致）', () {
      final bank = loadBankFromString(jsonEncode({
        '题库名称': '往返',
        '题目列表': [
          {
            '题号': '阅读 Q50',
            '分类': '阅读 · Section C',
            '题目': 'What is one factor essential to success?',
            '副题目': '在美国取得成功的一个关键因素是什么？',
            '正确答案选项': 'D',
            '选项': {
              'A': 'a',
              'B': 'b',
              'C': 'c',
              'D': 'A clear aim and high motivation.'
            }
          }
        ]
      }));
      final text = bankToJsonString(bank.questions, bank.name);
      final again = loadBankFromString(text);
      expect(again.name, '往返');
      expect(again.questions.length, 1);
      expect(again.questions.first.answers, ['D']);
      expect(again.questions.first.options, bank.questions.first.options);
      expect(again.questions.first.text, bank.questions.first.text);
    });
  });

  group('配置', () {
    test('Cfg 往返一致', () {
      final c = Cfg(
        instant: false,
        feedback: false,
        autoNextOnCorrect: false,
        autoNext: false,
        shuffle: true,
        chineseFirst: true,
        rememberProgress: false,
        theme: ThemeMode2.light,
        accent: 3,
        fontScale: 1.3,
      );
      final back = Cfg.fromMap(jsonDecode(jsonEncode(c.toMap())));
      expect(back.instant, false);
      expect(back.shuffle, true);
      expect(back.chineseFirst, true);
      expect(back.rememberProgress, false);
      expect(back.theme, ThemeMode2.light);
      expect(back.accent, 3);
      expect(back.fontScale, 1.3);
    });

    test('缺字段时用默认值', () {
      final c = Cfg.fromMap(<String, dynamic>{});
      expect(c.instant, true);
      expect(c.feedback, true);
      expect(c.autoNextOnCorrect, true);
      expect(c.theme, ThemeMode2.dark);
      expect(c.accent, 0);
      expect(c.fontScale, 1.0);
    });
  });

  group('进度记忆', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('Progress 往返一致', () {
      final p = Progress(
        idx: 12,
        picks: {
          'q1': ['A'],
          'q2': ['B', 'C'],
        },
        wrong: ['q2'],
      );
      final back = Progress.fromMap(jsonDecode(jsonEncode(p.toMap())));
      expect(back.idx, 12);
      expect(back.picks['q1'], ['A']);
      expect(back.picks['q2'], ['B', 'C']);
      expect(back.wrong, ['q2']);
    });

    test('保存 / 读取 / 清除', () async {
      expect(await ProgressStore.load('甲库'), isNull);
      await ProgressStore.save('甲库', Progress(idx: 7, wrong: ['q3']));
      final p = await ProgressStore.load('甲库');
      expect(p, isNotNull);
      expect(p!.idx, 7);
      expect(p.wrong, ['q3']);
      // 不同题库互不干扰
      expect(await ProgressStore.load('乙库'), isNull);
      await ProgressStore.clear('甲库');
      expect(await ProgressStore.load('甲库'), isNull);
    });
  });

  group('主题', () {
    tearDown(() {
      T.mode = ThemeMode2.dark;
      T.accentIndex = 0;
      T.fontScale = 1.0;
      T.resolveDark(Brightness.dark);
    });

    test('深/浅色切换改变底色', () {
      T.mode = ThemeMode2.dark;
      T.resolveDark(Brightness.light);
      expect(T.isDark, isTrue, reason: '强制深色时不受系统影响');
      final darkBg = T.bg;

      T.mode = ThemeMode2.light;
      T.resolveDark(Brightness.dark);
      expect(T.isDark, isFalse, reason: '强制浅色时不受系统影响');
      expect(T.bg, isNot(darkBg));
    });

    test('跟随系统时由平台亮度决定', () {
      T.mode = ThemeMode2.system;
      T.resolveDark(Brightness.dark);
      expect(T.isDark, isTrue);
      T.resolveDark(Brightness.light);
      expect(T.isDark, isFalse);
    });

    test('字号缩放', () {
      T.fontScale = 1.0;
      expect(T.fs(20), 20);
      T.fontScale = 1.5;
      expect(T.fs(20), 30);
    });

    test('强调色预设可切换', () {
      T.accentIndex = 0;
      final a = T.accent;
      T.accentIndex = 1;
      expect(T.accent, isNot(a));
      expect(T.accent, kAccents[1].c1);
    });
  });
}

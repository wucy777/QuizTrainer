// QuizTrainer 核心：题库模型与 JSON 校验。
//
// 题库 JSON 规范（与 Windows/HTML 版完全一致）：
// {
//   "题库名称": "...",
//   "题目列表": [
//     {"题号":"可选", "分类":"可选", "题目":"题干", "副题目":"说明/可为空",
//      "正确答案选项":"B" 或 ["A","C"], "选项":{"A":"...","B":"..."}}
//   ]
// }
//
// 校验规则（任一条不满足即拒绝加载并逐条说明原因）：
//   1. 顶层为对象，含 题库名称 与 题目列表（非空数组）
//   2. 每题含 题目/副题目/正确答案选项/选项
//   3. 选项为对象，键为单个大写字母，≥2 个，值非空
//   4. 正确答案选项必须存在于选项键中
//   5. 题干非空，且不含 ✅ / 【X】 / -> X 之类残留标记
import 'dart:convert';

final RegExp _letter = RegExp(r'^[A-Z]$');
final RegExp _mark = RegExp(r'[✅✔]|【[A-Z]】|->\s*[A-Z]\b');

/// 题库格式错误，携带逐条中文说明。
class BankFormatException implements Exception {
  final List<String> errors;
  BankFormatException(this.errors);
  @override
  String toString() {
    final head = errors.take(4).join('；');
    return errors.length > 4 ? '$head（共 ${errors.length} 处问题）' : head;
  }
}

class Question {
  final int index;
  final String qid;
  final String category;
  final String text; // 题目
  final String sub; // 副题目（说明/提示/翻译），可为空
  final List<String> answers; // 正确答案字母（>1 表示多选）
  final Map<String, String> options; // 有序 A..O

  Question({
    required this.index,
    required this.qid,
    required this.category,
    required this.text,
    required this.sub,
    required this.answers,
    required this.options,
  });

  /// 题库内唯一的内部键：不同试卷的『题号』会重复（如 5 套卷都有「听力 Q1」），
  /// 因此不能用题号当字典键，否则答案会互相覆盖。
  String get key => 'q$index';

  bool get multi => answers.length > 1;

  String get answerText =>
      answers.map((L) => '$L) ${options[L] ?? ''}').join('、');

  bool isCorrect(Iterable<String> chosen) {
    final a = answers.toSet();
    final c = chosen.toSet();
    return a.length == c.length && a.every(c.contains);
  }
}

class Bank {
  final String name;
  final List<Question> questions;
  final String? path;
  Bank(this.name, this.questions, {this.path});

  List<String> get categories {
    final seen = <String>[];
    for (final q in questions) {
      if (q.category.isNotEmpty && !seen.contains(q.category)) {
        seen.add(q.category);
      }
    }
    return seen;
  }
}

List<String> _asLetters(dynamic value, String tag, List<String> errors) {
  if (value is String) {
    final v = value.trim();
    if (v.isEmpty) {
      errors.add('$tag: 正确答案选项为空');
      return [];
    }
    if (v.length > 1 && RegExp(r'^[A-Za-z]+$').hasMatch(v)) {
      return v.toUpperCase().split('');
    }
    if (!_letter.hasMatch(v.toUpperCase())) {
      errors.add('$tag: 正确答案选项 "$value" 不是字母');
      return [];
    }
    return [v.toUpperCase()];
  }
  if (value is List) {
    final out = <String>[];
    for (final item in value) {
      if (item is! String || !_letter.hasMatch(item.trim().toUpperCase())) {
        errors.add('$tag: 正确答案选项数组含非法项 "$item"');
        continue;
      }
      out.add(item.trim().toUpperCase());
    }
    if (out.isEmpty) errors.add('$tag: 正确答案选项数组为空');
    return out.toSet().toList()..sort();
  }
  errors.add('$tag: 正确答案选项类型非法（应为字符串或数组）');
  return [];
}

/// 解析已解码的 JSON 对象；失败抛 [BankFormatException]。
Bank parseBank(dynamic obj, {String? path}) {
  final errors = <String>[];
  if (obj is! Map) {
    throw BankFormatException(['题库根节点必须是 JSON 对象']);
  }

  var name = obj['题库名称'];
  if (name is! String || name.trim().isEmpty) {
    errors.add('缺少或非法的 题库名称');
    name = '未命名题库';
  }

  final rawList = obj['题目列表'];
  if (rawList is! List || rawList.isEmpty) {
    errors.add('缺少 题目列表，或它不是非空数组');
    throw BankFormatException(errors);
  }

  final questions = <Question>[];
  for (var i = 0; i < rawList.length; i++) {
    final raw = rawList[i];
    final tag = '第${i + 1}题';
    if (raw is! Map) {
      errors.add('$tag: 不是对象');
      continue;
    }

    var qid = raw['题号'] ?? '#${i + 1}';
    if (qid is! String) qid = qid.toString();
    var category = raw['分类'] ?? '';
    if (category is! String) category = category.toString();

    for (final k in ['题目', '副题目', '正确答案选项', '选项']) {
      if (!raw.containsKey(k)) errors.add('$tag($qid): 缺少字段 $k');
    }

    var text = raw['题目'];
    if (text is! String || text.trim().isEmpty) {
      errors.add('$tag($qid): 题目为空');
      text = text is String ? text : '';
    }
    var sub = raw['副题目'];
    if (sub == null) {
      sub = '';
    } else if (sub is! String) {
      errors.add('$tag($qid): 副题目类型非法（应为字符串，可为空）');
      sub = sub.toString();
    }

    if (_mark.hasMatch(text)) {
      errors.add('$tag($qid): 题目 含整理残留标记（✅/【X】/-> X）');
    }
    if (_mark.hasMatch(sub)) {
      errors.add('$tag($qid): 副题目 含整理残留标记（✅/【X】/-> X）');
    }

    final options = <String, String>{};
    final optsRaw = raw['选项'];
    if (optsRaw is! Map) {
      errors.add('$tag($qid): 选项 必须是对象 {"A":"..."}');
    } else {
      optsRaw.forEach((k, v) {
        if (k is! String || !_letter.hasMatch(k)) {
          errors.add('$tag($qid): 选项键 "$k" 非法（应为单个大写字母 A-Z）');
          return;
        }
        if (v is! String || v.trim().isEmpty) {
          errors.add('$tag($qid): 选项 $k 文本为空');
          return;
        }
        options[k] = v.trim();
      });
      if (options.length < 2) errors.add('$tag($qid): 选项少于 2 个');
    }
    final sortedKeys = options.keys.toList()..sort();
    final sortedOptions = <String, String>{for (final k in sortedKeys) k: options[k]!};

    final answers = _asLetters(raw['正确答案选项'], '$tag($qid)', errors);
    for (final L in answers) {
      if (!sortedOptions.containsKey(L)) {
        errors.add('$tag($qid): 正确答案 $L 不在选项 '
            '${sortedOptions.keys.join('/')} 中');
      }
    }
    if (answers.isEmpty) continue;
    if (answers.any((L) => !sortedOptions.containsKey(L))) continue;

    questions.add(Question(
      index: i + 1,
      qid: qid,
      category: category,
      text: text.trim(),
      sub: sub.trim(),
      answers: answers,
      options: sortedOptions,
    ));
  }

  if (errors.isNotEmpty) throw BankFormatException(errors);
  if (questions.isEmpty) throw BankFormatException(['题目列表里没有一道合法题目']);
  return Bank(name.trim(), questions, path: path);
}

/// 从 JSON 文本解析题库。
Bank loadBankFromString(String source, {String? path}) {
  dynamic obj;
  try {
    obj = jsonDecode(source);
  } on FormatException catch (e) {
    throw BankFormatException(['JSON 语法错误：${e.message}']);
  }
  return parseBank(obj, path: path);
}

/// 按规范格式导出（可直接再次导入）。
Map<String, dynamic> bankToJson(List<Question> questions, String name) {
  return {
    '题库名称': name,
    '题目列表': questions
        .map((q) => {
              '题号': q.qid,
              '分类': q.category,
              '题目': q.text,
              '副题目': q.sub,
              '正确答案选项': q.answers.length == 1 ? q.answers.first : q.answers,
              '选项': q.options,
            })
        .toList(),
  };
}

String bankToJsonString(List<Question> questions, String name) =>
    const JsonEncoder.withIndent(' ').convert(bankToJson(questions, name));

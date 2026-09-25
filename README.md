# QuizTrainer

通用**选择题刷题工具**。不内置任何题目，题库由使用者以 JSON 文件导入。

同一套代码同时支持 **Windows** 与 **Android**。

## 特性

- **一页一题**：题干 / 说明 / 选项 / 上一题 / 下一题 / 交卷
- **两种作答模式**（设置页联动勾选框）
  - 单击选项即提交为答案 —— 可再选「立即显示对错」与「答对后自动进入下一题」
  - 先选好、全部打完点「交卷」统一提交 —— 可再选「选择选项后自动进入下一题」
- **题库导入**：JSON 格式，严格校验，出错逐条说明且不影响当前题库
- **错题汇总**：交卷后出成绩单，可导出为同格式 JSON、可一键重刷
- **按分类筛选**：题库带 `分类` 时可只刷某一类
- **题库内搜索**：按题干 / 说明 / 题号 / 分类搜索并跳转
- **进度记忆**：下次打开自动回到上次位置，保留已选与错题
- **外观**：深色 / 浅色 / 跟随系统，6 种强调色，4 档字号
- **操作**：方向键翻页、手势滑动翻页、移动端触觉反馈
- 选项数自适应 2~15 个（A~O），长选项自动折行

## 截图

> 运行 `flutter run -d windows` 或安装 Android 包后可见实际界面。

## 快速开始

1. 打开程序 → 点 **导入题库 JSON** → 选择 .json 文件
2. 开始刷题

导入的题库保存在本机应用数据目录，下次启动自动载入；可在 **设置 → 已导入题库** 中移除。

## 题库格式

```json
{
  "题库名称": "示例题库",
  "题目列表": [
    {
      "题目": "光在真空中的传播速度约为多少？",
      "副题目": "提示：约 3×10^8 m/s",
      "正确答案选项": "A",
      "选项": {
        "A": "3×10^8 m/s",
        "B": "3×10^6 m/s",
        "C": "3×10^5 m/s",
        "D": "3×10^10 m/s"
      }
    }
  ]
}
```

- 必填：`题目` / `副题目` / `正确答案选项` / `选项`
- `副题目` 是说明栏（提示、译文、解析），不需要就写 `""`
- 可选：`题号`、`分类`（只用于显示与筛选，允许重复）
- 多选：`"正确答案选项": ["A", "C"]`
- 完整示例见 [`examples/示例题库.json`](examples/示例题库.json)

### 校验规则

导入时任一条不满足即拒绝加载，并指出错在第几题、什么原因：

1. 顶层为对象，含 `题库名称` 与 `题目列表`（非空数组）
2. 每题含 `题目` / `副题目` / `正确答案选项` / `选项`
3. `选项` 为对象，键是**单个大写字母**，至少 2 个，值非空
4. `正确答案选项` **必须存在于选项键中**
5. 题干非空
6. 题干与说明不含 `✅`、`【B】`、`-> C` 之类整理残留标记

## 构建

环境：Flutter 3.29+（Dart 3.7+）。

```bash
cd flutter_app
flutter pub get

# 运行
flutter run -d windows

# 测试
flutter test

# 打包
flutter build windows --release   # -> build/windows/x64/runner/Release/
flutter build apk --release       # -> build/app/outputs/flutter-apk/app-release.apk
```

### 打成 Windows 单文件 exe

Flutter 的 Windows 产物是文件夹。`packaging/` 提供自解压封装：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build_single_exe.ps1
# -> output/QuizTrainer_单文件版.exe
```

启动时把载荷解压到 `%TEMP%\QuizTrainer_<PID>`，**程序退出后自动删除**，不留残留。

### Android 构建注意

- 需要 Android SDK 与**标准 OpenJDK 17/21**。部分 GraalVM 发行版的 `jlink.exe`
  会递归调用自身，导致构建在 `JdkImageTransform` 阶段失败，可显式指定：
  ```bash
  flutter config --jdk-dir="/path/to/openjdk-21"
  ```
- 若插件声明的 NDK 版本本机未安装、而应用本身无原生代码，
  可在 `android/app/build.gradle.kts` 里显式写成本机已装版本。
- 未配置签名时 Flutter 会用 debug 签名打 release 包，可自行安装但不适合上架。

## 目录结构

```
flutter_app/          Flutter 应用
  lib/
    main.dart         应用入口、刷题页、设置页
    models.dart       题库模型与 JSON 校验
    store.dart        配置、题库存储、进度
    theme.dart        调色板与强调色预设
    widgets.dart      可复用组件
  test/               39 个测试（解析/校验/配置/进度/主题 + UI 交互）
packaging/            Windows 单文件封装（C# 启动器 + 打包器 + 构建脚本）
tools/                开发工具（开源前隐私自检）
examples/             示例题库
Document/             详细文档
```

## 许可

[MIT](LICENSE)


# QuizTrainer 开发文档

面向二次开发的说明。使用者文档见项目根目录 `README.md`。

## 架构

```
flutter_app/lib/
  main.dart      应用入口、刷题页、设置页、搜索与错题面板
  models.dart    Question / Bank 模型 + JSON 解析与校验
  store.dart     Cfg（运行期配置）、BankStore（题库落盘）、ProgressStore（进度）
  theme.dart     T 调色板 + Accent 预设
  widgets.dart   OptionTile / Chip2 / NoteBlock / 按钮 / 空状态等
```

### 关于主题的实现

`theme.dart` 里的 `T` 是**全局可变调色板**（静态字段 + 计算属性），
而不是 `ThemeExtension`。切换主题时在根部 `setState`，整棵树重建后读到新配色。

- 优点：组件里写 `T.surface` 这种短名字即可，改动面小
- 代价：它是全局状态，**测试之间必须复位**（见 `test/app_test.dart` 的 `tearDown`）

若想改成 `ThemeExtension`，需把各组件里的 `T.xxx` 换成
`Theme.of(context).extension<Palette>()!.xxx`，属纯机械改动。

### 数据流

```
用户导入 JSON
   → models.loadBankFromString()  严格校验，失败抛 BankFormatException
   → BankStore.save()             写入应用数据目录 banks/
   → 下次启动 BankStore.loadAll() 自动载入
   → 作答 → ProgressStore.save()  按题库名保存 {idx, picks, wrong}
```

- 题目内部键是 `Question.key`（= `q<index>`），**不是题号**。
  题号允许重复（不同来源的题库都可能有 Q1），用题号当字典键会互相覆盖。
- 筛选用 `_all`（全部）与 `_qs`（可见）两个列表，`picks`/`wrong` 以 key 索引，
  所以切换筛选不会丢作答状态。

## 测试

```bash
cd flutter_app
flutter test
```

当前 39 个测试：

| 文件 | 覆盖 |
|---|---|
| `test/widget_test.dart` | 题库解析、6 条校验规则、导出往返、Cfg 往返、ProgressStore、主题解析 |
| `test/app_test.dart` | UI 交互：作答、对错反馈、答对自动翻页、交卷、按钮/方向键/滑动翻页、分类筛选、搜索、设置页联动、字号、主题切换、错题本 |

写 UI 测试的注意点：

- 应用初始化含真实异步（SharedPreferences、文件读取），必须用
  `tester.runAsync()` 放行，否则 `pumpAndSettle` 会因加载指示器持续动画而超时。
- 测试通过 `QuizTrainerApp(testBanks: ..., testCfg: ...)` 注入，
  不依赖本机已导入的题库与配置。

## 打包

### Windows

```bash
flutter build windows --release
```

产物是**文件夹**（`quiz_trainer.exe` + `flutter_windows.dll` + `data/`）。
要单文件分发，用 `packaging/`：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build_single_exe.ps1
```

流程：PowerShell 调 `csc` 编译 `launcher.cs`（窗口程序）与 `packer.cs`（打包器）→
把 Release 文件夹压成 Deflate 载荷 → 合成
`[启动器][载荷][Int64 长度]["QDRILLPK"]`。

启动器运行时把载荷解压到 `%TEMP%\QuizTrainer_<PID>`，**等待子进程退出后删除**；
崩溃残留的目录会在下次启动时按「超过 1 小时」清理。

### Android

```bash
flutter build apk --release
```

## 踩过的坑

- **`main.cpp` 编码**：文件是 UTF-8，MSVC 默认按本地代码页解析字符串字面量，
  中文会变乱码。解决：标题用 `\u` 转义，并给文件加 UTF-8 BOM（否则中文注释触发
  C4819，而 Flutter 把警告当错误）。
- **JDK**：Android 构建需要标准 OpenJDK。部分 GraalVM 发行版的 `jlink.exe`
  会递归调用自身，导致 `JdkImageTransform` 失败。
- **NDK**：插件声明的版本本机没装、而应用无原生代码时，可在
  `android/app/build.gradle.kts` 显式写成本机已装版本。
- **构建缓存里的绝对路径**：项目文件夹改名后，`build/`、`.dart_tool/`、
  `android/.gradle/`、`android/app/.cxx/`、`windows/flutter/ephemeral/`
  里仍是旧路径，必须删掉重建，否则 CMake 报
  "CMakeCache.txt directory ... is different"。
- **进程名**：Flutter Windows 产物的进程名是 exe 名（`quiz_trainer`），
  而单文件封装的启动器进程名是 `QuizTrainer`，写清理脚本时两个都要匹配。

### CI（GitHub Actions）上踩的坑

- **Visual Studio 版本**：Flutter 3.29 的 `visual_studio.dart` 里生成器映射是

  ```dart
  return switch (_majorVersion) {
    17 => 'Visual Studio 17 2022',
    _  => 'Visual Studio 16 2019',   // 其它版本一律退回 2019
  };
  ```

  而 GitHub 的 `windows-latest` 已经升到 **VS 2026（v18）**，于是落进 `_` 分支，
  CMake 报 `could not find any instance of Visual Studio`。
  **解决**：Windows 任务固定用 `runs-on: windows-2022`（VS 2022 = v17）。
  等 Flutter 支持 v18 后可改回 `windows-latest`。

- **内联脚本里的中文**：`shell: powershell`（Windows PowerShell 5.1）会把内联脚本
  按本地代码页解析，脚本里写中文文件名会找不到文件。
  **解决**：用 `shell: pwsh`（默认 UTF-8），或改用通配符避开中文字面量。
  仓库里单独的 `.ps1` 文件带 UTF-8 BOM，所以文件形式不受影响。

## 开源检查

`tools/scan_privacy.ps1` 可扫描「会被提交的源码」是否含个人信息、绝对路径、
旧项目名。构建产物与 `_cache/` 已在 `.gitignore` 中排除。

## 持续集成

`.github/workflows/build.yml` 在 push 到 `main` 时：

1. **Windows 任务**：`flutter analyze` → `flutter test` → 构建 → 打成单文件 exe
2. **Android 任务**：构建 release APK
3. **发布任务**：两个都成功后，读取 `VERSION` 作为标签，
   创建/更新对应的 Release（预发布），附上 exe 与 apk

标签取自 `VERSION` 文件（当前 `1.0.0-beta` → 标签 `v1.0.0-beta`）。
发正式版时把 `VERSION` 里的 `-beta` 去掉即可。



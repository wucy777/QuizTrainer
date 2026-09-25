// 可复用组件。
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// 顶栏图标按钮（带 hover 反馈）
class IconAction extends StatefulWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool active;
  const IconAction({
    super.key,
    required this.icon,
    required this.tip,
    required this.onTap,
    this.active = false,
  });

  @override
  State<IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.active
        ? T.accent
        : (_hover ? T.text : T.muted);
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (_hover || widget.active)
                  ? T.surfaceHi
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 19, color: c),
          ),
        ),
      ),
    );
  }
}

/// 题库选择器
class BankPicker extends StatelessWidget {
  final List<Bank> banks;
  final int bankIdx;
  final void Function(int) onSelectBank;
  const BankPicker(this.banks, this.bankIdx, this.onSelectBank, {super.key});

  static String label(Bank b) =>
      b.name.contains('题') ? b.name : '${b.name}（${b.questions.length} 题）';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '切换题库',
      color: T.surfaceHi,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: PopupMenuPosition.under,
      onSelected: onSelectBank,
      itemBuilder: (c) => [
        for (var i = 0; i < banks.length; i++)
          PopupMenuItem(
            value: i,
            height: 42,
            child: Row(
              children: [
                Icon(
                  i == bankIdx
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: i == bankIdx ? T.accent : T.dim,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label(banks[i]),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: T.fs(13.5), color: T.text),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: T.surfaceHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label(banks[bankIdx]),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: T.fs(12.5), color: T.muted),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 16, color: T.dim),
          ],
        ),
      ),
    );
  }
}

/// 细进度条
class ProgressStrip extends StatelessWidget {
  final int current;
  final int total;
  const ProgressStrip({super.key, required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final p = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    return Container(
      color: T.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: p),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (c, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 4,
            backgroundColor: T.border,
            valueColor: AlwaysStoppedAnimation(T.accent),
          ),
        ),
      ),
    );
  }
}

/// 小标签
class Chip2 extends StatelessWidget {
  final String text;
  final bool muted;
  final Color? tone;
  const Chip2(this.text, {super.key, this.muted = false, this.tone});

  @override
  Widget build(BuildContext context) {
    final c = tone ?? (muted ? T.muted : T.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: T.fs(11.5), color: c, fontWeight: FontWeight.w500)),
    );
  }
}

/// 说明块（左侧强调条）
class NoteBlock extends StatelessWidget {
  final String text;
  const NoteBlock({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: T.accent, width: 3)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: T.fs(14.5), height: 1.55, color: T.muted)),
    );
  }
}

/// 选项卡片
class OptionTile extends StatefulWidget {
  final String letter;
  final String text;
  final String state; // idle/chosen/correct/wrong/reveal/dim
  final VoidCallback onTap;
  const OptionTile({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    Color bg, bd, fg, badgeBg, badgeFg;
    switch (s) {
      case 'chosen':
        bg = T.accent.withValues(alpha: 0.16);
        bd = T.accent;
        fg = T.text;
        badgeBg = T.accent;
        badgeFg = Colors.white;
        break;
      case 'correct':
        bg = T.green.withValues(alpha: 0.14);
        bd = T.green;
        fg = T.text;
        badgeBg = T.green;
        badgeFg = T.isDark ? const Color(0xFF06281C) : Colors.white;
        break;
      case 'wrong':
        bg = T.red.withValues(alpha: 0.14);
        bd = T.red;
        fg = T.text;
        badgeBg = T.red;
        badgeFg = Colors.white;
        break;
      case 'reveal':
        bg = T.amber.withValues(alpha: 0.13);
        bd = T.amber;
        fg = T.text;
        badgeBg = T.amber;
        badgeFg = T.isDark ? const Color(0xFF2A1D00) : Colors.white;
        break;
      case 'dim':
        bg = Colors.transparent;
        bd = T.border.withValues(alpha: 0.6);
        fg = T.dim;
        badgeBg = T.surfaceHi;
        badgeFg = T.dim;
        break;
      default:
        bg = _hover ? T.surfaceHi : T.surface;
        bd = _hover ? T.accent.withValues(alpha: 0.55) : T.border;
        fg = T.text;
        badgeBg = T.surfaceHi;
        badgeFg = T.muted;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.985 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(T.radius),
              border: Border.all(color: bd, width: 1.4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.letter,
                      style: TextStyle(
                          fontSize: T.fs(13),
                          fontWeight: FontWeight.w700,
                          color: badgeFg)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(widget.text,
                        style: TextStyle(
                            fontSize: T.fs(15.5), height: 1.5, color: fg)),
                  ),
                ),
                if (s == 'correct')
                  Icon(Icons.check_circle_rounded, size: 19, color: T.green)
                else if (s == 'wrong')
                  Icon(Icons.cancel_rounded, size: 19, color: T.red)
                else if (s == 'reveal')
                  Icon(Icons.lightbulb_rounded, size: 18, color: T.amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 判定结果条
class ResultBanner extends StatelessWidget {
  final bool correct;
  final String answerText;
  final bool showDetail;
  const ResultBanner({
    super.key,
    required this.correct,
    required this.answerText,
    required this.showDetail,
  });

  @override
  Widget build(BuildContext context) {
    if (!showDetail) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: T.border),
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_off_outlined, size: 18, color: T.muted),
            const SizedBox(width: 10),
            Text('已记录（配置为不显示对错）',
                style: TextStyle(fontSize: T.fs(14), color: T.muted)),
          ],
        ),
      );
    }
    final c = correct ? T.green : T.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(T.radius),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 20, color: c),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              correct ? '答对了' : '答错了　正确答案：$answerText',
              style: TextStyle(
                  fontSize: T.fs(14.5),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// 次要按钮
class GhostButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool trailingIcon;
  final VoidCallback? onTap;
  const GhostButton({
    super.key,
    required this.icon,
    required this.label,
    this.trailingIcon = false,
    required this.onTap,
  });

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    final fg = on ? (_hover ? T.text : T.muted) : T.dim.withValues(alpha: 0.5);
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _hover && on ? T.surfaceHi : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: on ? T.border : T.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.trailingIcon) ...[
                Icon(widget.icon, size: 17, color: fg),
                const SizedBox(width: 7),
              ],
              Text(widget.label,
                  style: TextStyle(
                      fontSize: T.fs(13.5),
                      fontWeight: FontWeight.w500,
                      color: fg)),
              if (widget.trailingIcon) ...[
                const SizedBox(width: 7),
                Icon(widget.icon, size: 17, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 主按钮（渐变 + 光晕）
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool big;
  final VoidCallback onTap;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.big = false,
    required this.onTap,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              horizontal: widget.big ? 26 : 20, vertical: widget.big ? 15 : 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hover
                  ? [
                      Color.lerp(T.accent, Colors.white, 0.18)!,
                      Color.lerp(T.accent2, Colors.white, 0.18)!,
                    ]
                  : [T.accent, T.accent2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: T.accent.withValues(alpha: _hover ? 0.42 : 0.26),
                blurRadius: _hover ? 18 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    size: widget.big ? 19 : 17, color: Colors.white),
                const SizedBox(width: 9),
              ],
              Text(widget.label,
                  style: TextStyle(
                      fontSize: T.fs(widget.big ? 15 : 13.5),
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态
class EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const EmptyState({super.key, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      T.accent.withValues(alpha: 0.20),
                      T.accent2.withValues(alpha: 0.14),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: T.border),
                ),
                child: Icon(Icons.library_books_outlined,
                    size: 36, color: T.accent),
              ),
              const SizedBox(height: 24),
              Text('还没有题库',
                  style: TextStyle(
                      fontSize: T.fs(21),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: T.text)),
              const SizedBox(height: 12),
              Text(
                '本程序只做刷题工具，不内置题目。\n'
                '请导入 JSON 题库文件（一个文件 = 一个题库）。\n'
                '导入后会保存在本机，下次启动自动载入。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: T.fs(13.5), height: 1.8, color: T.muted),
              ),
              const SizedBox(height: 26),
              PrimaryButton(
                label: '导入题库 JSON',
                icon: Icons.file_open_outlined,
                big: true,
                onTap: onImport,
              ),
              const SizedBox(height: 22),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: T.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: T.border),
                ),
                child: Text(
                  'JSON 每题需要：题目 / 副题目 / 正确答案选项 / 选项',
                  style: TextStyle(fontSize: T.fs(11.5), color: T.dim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

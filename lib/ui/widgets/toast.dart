import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/models.dart';
import '../../theme.dart';

/// 提示氣泡。論壇整體是 RPG 風格，所以做成一張有邊框與微光的卡，
/// 而不是 Material 預設那條方方的 SnackBar。
void toast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  if (!context.mounted) return;
  _show(context, _ToastCard(message: message, kind: kind));
}

/// 發文／回覆之後的積分結果。規則名與每一項變化各自成塊，比擠成一行好讀
void toastCredits(
  BuildContext context, {
  required String message,
  String rule = '',
  List<CreditChange> credits = const [],
}) {
  if (!context.mounted) return;
  if (credits.isEmpty && rule.isEmpty) return toast(context, message, kind: ToastKind.ok);
  _show(context, _CreditCard(message: message, rule: rule, credits: credits));
}

enum ToastKind { info, ok, warn }

OverlayEntry? _current;
Timer? _timer;

void _show(BuildContext context, Widget child) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  _dismiss();
  final entry = OverlayEntry(
    builder: (c) => Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(c).padding.bottom + 28,
      child: IgnorePointer(child: _Fade(child: child)),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 2600), _dismiss);
}

void _dismiss() {
  _timer?.cancel();
  _timer = null;
  _current?.remove();
  _current = null;
}

/// 淡入 + 稍微往上浮，收掉「啪」一下冒出來的生硬感
class _Fade extends StatefulWidget {
  const _Fade({required this.child});
  final Widget child;

  @override
  State<_Fade> createState() => _FadeState();
}

class _FadeState extends State<_Fade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .25), end: Offset.zero)
            .animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// 共用的外框：深底、主色描邊、一點外光
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.accent});
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = accent ?? scheme.primary;
    final dark = scheme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        decoration: BoxDecoration(
          color: dark ? const Color(0xF21B1E25) : const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line.withValues(alpha: .55), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: line.withValues(alpha: dark ? .28 : .18),
              blurRadius: 18,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .45 : .12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message, required this.kind});
  final String message;
  final ToastKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, accent) = switch (kind) {
      ToastKind.ok => (LucideIcons.circleCheck, const Color(0xFF4CAF50)),
      ToastKind.warn => (LucideIcons.circleAlert, scheme.error),
      ToastKind.info => (LucideIcons.info, scheme.primary),
    };

    return _Frame(
      accent: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: 11),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 14, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.message,
    required this.rule,
    required this.credits,
  });

  final String message;
  final String rule;
  final List<CreditChange> credits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _Frame(
      accent: const Color(0xFFF6B93B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.sparkles,
                  size: 18, color: Color(0xFFF6B93B)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(message,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (rule.isNotEmpty)
                Text(rule,
                    style: TextStyle(fontSize: 11.5, color: faint(context))),
            ],
          ),
          if (credits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final c in credits)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: .35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.name,
                            style: TextStyle(
                                fontSize: 12, color: subtle(context))),
                        const SizedBox(width: 5),
                        Text(
                          '${c.delta > 0 ? '+' : ''}${c.delta}${c.unit}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.delta > 0
                                ? const Color(0xFF4CAF50)
                                : scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

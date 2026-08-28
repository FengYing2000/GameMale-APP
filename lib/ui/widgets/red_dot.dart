import 'package:flutter/material.dart';

/// 在圖示右上角疊一顆小紅點（有新提醒／新訊息時）。
class RedDot extends StatelessWidget {
  const RedDot({super.key, required this.show, required this.child});
  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFFFF1744),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 1.5),
              // 霓虹光：紅色外暈，深色模式下特別明顯
              boxShadow: const [
                BoxShadow(
                    color: Color(0xFFFF1744), blurRadius: 6, spreadRadius: 1),
                BoxShadow(
                    color: Color(0x88FF5252), blurRadius: 12, spreadRadius: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

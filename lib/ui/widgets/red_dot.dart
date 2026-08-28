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
          right: -1,
          top: -1,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Theme.of(context).colorScheme.surface, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

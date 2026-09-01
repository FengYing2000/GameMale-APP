import 'package:flutter/material.dart';

/// 在圖示右上角疊未讀提示。
///
/// 有數字就顯示數字（「有 5 封」跟「有東西」差很多），
/// 只知道「有」但不知道幾筆時退回一顆小圓點。
class RedDot extends StatelessWidget {
  const RedDot({super.key, required this.child, this.count = 0, this.show});

  final Widget child;

  /// 未讀數。0 = 不顯示。
  final int count;

  /// 沒有數字可用時的開關。給不知道筆數、只知道有沒有的地方用。
  final bool? show;

  static const _red = Color(0xFFFF1744);

  @override
  Widget build(BuildContext context) {
    final visible = show ?? count > 0;
    if (!visible) return child;

    final surface = Theme.of(context).colorScheme.surface;
    // 霓虹光：紅色外暈，深色模式下特別明顯
    const glow = [
      BoxShadow(color: _red, blurRadius: 6, spreadRadius: 1),
      BoxShadow(color: Color(0x88FF5252), blurRadius: 12, spreadRadius: 2),
    ];

    final Widget marker;
    if (count > 0) {
      // 三位數以上就收成 99+，不然會把圖示整個蓋掉
      final text = count > 99 ? '99+' : '$count';
      marker = Container(
        constraints: const BoxConstraints(minWidth: 17),
        height: 17,
        padding: EdgeInsets.symmetric(horizontal: text.length > 1 ? 4.5 : 0),
        decoration: BoxDecoration(
          color: _red,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: surface, width: 1.5),
          boxShadow: glow,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      marker = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _red,
          shape: BoxShape.circle,
          border: Border.all(color: surface, width: 1.5),
          boxShadow: glow,
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(right: count > 0 ? -9 : -2, top: -6, child: marker),
      ],
    );
  }
}

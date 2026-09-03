import 'package:flutter/material.dart';

/// 未讀提示：霓虹紅點，有數字就顯示數字。
///
/// **圖示留在原位**：角標用 `Positioned` 疊在右上角，外層的 `Stack` 不佔
/// 額外寬度，所以圖示不會被推歪。早期版本為了避免被裁切而把整組放進一個
/// 加寬的方框，結果圖示整個偏掉。
///
/// **不畫外框**：描邊跟霓虹光是互斥的兩種語言，加了外框反而讓光暈變髒。
/// 要跟背景分離就靠光暈本身。
class RedDot extends StatelessWidget {
  const RedDot({super.key, required this.child, this.count = 0, this.show});

  final Widget child;

  /// 未讀數。0 = 不顯示。
  final int count;

  /// 沒有數字可用時的開關，給只知道「有沒有」的地方用。
  final bool? show;

  static const _red = Color(0xFFFF1744);

  @override
  Widget build(BuildContext context) {
    final visible = show ?? count > 0;
    if (!visible) return child;

    final label = count > 0 ? (count > 99 ? '99+' : '$count') : null;

    // 霓虹外暈。深色底下特別明顯，也是這顆點跟一般紅點的差別。
    const glow = [
      BoxShadow(color: _red, blurRadius: 8, spreadRadius: 1),
      BoxShadow(color: Color(0x99FF5252), blurRadius: 16, spreadRadius: 2),
    ];

    final Widget marker = label == null
        ? Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: _red,
              shape: BoxShape.circle,
              boxShadow: glow,
            ),
          )
        : Container(
            constraints: const BoxConstraints(minWidth: 16),
            height: 16,
            padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 4 : 0),
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(8),
              boxShadow: glow,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

    // clipBehavior: none 讓角標可以凸出去；Stack 本身只佔 child 的大小，
    // 所以圖示位置完全不變。
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          top: -5,
          right: label == null ? -3 : -9,
          child: marker,
        ),
      ],
    );
  }
}

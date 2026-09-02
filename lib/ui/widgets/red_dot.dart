import 'package:flutter/material.dart';

/// 未讀提示：霓虹紅點，有數字就顯示數字。
///
/// **為什麼不用 Material 的 `Badge`**：那個沒有外暈，看起來就是一顆普通的
/// 紅色圓點，跟這個 App 的調性不合。
///
/// **為什麼不用 Stack + 負的 Positioned**：`NavigationBar` 與 `IconButton`
/// 都會把圖示裁進固定大小的容器，凸出去的部分會被切掉，數字根本看不到。
/// 這裡改成把圖示連同角標一起畫在一個**稍微放大的方框內**，角標完全落在
/// 邊界裡面，不管外層怎麼裁都不會被切。
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
      BoxShadow(color: _red, blurRadius: 7, spreadRadius: 1),
      BoxShadow(color: Color(0x99FF5252), blurRadius: 14, spreadRadius: 2),
    ];
    final ring = Theme.of(context).colorScheme.surface;

    final Widget marker = label == null
        ? Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _red,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 1.5),
              boxShadow: glow,
            ),
          )
        : Container(
            constraints: const BoxConstraints(minWidth: 17),
            height: 17,
            padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 4.5 : 0),
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: ring, width: 1.5),
              boxShadow: glow,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

    // 整組畫在同一個稍大的方框裡（外層再怎麼裁都切不到），
    // **圖示置中**、角標貼右上角。左右各留一樣的空間，圖示才不會偏。
    final over = label == null ? 6.0 : 18.0;
    return SizedBox(
      width: 24 + over * 2,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(width: 24, height: 24, child: Center(child: child)),
          Positioned(top: 0, right: 0, child: marker),
        ],
      ),
    );
  }
}

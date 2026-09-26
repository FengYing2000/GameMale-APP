import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 輸入框的「點到外面就放開」，網頁版要分清楚是**點**還是**滑**。
///
/// 網頁版在 iPhone 上，瀏覽器只要一「點」到輸入框以外（包括按鈕），
/// 就會自己把鍵盤收掉——這一點 App 擋不了。Flutter 預設在手指一按下就放開
/// 輸入框，所以連滑動看訊息都會收鍵盤；可是整個不放開更糟：鍵盤被瀏覽器收了，
/// App 卻還以為在輸入中，再點輸入框時 Safari 對到舊位置，整個畫面跳掉
/// （私訊點 BBCode 之後變全螢幕就是這樣）。
///
/// 所以：手指放開時移動不到一個滑動門檻＝點 → 放開輸入框、跟瀏覽器同步；
/// 有滑動＝在捲 → 鍵盤留著。原生版回傳 null 用預設（原生本來就不會因為碰外面收鍵盤）。
TapRegionCallback? keyboardTapOutside(FocusNode focus) =>
    kIsWeb ? tapToUnfocus(focus) : null;

/// 手指放開時沒滑動（小於滑動門檻）才放開輸入框
@visibleForTesting
TapRegionCallback tapToUnfocus(FocusNode focus) {
  return (PointerDownEvent down) {
    void route(PointerEvent e) {
      if (e.pointer != down.pointer) return;
      if (e is PointerUpEvent) {
        if ((e.position - down.position).distance < kTouchSlop) focus.unfocus();
        GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
      } else if (e is PointerCancelEvent) {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
      }
    }

    GestureBinding.instance.pointerRouter.addGlobalRoute(route);
  };
}

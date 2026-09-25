// 把 App 圖示拆成啟動動畫用的三個透明圖層：十字鍵、紅色按鈕、字樣。
//
//   C:/src/flutter/bin/dart.bat run tool/make_splash.dart
//
// 圖示是黑底上的灰色十字鍵＋紅色按鈕＋「GameMale」字樣。要讓各部分分開動，
// 得去掉黑底變成透明：每個像素依「比黑多亮多少」算出透明度，再把顏色還原回
// 疊在黑底之前的樣子（反預乘），邊緣的抗鋸齒才不會變成一圈黑邊。
// 換圖示後重跑這支，並依印出的比例調整 lib/ui/widgets/launch_splash.dart。
//
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/icon.png').readAsBytesSync())!;
  final w = src.width, h = src.height;
  // 圖示的圓角黑底外圍有一圈細灰邊，每一列左右兩端都有它——不排除的話
  // 分不出圖形與字樣之間的空隙，灰邊也會被當成十字鍵的一部分
  // 圓角的地方灰邊是斜的，用矩形排除不掉，要照圓角方形的形狀算
  final m = (w * 0.05).round();
  final radius = w * 0.2;
  bool inside(int x, int y) {
    final qx = (x - w / 2).abs() - (w / 2 - radius);
    final qy = (y - h / 2).abs() - (h / 2 - radius);
    final d = sqrt(pow(max(qx, 0), 2) + pow(max(qy, 0), 2)) + min(max(qx, qy), 0) - radius;
    return d < -m;
  }

  // 紅＝R 明顯大於 G、B；其餘有亮度的都算灰
  bool isRed(img.Pixel p) => p.r - max(p.g, p.b) > 12;
  num bright(img.Pixel p) => max(p.r, max(p.g, p.b));

  // 找字樣與圖形的分界：從下往上掃，最下面一段有內容的橫帶就是字樣
  final rowHas = List.generate(h, (y) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      if (inside(x, y) && p.a > 200 && bright(p) > 40) return true;
    }
    return false;
  });
  // 從中間往下找第一段空白列＝圖形與字樣之間的間隙
  var gapStart = h ~/ 2;
  while (gapStart < h && rowHas[gapStart]) {
    gapStart++;
  }
  var wordTop = gapStart;
  while (wordTop < h && !rowHas[wordTop]) {
    wordTop++;
  }

  img.Image layer(bool Function(int x, int y, img.Pixel p) take, {required bool red}) {
    final out = img.Image(width: w, height: h, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        if (p.a < 250 || !inside(x, y) || !take(x, y, p)) continue;
        // 黑底不是純 0，帶著 1～幾的雜訊：低於門檻一律當背景。
        // 灰的本色約 76、紅的 R 約 244：亮到這個程度就算不透明
        const floor = 10;
        final a = ((bright(p) - floor) / ((red ? 200 : 64) - floor)).clamp(0.0, 1.0);
        if (a < 0.03) continue;
        int un(num c) => (c / a).round().clamp(0, 255);
        out.setPixelRgba(x, y, un(p.r), un(p.g), un(p.b), (a * 255).round());
      }
    }
    return out;
  }

  final cross = layer((x, y, p) => y < gapStart && !isRed(p), red: false);
  final dot = layer((x, y, p) => y < gapStart && isRed(p), red: true);
  final word = layer((x, y, p) => y >= wordTop, red: false);
  // 字樣的紅字（Male）要用紅的門檻，重算一次蓋上去
  final wordRed = layer((x, y, p) => y >= wordTop && isRed(p), red: true);
  img.compositeImage(word, wordRed);

  // 十字鍵與按鈕共用一個以按鈕中心為中心的正方形框：旋轉、縮放都繞著它
  final dotBox = _bounds(dot);
  final cx = (dotBox.left + dotBox.right) / 2, cy = (dotBox.top + dotBox.bottom) / 2;
  final crossBox = _bounds(cross);
  final half = [
    cx - crossBox.left, crossBox.right - cx, cy - crossBox.top, crossBox.bottom - cy,
  ].reduce(max).ceil() + 8;
  img.Image square(img.Image im) => img.copyCrop(im,
      x: (cx - half).round(), y: (cy - half).round(), width: half * 2, height: half * 2);

  final wordBox = _bounds(word);
  final wordCrop = img.copyCrop(word,
      x: wordBox.left - 6, y: wordBox.top - 6,
      width: wordBox.right - wordBox.left + 12, height: wordBox.bottom - wordBox.top + 12);

  Directory('assets/splash').createSync(recursive: true);
  File('assets/splash/cross.png').writeAsBytesSync(img.encodePng(square(cross)));
  File('assets/splash/dot.png').writeAsBytesSync(img.encodePng(square(dot)));
  File('assets/splash/word.png').writeAsBytesSync(img.encodePng(wordCrop));

  final side = half * 2;
  print('圖形框 ${side}px（中心＝按鈕中心），按鈕直徑 ${dotBox.right - dotBox.left}px');
  print('字樣 ${wordCrop.width}×${wordCrop.height}px');
  print('比例：按鈕直徑/圖形框 ${((dotBox.right - dotBox.left) / side).toStringAsFixed(3)}，'
      '字樣寬/圖形框 ${(wordCrop.width / side).toStringAsFixed(3)}，'
      '圖形框底到字樣頂 ${((wordBox.top - 6 - (cy + half)) / side).toStringAsFixed(3)}');
}

({int left, int top, int right, int bottom}) _bounds(img.Image im) {
  var l = im.width, t = im.height, r = 0, b = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a > 20) {
        l = min(l, x);
        r = max(r, x + 1);
        t = min(t, y);
        b = max(b, y + 1);
      }
    }
  }
  return (left: l, top: t, right: r, bottom: b);
}

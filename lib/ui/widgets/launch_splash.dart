import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 啟動動畫：十字鍵轉進定位 → 紅色按鈕「按下」彈出並擴散一圈波紋 →
/// 字樣淡入並掃過一道光 → 淡出進入 App。
///
/// 圖層來自 assets/icon.png（tool/make_splash.dart 拆的），比例照圖示原樣。
/// 系統啟動畫面（iOS LaunchScreen／Android launch_background／網頁 #boot）
/// 都是同一個純底色、沒有圖，動畫從空白長出來，接起來才不會閃。
///
/// * 動畫至少跑完一輪（約 1.1 秒）才離場；[ready] 之前會一直等著，
///   按鈕改成慢慢呼吸發光，等久了再顯示 [waitingLabel]。
/// * 系統開了「減少動態效果」就直接顯示成品、不轉不彈。
class LaunchSplash extends StatefulWidget {
  const LaunchSplash({
    super.key,
    required this.ready,
    required this.onDone,
    this.waitingLabel = '',
  });

  /// 底下的畫面準備好了（開機流程走完、知道要顯示哪一頁）
  final bool ready;

  /// 淡出結束，可以把這層拿掉了
  final VoidCallback onDone;
  final String waitingLabel;

  /// 跟 App 深色主題、網頁版載入畫面、原生啟動畫面同一個顏色
  static const background = Color(0xFF0F1115);

  static const _cross = AssetImage('assets/splash/cross.png');
  static const _dot = AssetImage('assets/splash/dot.png');
  static const _word = AssetImage('assets/splash/word.png');

  // tool/make_splash.dart 印出的比例（以十字鍵的正方形框為 1）
  static const _dotRatio = 0.261;
  static const _wordRatio = 1.690;
  static const _gapRatio = 0.099;
  static const _wordAspect = 926 / 165;

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))
    ..addStatusListener(_onIntro);
  late final _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool _prepared = false;
  bool _leaving = false;
  bool _showHint = false;
  Timer? _hintTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prepared) return;
    _prepared = true;
    _prepare();
  }

  Future<void> _prepare() async {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // 圖還沒解碼就開始動，第一幀會缺一塊。最多等 0.6 秒，等不到就照樣開始
    try {
      await Future.wait([
        precacheImage(LaunchSplash._cross, context),
        precacheImage(LaunchSplash._dot, context),
        precacheImage(LaunchSplash._word, context),
      ]).timeout(const Duration(milliseconds: 600));
    } catch (_) {}
    if (!mounted) return;
    if (still) {
      _intro.value = 1;
      _onIntro(AnimationStatus.completed);
    } else {
      _intro.forward();
    }
    _hintTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !widget.ready) setState(() => _showHint = true);
    });
  }

  void _onIntro(AnimationStatus s) {
    if (s != AnimationStatus.completed) return;
    if (!widget.ready && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _pulse.repeat(reverse: true);
    }
    _maybeLeave();
  }

  @override
  void didUpdateWidget(LaunchSplash old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _maybeLeave();
  }

  void _maybeLeave() {
    if (_leaving || !widget.ready || !_intro.isCompleted) return;
    _leaving = true;
    _hintTimer?.cancel();
    _exit.forward().whenComplete(() {
      _pulse.stop();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _intro.dispose();
    _exit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// 動畫進度 t 落在 [a, b] 區間時的 0～1
  double _iv(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_intro.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _exit, _pulse]),
        builder: (context, _) {
          final leave = Curves.easeIn.transform(_exit.value);
          return Opacity(
            opacity: 1 - leave,
            child: ColoredBox(
              color: LaunchSplash.background,
              child: LayoutBuilder(builder: (context, box) => _stage(box, leave)),
            ),
          );
        },
      ),
    );
  }

  Widget _stage(BoxConstraints box, double leave) {
    // 十字鍵的框：短邊的 42%，但字樣（1.69 倍寬）要塞得進螢幕寬的 78%
    final c = math.min(
      190.0,
      math.min(box.biggest.shortestSide * 0.42, box.maxWidth * 0.78 / LaunchSplash._wordRatio),
    );
    final dotD = c * LaunchSplash._dotRatio;
    final wordW = c * LaunchSplash._wordRatio;

    // ── 十字鍵：縮小＋逆轉 90° 起跳，回彈到定位
    final crossIn = _iv(0, .5, Curves.easeOutBack);
    final crossOpacity = _iv(0, .3);
    final crossTurn = lerpDouble(-.25, 0, _iv(0, .55, Curves.easeOutCubic))!;

    // ── 紅色按鈕：從無彈出、超過一點再落回（像被按下又彈起）
    final pop = _iv(.3, .72);
    final dotScale = pop < .55
        ? Curves.easeOut.transform(pop / .55) * 1.18
        : lerpDouble(1.18, 1, Curves.easeInOut.transform((pop - .55) / .45))!;
    final dotOpacity = _iv(.3, .38);

    // ── 按下去的波紋
    final ripple = _iv(.42, .95, Curves.easeOutCubic);

    // ── 等待中的呼吸光
    final glow = _intro.isCompleted && !_leaving ? .12 + .3 * Curves.easeInOut.transform(_pulse.value) : 0.0;

    // ── 字樣：往上浮入，再掃過一道光
    final wordIn = _iv(.5, .85, Curves.easeOutCubic);
    final shine = _iv(.72, 1);

    return Stack(
      children: [
        Center(
          child: Transform.scale(
            scale: 1 + .06 * leave,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: c,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (glow > 0)
                        _Circle(
                          size: dotD * 2.6,
                          gradient: RadialGradient(colors: [
                            const Color(0xFFF32E01).withValues(alpha: glow),
                            const Color(0x00F32E01),
                          ]),
                        ),
                      Opacity(
                        opacity: crossOpacity,
                        child: Transform.rotate(
                          angle: crossTurn * 2 * math.pi,
                          child: Transform.scale(
                            scale: lerpDouble(.55, 1, crossIn)!,
                            child: Image(image: LaunchSplash._cross, width: c, height: c, gaplessPlayback: true),
                          ),
                        ),
                      ),
                      if (ripple > 0 && ripple < 1)
                        _Circle(
                          size: dotD * (1 + 2.2 * ripple),
                          border: Border.all(
                            color: const Color(0xFFF32E01).withValues(alpha: (1 - ripple) * .55),
                            width: 2,
                          ),
                        ),
                      Opacity(
                        opacity: dotOpacity,
                        child: Transform.scale(
                          scale: dotScale,
                          child: Image(image: LaunchSplash._dot, width: c, height: c, gaplessPlayback: true),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: c * LaunchSplash._gapRatio),
                Opacity(
                  opacity: wordIn,
                  child: Transform.translate(
                    offset: Offset(0, lerpDouble(14, 0, wordIn)!),
                    child: SizedBox(
                      width: wordW,
                      height: wordW / LaunchSplash._wordAspect,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Image(image: LaunchSplash._word, gaplessPlayback: true),
                          if (shine > 0 && shine < 1)
                            ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (r) => LinearGradient(
                                begin: const Alignment(-1, -.3),
                                end: const Alignment(1, .3),
                                colors: const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
                                stops: [
                                  (shine * 1.6 - .45).clamp(0.0, 1.0),
                                  (shine * 1.6 - .3).clamp(0.0, 1.0),
                                  (shine * 1.6 - .15).clamp(0.0, 1.0),
                                ],
                              ).createShader(r),
                              child: const ColorFiltered(
                                colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                child: Image(image: LaunchSplash._word, gaplessPlayback: true),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.waitingLabel.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 56 + MediaQuery.paddingOf(context).bottom,
            child: AnimatedOpacity(
              opacity: _showHint && !widget.ready ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Text(
                widget.waitingLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF8A93A6), letterSpacing: .5),
              ),
            ),
          ),
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, this.gradient, this.border});
  final double size;
  final Gradient? gradient;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient, border: border),
        ),
      );
}

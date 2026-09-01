import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 論壇 cookie 的加密存放（AES-256-GCM）。
///
/// 跟 SignHub 同一套做法：**存的是 cookie 不是密碼**，密碼從頭到尾留在使用者
/// 手機上，伺服器只拿得到登入後的 session。
///
/// 加密擋得住的是「備份或資料檔外流」，擋不住拿到這台機器 root 的人——
/// 金鑰就在同一台的 .env 裡。這是自架服務的先天限制，別對它有超過的期待。
///
/// 使用者隨時可以在論壇按登出，那個 session 立刻失效，這裡存的東西就變廢紙。
class SecretBox {
  SecretBox(this.key) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 的金鑰要 32 bytes，收到 ${key.length}');
    }
  }

  /// 從 .env 的 base64 金鑰建立。
  ///
  /// 設定填錯要在**啟動時**就講清楚哪裡錯，不要丟一句
  /// 「Invalid length, must be multiple of four」讓人去猜。
  /// 最常見的就是複製時把結尾的 `=` 漏掉了。
  factory SecretBox.fromBase64(String b64) {
    final Uint8List raw;
    try {
      raw = Uint8List.fromList(base64.decode(b64.trim()));
    } on FormatException {
      throw ArgumentError('SECRET_KEY 不是合法的 base64'
          '（長度 ${b64.trim().length}）。最常見的原因是複製時把結尾的 = 漏掉了，'
          '請整行原封不動貼進去。');
    }
    return SecretBox(raw);
  }

  final Uint8List key;

  /// 產一把新金鑰。**換掉會讓所有已存的 cookie 解不開**，
  /// 所有人都要重新登入。
  static String generateKey() => base64.encode(
      List<int>.generate(32, (_) => math.Random.secure().nextInt(256)));

  /// 加密。輸出是 base64(nonce ‖ 密文 ‖ 標籤)。
  ///
  /// 每次都用新的隨機 nonce——GCM 同一把金鑰重複用 nonce 會直接洩漏明文，
  /// 這是不能省的。
  String seal(String plaintext) {
    final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => math.Random.secure().nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final out = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
    return base64.encode(<int>[...nonce, ...out]);
  }

  /// 解密。被動過手腳會丟 [FormatException]，不會回半調子的結果。
  String open(String sealed) {
    final Uint8List raw;
    try {
      raw = Uint8List.fromList(base64.decode(sealed));
    } on FormatException {
      throw const FormatException('密文不是合法的 base64');
    }
    // nonce 12 + 標籤 16，低於這個長度不可能是我們加密出來的
    if (raw.length < 12 + 16) {
      throw const FormatException('密文長度不足');
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), 128, raw.sublist(0, 12), Uint8List(0)));
    try {
      return utf8.decode(cipher.process(raw.sublist(12)));
    } catch (e) {
      // GCM 驗不過就是被改過或金鑰不對，兩種都不能當成正常資料用
      throw const FormatException('密文驗證失敗：金鑰不對或內容被竄改');
    }
  }
}

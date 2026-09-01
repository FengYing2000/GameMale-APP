import 'package:gm_server/vapid.dart';

/// 產一組 VAPID 金鑰。跑一次，把私鑰存進 .env 就別再動它——
/// 換金鑰會讓所有既有訂閱失效，每個使用者都要重新授權通知。
void main() {
  final keys = VapidKeys.generate();
  print('VAPID_PRIVATE_KEY=${keys.privateKeyBase64}');
  print('');
  print('公鑰（前端會自己跟伺服器要，這裡只是給你確認用）：');
  print(keys.publicKeyBase64);
}

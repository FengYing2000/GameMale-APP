import 'package:gm_server/secret_box.dart';

/// 產一把加密論壇 cookie 用的金鑰。跑一次存進 .env 就別再動——
/// 換掉會讓所有已存的 cookie 解不開，每個人都要重新登入。
void main() {
  print('SECRET_KEY=${SecretBox.generateKey()}');
}

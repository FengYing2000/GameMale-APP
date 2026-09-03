import 'package:gm_server/asset_guard.dart';
import 'package:test/test.dart';

/// `/gmimg` 從白名單改成「任何主機都代理」之後，安全就完全靠這兩道守門。
/// 這裡把它們釘死，免得哪天有人為了省事把判斷放寬，
/// 讓這台機器變成別人的開放代理或 SSRF 跳板。
void main() {
  group('內網位址一律不代理', () {
    for (final h in [
      'localhost',
      'foo.localhost',
      'db.internal',
      'nas.local',
      '127.0.0.1',
      '127.1.2.3',
      '0.0.0.0',
      '10.0.0.5',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.1',
      '169.254.169.254', // 雲端 metadata，最典型的 SSRF 目標
      '100.64.0.1', // CGNAT
      '::1',
      'fd00::1',
      'fe80::1',
      '::ffff:127.0.0.1', // 包成 IPv6 的迴環，同樣要擋
      '',
    ]) {
      test('擋 $h', () => expect(isPrivateHost(h), isTrue, reason: h));
    }
  });

  group('正常的圖床要放行', () {
    for (final h in [
      'i.imgs.ovh',
      'img.gamemale.com',
      'gcore.jsdelivr.net',
      '8.8.8.8',
      '172.32.0.1', // 172 私有段只到 31
      '192.169.0.1', // 只有 192.168 是私有
      '11.0.0.1',
    ]) {
      test('放行 $h', () => expect(isPrivateHost(h), isFalse, reason: h));
    }
  });

  group('只回圖片', () {
    test('圖片放行', () {
      expect(isImageType('image/jpeg'), isTrue);
      expect(isImageType('IMAGE/PNG'), isTrue);
      expect(isImageType('image/webp; charset=binary'), isTrue);
    });
    test('其他一律擋', () {
      // 少了這道，/gmimg 就成了萬用的內容代理
      expect(isImageType('text/html'), isFalse);
      expect(isImageType('application/json'), isFalse);
      expect(isImageType(null), isFalse);
      expect(isImageType(''), isFalse);
    });
  });
}

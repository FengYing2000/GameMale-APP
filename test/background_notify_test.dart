import 'package:flutter_test/flutter_test.dart';
import 'package:gamemale/services/background.dart';

/// 原生版的背景通知與網頁版的伺服器推播是兩套完全不同的實作，
/// 但使用者看到的應該是同一種東西。這裡把文案格式釘住。
///
/// 這些是純函式，不碰網路也不碰 workmanager。
void main() {
  group('提醒通知的標題講得出是哪一類', () {
    test('單一分類', () {
      expect(noticeTitle({'system': 2}), '[系統提醒]');
    });

    test('多個分類串起來', () {
      expect(noticeTitle({'system': 1, 'mypost': 2}), '[系統提醒、回覆我的]');
    });

    test('數字是 0 的分類不列進去', () {
      expect(noticeTitle({'system': 0, 'mypost': 3}), '[回覆我的]');
    });

    test('讀不到分類時退回泛稱', () {
      // 論壇偶爾只給 class="yes" 不給細項，這時不能吐出一個空的 []
      expect(noticeTitle(const {}), '[論壇提醒]');
      expect(noticeTitle({'system': 0}), '[論壇提醒]');
    });

    test('沒見過的分類代號不會變成空字串', () {
      expect(noticeTitle({'newkind': 1}), '[提醒]');
    });
  });

  group('私訊通知：標題是寄件者，內文是訊息', () {
    test('有寄件者也有內容', () {
      final n = pmNotification(name: '小明', preview: '在嗎', unread: 1);
      expect(n.title, '[私人消息] 小明');
      expect(n.body, '在嗎');
    });

    test('有寄件者但抓不到內容，退回則數', () {
      final n = pmNotification(name: '小明', preview: '', unread: 3);
      expect(n.title, '[私人消息] 小明');
      expect(n.body, contains('3'));
    });

    test('連寄件者都沒有就只講則數', () {
      final n = pmNotification(name: '', preview: '不該被用到', unread: 2);
      expect(n.title, '[私人消息]');
      expect(n.body, contains('2'),
          reason: '沒有寄件者時不能把內容拿出來當內文，那樣分不清是誰傳的');
    });
  });
}

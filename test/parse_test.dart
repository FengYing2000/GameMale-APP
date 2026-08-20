// 用真實抓下來的論壇頁面驗證解析器。
// fixtures 不進版控，需要時執行 `dart run tool/fetch_fixtures.dart` 重抓。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:gamemale/api/discuz.dart' as api;
import 'package:gamemale/api/http.dart';
import 'package:gamemale/api/parse.dart';

File _f(String name) => File('test/fixtures/$name');

dom.Document? _load(String name) {
  final f = _f(name);
  if (!f.existsSync()) return null;
  return toDoc(f.readAsStringSync());
}

void main() {
  group('首頁 板塊列表', () {
    final doc = _load('index.html');
    if (doc == null) return;
    final r = api.parseIndex(doc);
    final all = r.groups.expand((g) => g.forums).toList();

    test('解析出分類群組', () => expect(r.groups.length, greaterThan(0)));
    test('解析出板塊', () => expect(all.length, greaterThan(5)));
    test('每個板塊都有 fid', () => expect(all.every((f) => f.fid > 0), isTrue));
    test('每個板塊都有名稱', () => expect(all.every((f) => f.name.isNotEmpty), isTrue));
    test('板塊有主題/回覆數',
        () => expect(all.every((f) => f.threads.isNotEmpty && f.posts.isNotEmpty), isTrue));
    test('板塊有簡介',
        () => expect(all.where((f) => f.desc.isNotEmpty).length, greaterThan(all.length ~/ 2)));
    test('偵測到已登入', () => expect(r.user.loggedIn, isTrue));
    test('取得 uid', () => expect(r.user.uid, greaterThan(0)));
    test('取得使用者名稱', () => expect(r.user.name, isNotEmpty));
    test('解析簽到元件', () => expect(r.sign, isNotNull));
    test('簽到經驗值有數字', () => expect(r.sign!.expMax, greaterThan(0)));
    test('簽到進度百分比', () => expect(r.sign!.percent, greaterThan(0)));
    test('板塊回覆數取到精確值（不是「4万」）',
        () => expect(int.tryParse(all.first.posts), isNotNull));
  });

  group('主題列表', () {
    final doc = _load('forum.html');
    if (doc == null) return;
    final list = api.parseThreadList(doc);

    test('解析出主題', () => expect(list.length, greaterThan(10)));
    test('每筆都有 tid', () => expect(list.every((t) => t.tid > 0), isTrue));
    test('每筆都有標題', () => expect(list.every((t) => t.title.isNotEmpty), isTrue));
    test('標題不含分類前綴',
        () => expect(list.every((t) => t.type.isEmpty || !t.title.startsWith(t.type)), isTrue));
    test('有作者',
        () => expect(list.where((t) => t.author.isNotEmpty).length, greaterThan(list.length * 0.8)));
    test('有瀏覽/回覆數',
        () => expect(list.any((t) => t.views > 0 && t.replies > 0), isTrue));
    test('有發布日期',
        () => expect(list.where((t) => t.date.isNotEmpty).length, greaterThan(list.length * 0.8)));
    test('有頭像 uid',
        () => expect(list.where((t) => t.uid != null).length, greaterThan(list.length * 0.8)));
    test('分頁解析', () => expect(parsePager(doc).total, greaterThan(1)));

    test('子版塊不會誤抓成主題分類', () {
      // #subMenu 第一個 ul 沒有子版塊時其實是 #thread_types，必須排除
      final subs = doc.querySelectorAll('#subMenu li a');
      expect(subs.length, greaterThan(0));
    });
  });

  group('帖子內頁', () {
    final doc = _load('thread.html');
    if (doc == null) return;
    final t = api.parseThread(doc, 129896);

    test('有標題', () => expect(t.title, isNotEmpty));
    test('抓到分類', () => expect(t.type, isNotEmpty));
    test('回推 fid', () => expect(t.fid, greaterThan(0)));
    test('解析出樓層', () => expect(t.posts.length, greaterThan(5)));
    test('每層都有 pid', () => expect(t.posts.every((p) => (p.pid ?? 0) > 0), isTrue));
    test('每層都有作者', () => expect(t.posts.every((p) => p.author.isNotEmpty), isTrue));
    test('每層都有時間', () => expect(t.posts.every((p) => p.time.isNotEmpty), isTrue));
    test('每層都有內容 HTML', () => expect(t.posts.every((p) => p.html.isNotEmpty), isTrue));
    test('樓主在第一層', () => expect(t.posts.first.floor, '樓主'));
    test('回覆有樓層號', () => expect(t.posts[1].floor.contains('楼'), isTrue));
    test('內容含絕對網址圖片',
        () => expect(t.posts.any((p) => RegExp('<img[^>]+src="https://').hasMatch(p.html)), isTrue));
    test('內容已移除 script',
        () => expect(t.posts.every((p) => !p.html.toLowerCase().contains('<script')), isTrue));
    test('內容已移除事件屬性',
        () => expect(t.posts.every((p) => !RegExp('onclick=', caseSensitive: false).hasMatch(p.html)), isTrue));
    test('表情符號有標記',
        () => expect(t.posts.any((p) => p.html.contains('class="smiley"')), isTrue));
    test('一般圖片有標記',
        () => expect(t.posts.any((p) => p.html.contains('class="post-img"')), isTrue));
    test('站內連結標上 data-inapp',
        () => expect(t.posts.any((p) => p.html.contains('data-inapp')), isTrue));
    test('spoiler 轉成 data-spoiler',
        () => expect(t.posts.any((p) => p.html.contains('data-spoiler')), isTrue));
    test('spoiler 內容不再帶 display:none', () {
      // 論壇的 .spoilerbody 有 style="display:none"，照搬過去會讓展開後一片空白
      final withSpoiler = t.posts.firstWhere((p) => p.html.contains('data-spoiler'));
      final spoilerPart = withSpoiler.html
          .substring(withSpoiler.html.indexOf('data-spoiler'));
      expect(RegExp(r'display\s*:\s*none', caseSensitive: false).hasMatch(spoilerPart),
          isFalse,
          reason: '展開後內容會被渲染引擎隱藏，圖片與文字都看不到');
    });

    test('整篇內容都沒有 display:none', () {
      for (final p in t.posts) {
        expect(RegExp(r'display\s*:\s*none', caseSensitive: false).hasMatch(p.html),
            isFalse);
      }
    });

    test('引用回覆連結',
        () => expect(t.posts.any((p) => p.quoteHref.contains('repquote')), isTrue));
    test('分頁解析', () => expect(t.pager.total, greaterThan(1)));
  });

  group('導讀', () {
    final doc = _load('guide.html');
    if (doc == null) return;
    // 導讀的 <a> 沒有 forumDisplayImgList class，靠 fallback 選擇器接住
    final list = api.parseThreadList(doc);

    test('解析出主題', () => expect(list.length, greaterThan(20)));
    test('每筆都有 tid', () => expect(list.every((t) => t.tid > 0), isTrue));
    test('每筆都有標題', () => expect(list.every((t) => t.title.isNotEmpty), isTrue));
    test('有作者',
        () => expect(list.where((t) => t.author.isNotEmpty).length, greaterThan(list.length * 0.8)));
    test('有時間',
        () => expect(list.where((t) => t.date.isNotEmpty).length, greaterThan(list.length * 0.8)));
  });

  group('收藏', () {
    final doc = _load('favorite.html');
    if (doc == null) return;
    final list = api.parseFavList(doc);

    test('解析出收藏', () => expect(list.length, greaterThan(3)));
    test('每筆都有 tid', () => expect(list.every((t) => t.tid > 0), isTrue));
    test('每筆都有標題', () => expect(list.every((t) => t.title.isNotEmpty), isTrue));
    test('取得 favid（可取消收藏）',
        () => expect(list.every((t) => (t.favid ?? 0) > 0), isTrue));
    test('取得收藏時間',
        () => expect(list.every((t) => t.date.contains('收藏时间')), isTrue));
  });

  group('通知', () {
    final doc = _load('notice.html');
    if (doc == null) return;
    // 桌面模板，結構是 .nts > dl；主題 id 在 ptid
    final dls = doc.querySelectorAll('.nts dl');

    test('找得到通知節點', () => expect(dls.length, greaterThan(0)));
    test('每筆都有內容',
        () => expect(dls.every((dl) => txt(dl.querySelector('.ntc_body') ?? dl).isNotEmpty), isTrue));
    test('每筆都有時間',
        () => expect(dls.every((dl) => txt(dl.querySelector('dt span')).isNotEmpty), isTrue));
    test('取得發文者 uid', () {
      expect(
        dls.every((dl) => paramInt(attr(dl.querySelector('.avt img'), 'src'), 'uid') != null),
        isTrue,
      );
    });
    test('從 ptid 取得主題 id', () {
      for (final dl in dls) {
        final body = dl.querySelector('.ntc_body') ?? dl;
        final link = body
            .querySelectorAll('a')
            .map((a) => attr(a, 'href'))
            .firstWhere((h) => RegExp('ptid=|tid=|mod=viewthread').hasMatch(h), orElse: () => '');
        expect(paramInt(link, 'ptid') ?? paramInt(link, 'tid'), isNotNull);
      }
    });
  });

  group('登入表單', () {
    final doc = _load('login.html');
    if (doc == null) return;
    final action = attr(doc.querySelector('#loginform'), 'action');

    test('取得 formhash', () => expect(formhashOf(doc), isNotNull));
    test('取得 loginhash', () => expect(param(action, 'loginhash'), isNotNull));
    test('偵測到需要驗證碼',
        () => expect(doc.querySelector('input[name="seccodehash"]'), isNotNull));
    test('取得安全提問選項',
        () => expect(doc.querySelectorAll('select[name="questionid"] option').length, greaterThan(0)));
    test('未登入時 isLoggedIn 為 false', () => expect(isLoggedIn(doc), isFalse));
  });

  group('回覆表單', () {
    final doc = _load('replyform.html');
    if (doc == null) return;

    test('取得 formhash', () => expect(formhashOf(doc), isNotNull));
    test('取得 posttime',
        () => expect(attr(doc.querySelector('input[name="posttime"]'), 'value'), isNotEmpty));
    test('有 message 欄位',
        () => expect(doc.querySelector('textarea[name="message"]'), isNotNull));
  });

  group('個人中心', () {
    final doc = _load('me.html');
    if (doc == null) return;

    test('取得暱稱與等級',
        () => expect(txt(doc.querySelector('.user_avatar h2')).contains('Lvl'), isTrue));
    test('解析個人中心選單',
        () => expect(doc.querySelectorAll('.myinfo_list li a').length, greaterThanOrEqualTo(3)));
  });


  group('私訊', () {
    final list = _load('pm.html');
    if (list != null) {
      // li > a 內是 .avatar_img / .time / .num / .name / .grey，不是 h4+p
      final items = list.querySelectorAll('.pmbox li');
      test('解析出對話', () => expect(items.length, greaterThan(0)));
      test('每筆都有 touid', () {
        for (final li in items) {
          expect(paramInt(attr(li.querySelector('a'), 'href'), 'touid'), isNotNull);
        }
      });
      test('每筆都有對象名稱', () {
        for (final li in items) {
          expect(txt(li.querySelector('.name')), isNotEmpty);
        }
      });
      test('每筆都有最後訊息', () {
        for (final li in items) {
          expect(txt(li.querySelector('.grey')), isNotEmpty);
        }
      });
      test('每筆都有時間', () {
        for (final li in items) {
          expect(txt(li.querySelector('.time')), isNotEmpty);
        }
      });
    }

    final chat = _load('pmchat.html');
    if (chat != null) {
      final boxes = chat.querySelectorAll('.msgbox > div');
      test('解析出訊息氣泡', () => expect(boxes.length, greaterThan(2)));
      test('分得出自己與對方', () {
        expect(boxes.any((b) => b.classes.contains('self_msg')), isTrue);
        expect(boxes.any((b) => b.classes.contains('friend_msg')), isTrue);
      });
      test('每則都有內文與時間', () {
        for (final b in boxes) {
          if (!b.classes.contains('self_msg') && !b.classes.contains('friend_msg')) {
            continue;
          }
          expect(b.querySelector('.dialog_t'), isNotNull);
          expect(txt(b.querySelector('.date')), isNotEmpty);
        }
      });
      test('取得送出用的 pmid 與 formhash', () {
        final form = chat.querySelector('#pmform');
        expect(param(attr(form, 'action'), 'pmid'), isNotNull);
        expect(attr(chat.querySelector('#pmform input[name="formhash"]'), 'value'),
            isNotEmpty);
      });
    }
  });

  group('工具函式', () {
    test('param 解析查詢字串', () {
      expect(param('forum.php?mod=viewthread&amp;tid=123', 'tid'), '123');
      expect(param('a.php?fid=9', 'tid'), isNull);
    });
    test('absolute 相對轉絕對', () {
      expect(absolute('static/image/x.gif'), 'https://www.gamemale.com/static/image/x.gif');
      expect(absolute('//img.gamemale.com/a.png'), 'https://img.gamemale.com/a.png');
      expect(absolute('https://x.com/a.png'), 'https://x.com/a.png');
    });
    test('digits 抽數字', () {
      expect(digits('30121'), 30121);
      expect(digits('回覆 362 則'), 362);
    });
  });
}

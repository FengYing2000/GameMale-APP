// 用真實抓下來的論壇頁面驗證解析器。
// fixtures 不進版控，需要時執行 `dart run tool/fetch_fixtures.dart` 重抓。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:gamemale/api/discuz.dart' as api;
import 'package:gamemale/api/group.dart' as group_api;
import 'package:gamemale/api/http.dart';
import 'package:gamemale/api/models.dart';
import 'package:gamemale/api/parse.dart';
import 'package:gamemale/api/register.dart' as register;
import 'package:gamemale/api/smilies.dart' as smilies;
import 'package:gamemale/api/space.dart' as space;
import 'package:gamemale/i18n/s2t.dart';
import 'package:gamemale/ui/widgets/smart_image.dart';

File _f(String name) => File('test/fixtures/$name');

dom.Document? _load(String name) {
  final f = _f(name);
  if (!f.existsSync()) return null;
  return toDoc(f.readAsStringSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => S2T.instance.load());

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


  group('投票與樓中樓', () {
    final doc = _load('poll.html');
    if (doc == null) return;
    final t = api.parseThread(doc, 129896);

    test('解析出投票', () => expect(t.poll, isNotNull));
    test('投票有標題與選項', () {
      expect(t.poll!.title, isNotEmpty);
      expect(t.poll!.options.length, greaterThan(2));
    });
    test('選項有 id 與去掉序號的文字', () {
      for (final o in t.poll!.options) {
        expect(o.id, isNotEmpty);
        expect(o.text, isNotEmpty);
        expect(RegExp(r'^\d+\.').hasMatch(o.text), isFalse, reason: '序號應該去掉');
      }
    });
    test('投票有 formhash 與送出網址', () {
      expect(t.poll!.formhash, isNotEmpty);
      expect(t.poll!.action, contains('votepoll'));
    });

    test('解析出樓中樓', () {
      final withComments = t.posts.where((p) => p.comments.isNotEmpty);
      expect(withComments, isNotEmpty, reason: '這帖應該有樓中樓');
    });
    test('樓中樓有作者與內容', () {
      for (final p in t.posts) {
        for (final c in p.comments) {
          expect(c.name, isNotEmpty);
          expect(c.text, isNotEmpty);
          expect(c.text.startsWith(':'), isFalse, reason: '冒號應該去掉');
        }
      }
    });
  });


  group('評分', () {
    final form = _load('rateform.html');
    if (form != null) {
      // 論壇依等級決定給哪些項目，低等級帳號可能只有其中一兩項
      final inputs = form.querySelectorAll('input[name^="score"]');
      test('解析出可評分項目', () => expect(inputs.length, greaterThan(0)));
      test('每項都有欄位名與可選加分值', () {
        for (final i in inputs) {
          expect(attr(i, 'name').startsWith('score'), isTrue);
        }
        expect(form.querySelectorAll('ul[id^="scoreoption"] li'), isNotEmpty);
      });
      test('取得 formhash / tid / pid', () {
        expect(attr(form.querySelector('input[name="formhash"]'), 'value'), isNotEmpty);
        expect(attr(form.querySelector('input[name="tid"]'), 'value'), isNotEmpty);
        expect(attr(form.querySelector('input[name="pid"]'), 'value'), isNotEmpty);
      });
      test('取得可選理由', () {
        expect(form.querySelectorAll('#reasonselect li'), isNotEmpty);
      });
    }

    final view = _load('viewratings.html');
    if (view != null) {
      final rows = view
          .querySelectorAll('table.list tr')
          .where((tr) => tr.querySelectorAll('td').length >= 4)
          .where((tr) => txt(tr.querySelectorAll('td')[0]) != '积分')
          .toList();
      test('解析出評分紀錄', () => expect(rows.length, greaterThan(3)));
      test('每筆都有積分與評分者', () {
        for (final tr in rows) {
          final tds = tr.querySelectorAll('td');
          expect(txt(tds[0]), isNotEmpty);
          expect(txt(tds[1]), isNotEmpty);
        }
      });
    }
  });


  group('登入狀態判定', () {
    // 只憑「沒有登出連結」判定訪客，會把 inajax 浮層片段誤判成登出，
    // 使用者一點評分紀錄就被踢出登入狀態
    test('已登入的首頁：不是訪客頁', () {
      final doc = _load('index.html');
      if (doc == null) return;
      expect(isLoggedIn(doc), isTrue);
      expect(isGuestPage(doc), isFalse);
    });

    test('訪客首頁：不可被判成已登入', () {
      // 訪客版底部導覽也有 mycenter=1 的「我的」連結，
      // 拿它當已登入的證據會讓畫面顯示「已登入」卻抓不到 uid
      final doc = _load('guest_index.html');
      if (doc == null) return;
      expect(isLoggedIn(doc), isFalse);
      expect(isGuestPage(doc), isTrue);
      expect(api.parseHeaderUser(doc).uid, isNull);
    });

    test('鎖定板塊：仍算已登入，不可被踢出', () {
      final doc = _load('locked_forum.html');
      if (doc == null) return;
      expect(isLoggedIn(doc), isTrue);
      expect(isGuestPage(doc), isFalse);
      expect(api.parseHeaderUser(doc).uid, 677863);
      expect(noticeMessage(doc), contains('权限'));
    });

    test('登入頁：是訪客頁', () {
      final doc = _load('login.html');
      if (doc == null) return;
      expect(isLoggedIn(doc), isFalse);
      expect(isGuestPage(doc), isTrue);
    });

    test('評分表單（inajax 片段）不可被判成訪客', () {
      final doc = _load('rateform.html');
      if (doc == null) return;
      expect(isGuestPage(doc), isFalse,
          reason: '浮層片段沒有登入入口，不該觸發登出');
    });

    test('評分紀錄（inajax 片段）不可被判成訪客', () {
      final doc = _load('viewratings.html');
      if (doc == null) return;
      expect(isGuestPage(doc), isFalse,
          reason: '浮層片段沒有登入入口，不該觸發登出');
    });
  });



  group('附件圖片', () {
    final doc = _load('t65.html');
    if (doc == null) return;
    final t = api.parseThread(doc, 194065);

    // Discuz 手機版把附件圖放在 ul.img_list，那是 .postListCon 的兄弟節點，
    // 只讀內文的話用附件上傳的照片會整批不見
    test('樓主的附件圖有被收進內容', () {
      final imgs = RegExp('<img[^>]*>').allMatches(t.posts.first.html);
      expect(imgs.length, greaterThan(1), reason: '附件圖應該出現在內容裡');
    });

    test('附件圖網址已絕對化', () {
      expect(t.posts.first.html, contains('https://www.gamemale.com/forum.php?mod=image'));
    });

    test('附件圖外層的連結已拆掉（避免蓋掉點圖放大）', () {
      final head = t.posts.first.html;
      final i = head.indexOf('img_list');
      if (i < 0) return;
      expect(head.substring(i), isNot(contains('<a ')));
    });
  });


  group('評分紀錄合併', () {
    final doc = _load('viewratings.html');
    if (doc == null) return;

    test('同一人同一次評分合併成一筆', () {
      final rows = doc
          .querySelectorAll('table.list tr')
          .where((tr) => tr.querySelectorAll('td').length >= 4)
          .where((tr) => txt(tr.querySelectorAll('td')[0]) != '积分')
          .length;
      // 論壇是一項積分一列，合併後筆數一定比原始列數少
      expect(rows, greaterThan(3));
    });
  });


  group('訪客看帖的附件提示', () {
    final doc = _load('guest_thread.html');
    if (doc == null) return;
    final t = api.parseThread(doc, 194065);

    // 訪客時論壇把附件換成 .warning 提示，它和 .img_list 一樣在內文之外，
    // 沒撈進來的話畫面上會是一片空白，使用者不知道發生什麼事
    test('提示文字有出現在內容裡', () {
      expect(t.posts.first.html, contains('登录'));
    });

    test('提示裡的登入連結有保留', () {
      expect(t.posts.first.html, contains('mod=logging'));
    });

    test('訪客看帖仍可解析出樓層', () {
      expect(t.posts.length, greaterThan(3));
    });
  });


  group('需要登入的板塊', () {
    // 訪客進需要登入的板塊時，論壇直接 302 轉到登入頁，
    // 跟隨轉址後解析到的是登入表單 —— 照一般流程會顯示成「這個板塊沒有主題」
    final doc = _load('guest_locked_forum.html');
    if (doc == null) return;

    test('被判定為需要登入', () {
      expect(isGuestPage(doc), isTrue);
    });

    test('板塊資料帶上 requiresLogin', () {
      final f = api.parseForumFromDoc(doc, 150);
      expect(f.requiresLogin, isTrue);
      expect(f.list, isEmpty);
    });
  });


  group('樓中樓內容', () {
    final doc = _load('poll.html');
    if (doc == null) return;
    final t = api.parseThread(doc, 129896);
    final withComments = t.posts.where((p) => p.comments.isNotEmpty).toList();

    test('有解析出樓中樓', () => expect(withComments, isNotEmpty));

    test('每則都有內容，不能只有暱稱和時間', () {
      // 結構是 <a><em>暱稱</em></a><em>:內容</em><div>時間</div>
      // 取 querySelectorAll('em').last 會抓到時間那個 em
      for (final p in withComments) {
        for (final c in p.comments) {
          expect(c.text, isNotEmpty, reason: '${c.name} 的樓中樓沒有內容');
          expect(c.text, isNot(startsWith(':')));
        }
      }
    });
  });

  group('是否需要登入', () {
    test('訪客瀏覽公開板塊不算被擋', () {
      final doc = _load('guest_index.html');
      if (doc == null) return;
      // 訪客頁尾一樣有登入連結，不能拿 isGuestPage 當「需要登入」
      expect(isLoginWall(doc), isFalse);
      expect(isGuestPage(doc), isTrue);
    });

    test('真的被轉到登入表單才算', () {
      final doc = _load('guest_locked_forum.html');
      if (doc == null) return;
      expect(isLoginWall(doc), isTrue);
    });
  });


  group('送出動作遇到登入牆', () {
    // 訪客按回覆／收藏／評分時，論壇會把我們轉到登入頁。
    // 少了這個判斷會顯示「成功」但實際什麼都沒發生 —— 最容易讓人白忙的 bug
    final wall = _load('guest_locked_forum.html');
    if (wall == null) return;

    test('登入頁被視為未送出', () {
      expect(isLoginWall(wall), isTrue);
    });

    test('公開內容頁不會被誤判成登入牆', () {
      final ok = _load('index.html');
      if (ok == null) return;
      expect(isLoginWall(ok), isFalse);
    });
  });

  group('個人資料（桌面模板）', () {
    final doc = _load('profile.html');
    if (doc == null) return;
    final p = api.parseProfile(doc, 610657);

    test('抓到名字，而且不含 UID 那一段', () {
      expect(p.name, isNotEmpty);
      expect(p.name, isNot(contains('UID')));
    });
    test('用戶組來自活躍概況，不是登入者自己的等級', () => expect(p.level, isNotEmpty));
    test('擴展角色組會拆成多個', () {
      // 這頁是「GM活动员,战士 · I」，逗號要拆開
      expect(p.roles.length, greaterThan(1));
      expect(p.roles.every((r) => !r.contains(',')), isTrue);
    });
    test('欄位有標籤也有值',
        () => expect(p.fields.every((f) => f.label.isNotEmpty && f.value.isNotEmpty), isTrue));
    test('積分不會混進一般欄位', () {
      expect(p.credits.length, greaterThan(5));
      expect(p.fields.any((f) => f.label.contains('金币') || f.label.contains('金幣')), isFalse);
    });
    test('統計是連結，不會被當成欄位', () {
      expect(p.stats, isNotEmpty);
      expect(p.stats.every((s) => s.url.isNotEmpty), isTrue);
    });
    test('勳章有圖有名字', () {
      expect(p.medals, isNotEmpty);
      expect(p.medals.every((m) => m.image.startsWith('http')), isTrue);
      expect(p.medals.any((m) => m.name.isNotEmpty), isTrue);
    });
    test('勳章說明是純文字，不留 HTML 標籤', () {
      expect(p.medals.any((m) => m.desc.isNotEmpty), isTrue);
      expect(p.medals.every((m) => !m.desc.contains('<')), isTrue);
    });
    test('區塊只留有連結的（已加入群組），標題區塊與勳章不重複列入', () {
      expect(p.sections.any((s) => s.title.contains('群')), isTrue);
      expect(p.sections.any((s) => s.title.contains('勋章') || s.title.contains('勳章')), isFalse);
      expect(p.sections.every((s) => s.links.isNotEmpty), isTrue);
    });
    test('版塊/群組連結解得出 fid',
        () => expect(p.sections.expand((s) => s.links).any((l) => l.fid != null), isTrue));
    test('看別人的資料 isSelf 是 false', () => expect(p.isSelf, isFalse));
  });

  group('個人空間', () {
    SpaceData? load(String name, SpaceTab tab) {
      final doc = _load('space_$name.html');
      return doc == null ? null : space.parseSpace(doc, tab);
    }

    test('首頁把區塊拉平成摘要', () {
      final d = load('index', SpaceTab.home);
      if (d == null) return;
      expect(d.owner, isNotEmpty);
      expect(d.items, isNotEmpty);
      expect(d.items.every((b) => b.children.isNotEmpty), isTrue);
      // 「个人资料」那塊是 <em>標籤</em>值，不補空白會黏成「网名昵称风」
      final info = d.items.where((b) => b.title.contains('资料') || b.title.contains('資料'));
      if (info.isNotEmpty) {
        expect(info.first.children.any((c) => c.title.contains('  ')), isTrue);
      }
    });

    test('記錄有正文、作者、時間，回覆掛在 children', () {
      final d = load('doing', SpaceTab.doing);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.title.isNotEmpty && i.author.isNotEmpty), isTrue);
      expect(d.items.any((i) => i.children.isNotEmpty), isTrue);
      expect(d.pager.total, greaterThan(1));
    });

    test('日誌的作者取自內文那列，不是頭像連結', () {
      final d = load('blog', SpaceTab.blog);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.title.isNotEmpty), isTrue);
      expect(d.items.every((i) => i.author.isNotEmpty), isTrue);
      expect(d.items.any((i) => i.meta.contains('阅读') || i.meta.contains('閱讀')), isTrue);
    });

    test('相冊有封面與張數', () {
      final d = load('album', SpaceTab.album);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.title.isNotEmpty), isTrue);
      expect(d.items.any((i) => i.albumId != null), isTrue);
    });

    test('主題解得出 tid 與版塊（版塊那格沒有 class）', () {
      final d = load('thread', SpaceTab.thread);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.tid != null), isTrue);
      expect(d.items.any((i) => i.fid != null), isTrue);
      expect(d.items.any((i) => i.meta.contains(' · ')), isTrue);
    });

    test('留言板有留言者、時間、內文，也拿得到 formhash', () {
      final d = load('wall', SpaceTab.wall);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.author.isNotEmpty), isTrue);
      expect(d.items.every((i) => i.title.isNotEmpty), isTrue);
      expect(d.formhash, isNotEmpty);
    });

    test('好友有 uid 與頭像', () {
      final d = load('friend', SpaceTab.friend);
      if (d == null) return;
      expect(d.items, isNotEmpty);
      expect(d.items.every((i) => i.uid != null && i.uid! > 0), isTrue);
      expect(d.items.every((i) => i.avatar.startsWith('http')), isTrue);
    });
  });

  group('表情', () {
    final f = _f('smilies.js');
    if (!f.existsSync()) return;
    final groups = smilies.parseSmilies(f.readAsStringSync());

    test('解析出多組表情', () => expect(groups.length, greaterThan(3)));
    test('每組都有名字跟內容', () {
      expect(groups.every((g) => g.name.isNotEmpty), isTrue);
      expect(groups.every((g) => g.items.isNotEmpty), isTrue);
    });
    test('BBCode 是 {:分組_編號:}', () {
      final all = groups.expand((g) => g.items);
      expect(all.every((s) => RegExp(r'^\{:\d+_\d+:\}$').hasMatch(s.code)), isTrue);
    });
    test('圖片是絕對網址', () {
      final all = groups.expand((g) => g.items);
      expect(all.every((s) => s.url.startsWith('https://')), isTrue);
      expect(all.every((s) => s.url.contains('/smiley/')), isTrue);
    });
    test('對得上手機回覆表單給的代碼（呆呆第一個是 {:3_41:}）', () {
      final all = groups.expand((g) => g.items).toList();
      final m = all.where((s) => s.code == '{:3_41:}');
      expect(m, isNotEmpty);
      expect(m.first.url, endsWith('/smiley/grapeman/01.gif'));
    });
    test('編號不重複', () {
      final codes = groups.expand((g) => g.items).map((s) => s.code).toList();
      expect(codes.toSet().length, codes.length);
    });
  });

  group('回帖獎勵', () {
    test('沒有 #pl_top 就是沒有獎勵', () {
      final doc = _load('thread.html');
      if (doc == null) return;
      expect(api.parseThreadPrize(doc), isNull);
    });
    test('解得出獎池與規則', () {
      final doc = toDoc('<div id="pl_top"><table><tr class="ad">'
          '<td class="pls"></td><td class="plc"></td></tr><tr>'
          '<td class="pls"><img src="static/image/common//thread_prize_s.png" alt="回帖奖励" />'
          '<strong>13783 枚金币</strong></td>'
          '<td class="plc">回复本帖可获得 77 枚金币奖励! 每人限 1 次</td></tr></table></div>');
      final p = api.parseThreadPrize(doc);
      expect(p, isNotNull);
      expect(p!.pool, contains('13783'));
      // 第一列是空的廣告列，不能抓到空字串
      expect(p.rule, contains('77'));
    });
  });

  group('註冊問答', () {
    final doc = _load('register.html');
    if (doc == null) return;
    final q = register.parseRegisterQuiz(doc);

    test('抓得到 formhash', () => expect(q.formhash, isNotEmpty));
    test('解析出題目', () => expect(q.questions.length, greaterThan(3)));
    test('每題都有題幹跟選項', () {
      expect(q.questions.every((x) => x.title.isNotEmpty), isTrue);
      expect(q.questions.every((x) => x.options.length > 1), isTrue);
    });
    test('欄位名是 Discuz 的 question[n] 形式', () {
      expect(q.questions.every((x) => x.field.startsWith('question[')), isTrue);
    });
    test('複選題認得出來（欄位名結尾是 []）', () {
      final multi = q.questions.where((x) => x.multi);
      expect(multi, isNotEmpty);
      expect(multi.every((x) => x.field.endsWith('[]')), isTrue);
    });
    test('單選題欄位名是 [0]', () {
      final single = q.questions.where((x) => !x.multi);
      expect(single.every((x) => x.field.endsWith('[0]')), isTrue);
    });
    test('選項都有 value', () {
      expect(
        q.questions.expand((x) => x.options).every((o) => o.value.isNotEmpty),
        isTrue,
      );
    });
    test('讀得到頂端公告（目前是關閉註冊）', () => expect(q.notice, isNotEmpty));
  });

  group('網址組裝', () {
    test('手機版一律補 mobile=2', () {
      expect(Api.mobileUrl('forum.php'), '/forum.php?mobile=2');
      expect(Api.mobileUrl('forum.php?fid=1'), '/forum.php?fid=1&mobile=2');
      // 已經有了就不要重複加
      expect(Api.mobileUrl('forum.php?mobile=2'), '/forum.php?mobile=2');
    });
    test('桌面版要明寫 mobile=no —— 只是拿掉 mobile=2 沒用', () {
      // Discuz 會依 iPhone UA 自動轉手機版，不明講就拿不到桌面模板
      expect(Api.desktopUrl('home.php?mod=space'), '/home.php?mod=space&mobile=no');
      expect(Api.desktopUrl('home.php?do=profile&mobile=2'),
          '/home.php?do=profile&mobile=no');
      expect(Api.desktopUrl('/forum.php'), '/forum.php?mobile=no');
    });
  });

  group('積分變化 cookie', () {
    // 真實案例：回覆一帖後金幣 827→830、血液 4097→4101、咒術 64→65，
    // 其餘不變。App 一度顯示成「血液+3 追隨+4 知識+1」—— 整串位移一格。
    setUp(() {
      api.captureCreditNamesForTest(
          '1|旅程|里,2|金币|枚,3|血液|滴,4|追随|人,5|咒术|卷,6|知识|点,7|灵魂|隻,8|堕落|黑');
    });

    // cookie 是 `總積分D變化1…D變化8D uid`，共十格
    const cookie = '3D0D3D4D0D1D0D0D0D677863';

    test('依積分 ID 定位，不是照順序數', () {
      final out = api.parseCreditNotice(cookie, uid: 677863);
      // 積分名稱是系統文字，介面設繁體時會跟著轉
      expect(out.map((c) => c.toString()).toList(),
          ['金幣 +3枚', '血液 +4滴', '咒術 +1卷']);
    });

    test('不會把變化套到下一個名稱上', () {
      final names = api.parseCreditNotice(cookie, uid: 677863).map((c) => c.name);
      expect(names, isNot(contains('追隨')), reason: '追隨這次沒有變動');
      expect(names, isNot(contains('知識')));
      expect(names, isNot(contains('旅程')));
    });

    test('第 0 格是總積分，不能被當成第一項', () {
      // 總積分 3 若被誤讀，就會多出一筆「旅程 +3」
      expect(api.parseCreditNotice(cookie, uid: 677863).length, 3);
    });

    test('uid 對不上就整份丟掉', () {
      expect(api.parseCreditNotice(cookie, uid: 123456), isEmpty);
    });

    test('沒有變化時回空', () {
      expect(api.parseCreditNotice('0D0D0D0D0D0D0D0D0D677863', uid: 677863),
          isEmpty);
    });

    test('負值也讀得出來', () {
      final out = api.parseCreditNotice('-5D0D-5D0D0D0D0D0D0D677863', uid: 677863);
      expect(out.single.toString(), '金幣 -5枚');
    });
  });

  group('版塊篩選參數', () {
    test('預設什麼都不帶', () {
      expect(const ForumQuery().toParams(), isEmpty);
      expect(const ForumQuery().isDefault, isTrue);
    });
    test('投票／懸賞走 specialtype', () {
      expect(const ForumQuery(special: 'poll').toParams(),
          {'filter': 'specialtype', 'specialtype': 'poll'});
      expect(const ForumQuery(special: 'reward').toParams()['specialtype'], 'reward');
    });
    test('最新與熱門會自己帶上 orderby', () {
      expect(const ForumQuery(tab: 'lastpost').toParams(),
          {'filter': 'lastpost', 'orderby': 'lastpost'});
      // 熱門的 orderby 是 heats，不是 heat
      expect(const ForumQuery(tab: 'heat').toParams()['orderby'], 'heats');
    });
    test('精華要多帶 digest=1', () {
      expect(const ForumQuery(tab: 'digest').toParams()['digest'], '1');
    });
    test('排序：發帖時間走 author，回覆與查看走 reply', () {
      expect(const ForumQuery(orderby: 'dateline').toParams()['filter'], 'author');
      expect(const ForumQuery(orderby: 'replies').toParams()['filter'], 'reply');
      expect(const ForumQuery(orderby: 'views').toParams()['filter'], 'reply');
    });
    test('時間可以疊在 specialtype 上（實測過會再篩一次）', () {
      final q = const ForumQuery(special: 'reward', dateline: 604800).toParams();
      expect(q['filter'], 'specialtype');
      expect(q['specialtype'], 'reward');
      expect(q['dateline'], '604800');
    });
    test('主題分類優先於其他篩選', () {
      final q = const ForumQuery(typeid: 9, special: 'poll').toParams();
      expect(q['filter'], 'typeid');
      expect(q['typeid'], '9');
      expect(q.containsKey('specialtype'), isFalse);
    });
    test('hasExtra 只認排序與時間', () {
      expect(const ForumQuery(tab: 'digest').hasExtra, isFalse);
      expect(const ForumQuery(orderby: 'views').hasExtra, isTrue);
      expect(const ForumQuery(dateline: 86400).hasExtra, isTrue);
    });
  });

  group('高級搜索參數', () {
    test('預設只帶範圍與排序', () {
      final p = const AdvancedSearch().toParams();
      expect(p['srchfilter'], 'all');
      expect(p['orderby'], 'lastpost');
      expect(p['ascdesc'], 'desc');
      expect(p.containsKey('srchtype'), isFalse);
      expect(const AdvancedSearch().isDefault, isTrue);
    });
    test('全文搜尋帶 srchtype=fulltext', () {
      expect(const AdvancedSearch(fulltext: true).toParams()['srchtype'], 'fulltext');
    });
    test('作者帶 srchuname', () {
      expect(const AdvancedSearch(author: 'cdcai').toParams()['srchuname'], 'cdcai');
    });
    test('時間為 0 時不帶 srchfrom 與 before', () {
      final p = const AdvancedSearch().toParams();
      expect(p.containsKey('srchfrom'), isFalse);
      expect(p.containsKey('before'), isFalse);
    });
    test('「以前」才會把 before 設成 1', () {
      expect(const AdvancedSearch(srchfrom: 86400).toParams()['before'], '');
      expect(
          const AdvancedSearch(srchfrom: 86400, before: true).toParams()['before'],
          '1');
    });
  });

  group('ajax 送出結果', () {
    // 論壇的 ajax 回應常常整包只是一段 <script>，直接把 body 當訊息
    // 會把 JavaScript 一起唸出來
    test('抓 showDialog 裡的訊息', () {
      const body = "<root><![CDATA[<script>hideWindow('x');"
          "showDialog('操作成功 ', 'right', null);</script>]]></root>";
      final r = api.submitResult(body, '取消收藏');
      expect(r.message, '操作成功');
      expect(r.ok, isTrue);
    });
    test('沒有 showDialog 時抓 succeedhandle 的第二個參數', () {
      const body = "<root><![CDATA[<script>if(typeof succeedhandle_a_delete_1=="
          "'function') {succeedhandle_a_delete_1('home.php?x=1', '操作成功 ', "
          "{'favid':'1'});}</script>]]></root>";
      final r = api.submitResult(body, '取消收藏');
      expect(r.message, '操作成功');
      expect(r.message, isNot(contains('succeedhandle')));
      expect(r.ok, isTrue);
    });
    test('失敗訊息不會被當成成功', () {
      const body = "<root><![CDATA[<script>showDialog('您需要先登录才能继续本操作', "
          "'alert');</script>]]></root>";
      expect(api.submitResult(body, '取消收藏').ok, isFalse);
    });
  });

  group('圖片來源判斷', () {
    // 帖子裡的 emoji 走 jsdelivr 的 SVG，日誌裡常見內嵌的 data: URI，
    // 兩種都不是一般的 png/jpg，走錯解碼路徑就整片「圖片載入失敗」
    test('認得出 data: URI', () {
      expect(SmartImage.isData('data:image/png;base64,iVBORw0KGgo='), isTrue);
      expect(SmartImage.isData('https://x.com/a.png'), isFalse);
    });
    test('認得出 SVG', () {
      expect(
          SmartImage.isSvg(
              'https://gcore.jsdelivr.net/gh/googlefonts/noto-emoji/svg/emoji_u1f60d.svg'),
          isTrue);
      expect(SmartImage.isSvg('data:image/svg+xml,%3Csvg%3E'), isTrue);
      expect(SmartImage.isSvg('https://img.gamemale.com/a.jpg'), isFalse);
    });
    test('data: URI 解得出位元組', () {
      // 1x1 透明 PNG
      const png = 'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final bytes = SmartImage.decodeData(png);
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(20));
      // PNG 檔頭
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
    test('base64 夾雜換行也要解得開', () {
      const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA\n'
          'AAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      expect(SmartImage.decodeData(png), isNotNull);
    });
    test('壞掉的 data: URI 回 null，不會炸掉', () {
      expect(SmartImage.decodeData('data:image/png;base64,@@@@'), isNull);
      expect(SmartImage.decodeData('data:image/png'), isNull);
    });
  });

  group('分頁列', () {
    PageInfo p(String html, {int current = 1}) =>
        parsePager(toDoc('<div class="pg">$html</div>'), current: current);

    test('有頁碼時照論壇給的算', () {
      final r = p('<strong>2</strong><a href="?page=1">1</a>'
          '<a href="?page=3">3</a><a href="?page=9">9</a>'
          '<a href="?page=3" class="nxt">下一页</a>');
      expect(r.page, 2);
      expect(r.total, 9);
      expect(r.numbered, isTrue);
      expect(r.hasNext, isTrue);
    });

    test('只有上下頁時，目前頁數要用我們請求的那一頁', () {
      // 我的回覆、記錄廣場就是這種：沒有 <strong>，也沒有頁碼連結
      const only = '<span class="pgb"><a href="?page=1">上一页</a></span>'
          '<a href="?page=3" class="nxt">下一页</a>';
      final r = p(only, current: 2);
      expect(r.page, 2, reason: '照 DOM 算會變成第 1 頁');
      expect(r.total, greaterThanOrEqualTo(2));
      expect(r.numbered, isFalse, reason: '沒有真的頁碼，不該給人點頁數表');
      expect(r.hasNext, isTrue);
      expect(r.hasPrev, isTrue);
    });

    test('下一頁的 page=3 不該被當成總頁數', () {
      final r = p('<a href="?page=2" class="nxt">下一页</a>', current: 1);
      expect(r.page, 1);
      // 只知道還有下一頁，總數是猜的
      expect(r.total, 2);
      expect(r.numbered, isFalse);
    });

    test('沒有分頁列就是單頁', () {
      final r = parsePager(toDoc('<div></div>'), current: 3);
      expect(r.page, 3);
      expect(r.hasNext, isFalse);
    });
  });

  group('系統文字 vs 使用者內容', () {
    // 使用者發的東西一律原文（轉過的標題跟網頁版對不起來），
    // 系統文字（版塊名、積分名、論壇提示）才跟著介面語言
    test('txt 不轉，sys 才轉', () {
      uiTraditional = true;
      convertToTraditional = false;
      final doc = toDoc('<p>汉化补丁</p>');
      expect(txt(doc.querySelector('p')), '汉化补丁', reason: '使用者內容要保留原文');
      expect(sys('汉化补丁'), '漢化補丁');
    });
    test('介面設簡體時系統文字也維持簡體', () {
      uiTraditional = false;
      expect(sys('金币'), '金币');
      uiTraditional = true;
    });
    test('送出失敗要看原文判斷，別被轉換擋掉', () {
      const body = "<root><![CDATA[<script>showDialog('您需要先登录才能继续本操作',"
          "'alert');</script>]]></root>";
      final r = api.submitResult(body, '收藏');
      expect(r.ok, isFalse, reason: '轉成繁體後「需要先登录」就對不上樣式了');
      // 顯示出來的還是繁體
      expect(r.message, contains('登錄'));
    });
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

  group('淘帖列表', () {
    final doc = _load('collection_index.html');
    if (doc == null) return;
    final r = api.parseCollectionIndex(doc);

    test('解析出專輯', () => expect(r.items.length, greaterThan(3)));
    test('每個專輯有 ctid 與名稱', () {
      expect(r.items.every((c) => c.ctid > 0 && c.name.isNotEmpty), isTrue);
    });
    test('有主題數與訂閱資訊',
        () => expect(r.items.any((c) => c.threads.isNotEmpty && c.meta.isNotEmpty), isTrue));
  });

  group('淘專輯內頁', () {
    final doc = _load('collection_view.html');
    if (doc == null) return;
    final v = api.parseCollectionView(doc, 452);

    test('有專輯名稱', () => expect(v.name.isNotEmpty, isTrue));
    test('有收錄主題', () => expect(v.list.length, greaterThan(3)));
    test('每筆主題有 tid 與標題',
        () => expect(v.list.every((t) => t.tid > 0 && t.title.isNotEmpty), isTrue));
    test('認得出已訂閱狀態（取消訂閱＝已訂閱）', () => expect(v.following, isTrue));
  });

  group('記錄廣場（桌面）', () {
    final doc = _load('doing_desktop.html');
    if (doc == null) return;
    final d = api.parseDoingPage(doc);

    test('解析出記錄', () => expect(d.items.isNotEmpty, isTrue));
    test('每則有 doid 與正文',
        () => expect(d.items.every((x) => x.doid > 0), isTrue));
    final withComments = d.items.where((x) => x.comments.isNotEmpty).toList();
    test('有帶回覆的記錄', () => expect(withComments.isNotEmpty, isTrue));
    test('回覆有時間（不是空括號）', () {
      final cs = withComments.expand((x) => x.comments);
      expect(cs.any((c) => c.time.isNotEmpty), isTrue);
    });
    test('回覆有作者', () {
      final cs = withComments.expand((x) => x.comments);
      expect(cs.every((c) => c.author.isNotEmpty), isTrue);
    });
  });

  group('簽到排行', () {
    final xml = _f('sign_rank.xml');
    if (!xml.existsSync()) return;
    final doc = toDoc(api.unwrapAjax(xml.readAsStringSync()));
    final rows = api.parseSignRank(doc);

    test('解析出排行列', () => expect(rows.length, greaterThan(3)));
    test('每列有暱稱與天數',
        () => expect(rows.every((r) => r.name.isNotEmpty && r.totalDays.isNotEmpty), isTrue));
    test('等級有解出',
        () => expect(rows.any((r) => r.level.contains('LV')), isTrue));
  });

  group('道具彈窗', () {
    final xml = _f('magic_buy.xml');
    if (!xml.existsSync()) return;
    final doc = toDoc(api.unwrapAjax(xml.readAsStringSync()));
    final op = api.parseMagicOp(doc);

    test('解析成功（有表單）', () => expect(op.ready, isTrue));
    test('帶得出 mid 與 formhash', () {
      expect(op.fields['mid'], isNotNull);
      expect((op.fields['formhash'] ?? '').isNotEmpty, isTrue);
    });
    test('是購買、有數量欄與送出旗標', () {
      expect(op.operation, 'buy');
      expect(op.hasNum, isTrue);
      expect(op.submitName, 'operatesubmit');
    });
    test('有售價之類的說明行',
        () => expect(op.lines.any((l) => l.contains('售價') || l.contains('售价')), isTrue));
  });

  group('淘帖表單', () {
    final xml = _f('addthread.xml');
    if (!xml.existsSync()) return;
    final doc = toDoc(api.unwrapAjax(xml.readAsStringSync()));

    test('解析出我的專輯選項', () {
      final opts = doc.querySelectorAll('#selectCollection option');
      expect(opts.isNotEmpty, isTrue);
      expect(int.tryParse(opts.first.attributes['value'] ?? ''), isNotNull);
    });
  });

  group('我自己建的淘專輯', () {
    final doc = _load('collection_mine.html');
    if (doc == null) return;
    final v = api.parseCollectionView(doc, 656);

    test('認得出是自己建的（有編輯／刪除）', () => expect(v.mine, isTrue));
    test('編輯／刪除連結解得出',
        () => expect(v.editUrl.isNotEmpty && v.removeUrl.isNotEmpty, isTrue));
    test('有創建人與 uid',
        () => expect(v.author.isNotEmpty && (v.authorUid ?? 0) > 0, isTrue));
    test('有 formhash（發評論／刪除要用）',
        () => expect(v.formhash.isNotEmpty, isTrue));
  });

  group('群組首頁', () {
    final doc = _load('group_index.html');
    if (doc == null) return;
    final g = group_api.parseGroupIndexDoc(doc);

    test('有推薦群組', () => expect(g.recommended.isNotEmpty, isTrue));
    test('推薦群組每個有 fid 與名稱',
        () => expect(g.recommended.every((x) => x.fid > 0 && x.name.isNotEmpty), isTrue));
    test('有群組分類', () => expect(g.categories.isNotEmpty, isTrue));
    test('分類底下有群組',
        () => expect(g.categories.any((c) => c.groups.isNotEmpty), isTrue));
    test('有積分排行', () => expect(g.ranking.isNotEmpty, isTrue));
    test('排行每列有 fid',
        () => expect(g.ranking.every((r) => r.fid > 0 && r.name.isNotEmpty), isTrue));
  });

  group('群組成員列表', () {
    final doc = _load('group_members.html');
    if (doc == null) return;
    final r = group_api.parseGroupMembersDoc(doc);

    test('解析出成員', () => expect(r.members.isNotEmpty, isTrue));
    test('每個成員有名字',
        () => expect(r.members.every((m) => m.name.isNotEmpty), isTrue));
    test('認得出群主',
        () => expect(r.members.any((m) => m.title.contains('群主')), isTrue));
  });

  group('頁首提醒選單（紅點）', () {
    final doc = _load('prompt_menu.html');
    if (doc == null) return;
    final c = api.parsePromptCounts(doc);

    // 樣本是「系统提醒(1)、消息0、新听众0」，鈴鐺該亮、訊息不亮
    test('系統提醒 1 則要算進提醒未讀', () => expect(c.notice, 1));
    test('沒有未讀私訊', () => expect(c.pm, 0));
    test('認得出是 system 這一類有新的', () => expect(c.views['system'], 1));

    test('有未讀私訊時 prompt_news_N 的 N 就是數量', () {
      // prompt_news 的未讀數藏在 class 後綴裡（消息=私訊）
      final d = toDoc(
          '<ul id="myprompt_menu"><li>'
          '<a href="home.php?mod=space&do=pm"><em class="prompt_news_3"></em>消息</a>'
          '</li></ul>');
      expect(api.parsePromptCounts(d).pm, 3);
    });
  });
}

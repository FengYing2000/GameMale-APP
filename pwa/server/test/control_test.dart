import 'dart:convert';
import 'dart:io';

import 'package:gm_server/control/api.dart';
import 'package:gm_server/control/service.dart';
import 'package:gm_server/control/store.dart';
import 'package:gm_server/control/tokens.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late ControlStore store;
  late ControlService svc;
  late DateTime clock;

  setUp(() {
    store = ControlStore();
    clock = DateTime.utc(2026, 9, 24, 12);
    svc = ControlService(store, TokenSigner(utf8.encode('k' * 32)),
        clock: () => clock, webBuild: () => 80);
  });

  group('token', () {
    test('簽出來的驗得過，改一個字就不過', () {
      final s = TokenSigner(utf8.encode('secret-key-secret-key-secret-key'));
      final t = s.sign({'k': 'beta', 'c': 'abc'});
      expect(s.verify(t)?['c'], 'abc');
      expect(s.verify('${t.substring(0, t.length - 1)}x'), isNull);
      expect(s.verify('garbage'), isNull);
      expect(TokenSigner(utf8.encode('other-key-other-key-other-key!!!')).verify(t), isNull);
    });

    test('測試碼格式 GMXX-XXXX-XXXX、沒有易混淆字元', () {
      for (var i = 0; i < 50; i++) {
        final c = newBetaCode();
        expect(c, matches(RegExp(r'^GM[2-9A-Z]{2}-[2-9A-Z]{4}-[2-9A-Z]{4}$')));
        expect(c.substring(2), isNot(matches(RegExp('[01OIL]'))));
      }
    });
  });

  group('啟用測試碼', () {
    test('輸入時不分大小寫、可省略連字號', () {
      final c = svc.createCodes(note: '小明').single;
      final r = svc.activate(input: c.code.toLowerCase().replaceAll('-', ' '), deviceId: 'device-0001');
      expect(r.ok, isTrue);
      expect(svc.checkBeta(r.token).ok, isTrue);
    });

    test('裝置上限：同一台重複啟用不多佔名額，第三台被擋', () {
      final c = svc.createCodes(maxDevices: 2).single;
      expect(svc.activate(input: c.code, deviceId: 'device-aaaa').ok, isTrue);
      expect(svc.activate(input: c.code, deviceId: 'device-aaaa').ok, isTrue);
      expect(svc.activate(input: c.code, deviceId: 'device-bbbb').ok, isTrue);
      final third = svc.activate(input: c.code, deviceId: 'device-cccc');
      expect(third.ok, isFalse);
      expect(third.message, contains('2 台'));
      expect(c.devices, hasLength(2));
    });

    test('上限 0＝不限', () {
      final c = svc.createCodes(maxDevices: 0).single;
      for (var i = 0; i < 5; i++) {
        expect(svc.activate(input: c.code, deviceId: 'device-000$i').ok, isTrue);
      }
    });

    test('打錯、停用、過期都擋，理由分得出來', () {
      expect(svc.activate(input: 'GMAA-BBBB-CCCC', deviceId: 'device-0001').message, contains('不存在'));
      final off = svc.createCodes().single..enabled = false;
      expect(svc.activate(input: off.code, deviceId: 'device-0001').message, contains('停用'));
      final old = svc.createCodes(expiresAt: clock.subtract(const Duration(days: 1))).single;
      expect(svc.activate(input: old.code, deviceId: 'device-0001').message, contains('過期'));
    });

    test('裝置 ID 格式不對就拒絕', () {
      final c = svc.createCodes().single;
      expect(svc.activate(input: c.code, deviceId: 'x').ok, isFalse);
      expect(svc.activate(input: c.code, deviceId: '<script>alert(1)</script>').ok, isFalse);
    });

    test('啟用後停用、過期、解綁，舊 token 立刻失效', () {
      final c = svc.createCodes().single;
      final t = svc.activate(input: c.code, deviceId: 'device-0001').token;
      c.enabled = false;
      expect(svc.checkBeta(t).state, BetaState.disabled);
      c.enabled = true;
      c.expiresAt = clock;
      expect(svc.checkBeta(t).state, BetaState.expired);
      c.expiresAt = null;
      c.devices.clear();
      expect(svc.checkBeta(t).state, BetaState.removed);
      store.codes.clear();
      expect(svc.checkBeta(t).state, BetaState.disabled);
    });

    test('App 自己解除綁定，名額還回去', () {
      final c = svc.createCodes(maxDevices: 1).single;
      final t = svc.activate(input: c.code, deviceId: 'device-0001').token;
      expect(svc.unbind(t), isTrue);
      expect(c.devices, isEmpty);
      expect(svc.activate(input: c.code, deviceId: 'device-0002').ok, isTrue);
    });
  });

  group('狀態', () {
    test('預設（沒開測試碼、沒維護）誰都能用', () {
      final s = svc.status(platform: 'ios', build: 70);
      expect(s['canUse'], isTrue);
    });

    test('需要測試碼：沒碼不能用，有碼可以', () {
      store.settings.betaRequired = true;
      expect(svc.status(platform: 'ios')['canUse'], isFalse);
      final c = svc.createCodes().single;
      final t = svc.activate(input: c.code, deviceId: 'device-0001').token;
      final s = svc.status(platform: 'ios', token: t);
      expect(s['canUse'], isTrue);
      expect((s['beta'] as Map)['hint'], matches(RegExp(r'^GM..-\*\*\*\*-....$')));
    });

    test('維護中：一般碼被擋，「維護時可用」的碼放行並標示', () {
      store.settings
        ..maintenance = true
        ..maintenanceMessage = '升級中';
      final normal = svc.createCodes().single;
      final owner = svc.createCodes(bypass: true).single;
      final tn = svc.activate(input: normal.code, deviceId: 'device-0001').token;
      final to = svc.activate(input: owner.code, deviceId: 'device-0002').token;

      final a = svc.status(platform: 'ios', token: tn);
      expect(a['canUse'], isFalse);
      expect((a['maintenance'] as Map)['message'], '升級中');

      final b = svc.status(platform: 'ios', token: to);
      expect(b['canUse'], isTrue);
      expect((b['maintenance'] as Map)['bypassed'], isTrue);
    });

    test('有新版就回下載網址；低於最低版本強制更新', () {
      svc.upsertRelease(version: '1.29.0', build: 78, notes: '新增測試碼',
          iosUrl: 'https://x/a.ipa', androidUrl: 'https://x/a.apk');
      final u = svc.status(platform: 'android', build: 77)['update'] as Map;
      expect((u['latest'] as Map)['url'], 'https://x/a.apk');
      expect(u['required'], isFalse);

      expect((svc.status(platform: 'android', build: 78)['update'] as Map)['latest'], isNull);

      store.settings.minBuild = 78;
      final s = svc.status(platform: 'ios', build: 77);
      expect((s['update'] as Map)['required'], isTrue);
      expect(s['canUse'], isFalse);
      // 不知道自己幾號（舊版沒送）不強制，免得誤鎖
      expect((svc.status(platform: 'ios')['update'] as Map)['required'], isFalse);
    });

    test('只有 Android 安裝檔的版本，iOS 不會被通知', () {
      svc.upsertRelease(version: '1.29.1', build: 79, androidUrl: 'https://x/b.apk');
      expect((svc.status(platform: 'ios', build: 77)['update'] as Map)['latest'], isNull);
    });

    test('網頁版比對的是目前部署的 build，不用下載網址', () {
      final u = svc.status(platform: 'web', build: 77)['update'] as Map;
      expect((u['latest'] as Map)['build'], 80);
      expect((u['latest'] as Map)['url'], '');
      expect((svc.status(platform: 'web', build: 80)['update'] as Map)['latest'], isNull);
    });

    test('查狀態會更新裝置的最後使用時間與版本', () {
      final c = svc.createCodes().single;
      final t = svc.activate(input: c.code, deviceId: 'device-0001', version: '1.28.2').token;
      clock = clock.add(const Duration(hours: 3));
      svc.status(platform: 'ios', version: '1.29.0', token: t);
      expect(c.devices.single.lastSeen, clock);
      expect(c.devices.single.appVersion, '1.29.0');
    });
  });

  group('網頁版轉發把關', () {
    test('都沒開就放行', () => expect(svc.gate(null), isNull));

    test('需要測試碼：沒碼 403、有碼放行', () {
      store.settings.betaRequired = true;
      expect(svc.gate(null)?.status, 403);
      final c = svc.createCodes().single;
      expect(svc.gate(svc.activate(input: c.code, deviceId: 'device-0001').token), isNull);
    });

    test('維護中 503，連有效的一般碼也擋', () {
      store.settings.maintenance = true;
      final c = svc.createCodes().single;
      final t = svc.activate(input: c.code, deviceId: 'device-0001').token;
      expect(svc.gate(t)?.status, 503);
      c.bypass = true;
      expect(svc.gate(t), isNull);
    });
  });

  group('HTTP', () {
    late ControlApi api;
    setUp(() => api = ControlApi(svc, adminPassword: 'pw-123', deployToken: 'deploy-xyz'));

    Future<Response> call(String method, String path,
            {Object? body, Map<String, String> headers = const {}}) async =>
        await api.router.call(Request(method, Uri.parse('https://852111.xyz$path'),
            body: body == null ? null : json.encode(body), headers: headers));

    Future<Map<String, Object?>> jsonOf(Response r) async =>
        json.decode(await r.readAsString()) as Map<String, Object?>;

    String cookieOf(Response r) => (r.headers['set-cookie'] ?? '').split(';').first;

    test('後台沒登入一律 401', () async {
      expect((await call('GET', '/api/admin/state')).statusCode, 401);
      expect((await call('POST', '/api/admin/codes', body: {})).statusCode, 401);
    });

    test('密碼錯 401；對了拿到只限 /api/admin 的 HttpOnly cookie', () async {
      expect((await call('POST', '/api/admin/login', body: {'password': 'nope'})).statusCode, 401);
      final ok = await call('POST', '/api/admin/login', body: {'password': 'pw-123'});
      expect(ok.statusCode, 200);
      final set = ok.headers['set-cookie']!;
      expect(set, contains('HttpOnly'));
      expect(set, contains('Path=/api/admin'));
      expect(set, contains('SameSite=Strict'));
    });

    test('改資料要帶 X-GM-Admin（擋跨站偽造）', () async {
      final login = await call('POST', '/api/admin/login', body: {'password': 'pw-123'});
      final cookie = cookieOf(login);
      expect((await call('GET', '/api/admin/state', headers: {'cookie': cookie})).statusCode, 200);
      expect((await call('POST', '/api/admin/codes', body: {'note': 'x'}, headers: {'cookie': cookie})).statusCode, 403);
      final made = await call('POST', '/api/admin/codes',
          body: {'note': 'x', 'count': 2}, headers: {'cookie': cookie, 'x-gm-admin': '1'});
      expect(made.statusCode, 200);
      expect((await jsonOf(made))['codes'], hasLength(2));
    });

    test('部署金鑰只能發佈版本，不能碰其他後台功能', () async {
      final auth = {'authorization': 'Bearer deploy-xyz'};
      final rel = await call('POST', '/api/admin/releases',
          body: {'version': '1.29.0', 'build': 78, 'iosUrl': 'https://x/a.ipa', 'androidUrl': 'http://insecure/a.apk'},
          headers: auth);
      expect(rel.statusCode, 200);
      final saved = (await jsonOf(rel))['release'] as Map;
      expect(saved['androidUrl'], '', reason: '只收 https');
      expect((await call('GET', '/api/admin/state', headers: auth)).statusCode, 401);
      expect((await call('POST', '/api/admin/releases', body: {'version': '1', 'build': 1},
              headers: {'authorization': 'Bearer wrong'}))
          .statusCode, 401);
    });

    test('網頁版啟用：token 只放 HttpOnly cookie，不交給 JS；原生版放在回應裡', () async {
      final c = svc.createCodes().single;
      final web = await call('POST', '/api/app/activate',
          body: {'code': c.code, 'device': 'browser-0001', 'platform': 'web'});
      expect((await jsonOf(web)).containsKey('token'), isFalse);
      expect(web.headers['set-cookie'], allOf(contains('gmx_beta='), contains('HttpOnly'), contains('Path=/')));

      final ios = await call('POST', '/api/app/activate',
          body: {'code': c.code, 'device': 'iphone-00001', 'platform': 'ios'});
      final token = (await jsonOf(ios))['token'] as String;
      final st = await jsonOf(await call('GET', '/api/app/status?platform=ios&build=77',
          headers: {'x-gm-token': token}));
      expect((st['beta'] as Map)['valid'], isTrue);
      expect(st['sourceUrl'], 'https://852111.xyz/api/app/source.json');
    });

    test('猜碼限流：同一 IP 十次以上被擋', () async {
      Response? last;
      for (var i = 0; i < 11; i++) {
        last = await call('POST', '/api/app/activate',
            body: {'code': 'GMAA-AAAA-AAAA', 'device': 'device-0001'},
            headers: {'x-forwarded-for': '1.2.3.4'});
      }
      expect(last!.statusCode, 429);
    });

    test('SideStore 來源只列有 iOS 安裝檔的版本', () async {
      svc.upsertRelease(version: '1.29.0', build: 78, iosUrl: 'https://x/a.ipa', iosSize: 100);
      svc.upsertRelease(version: '1.29.1', build: 79, androidUrl: 'https://x/b.apk');
      final j = await jsonOf(await call('GET', '/api/app/source.json'));
      final app = (j['apps'] as List).single as Map;
      expect(app['bundleIdentifier'], 'com.fengying.gamemale');
      expect((app['versions'] as List).single['version'], '1.29.0');
      expect(app['downloadURL'], 'https://x/a.ipa');
    });

    test('到期日只填日期＝當天台灣時間結束', () {
      expect(ControlApi.parseExpiry('2026-10-31'), DateTime.utc(2026, 10, 31, 15, 59, 59));
      expect(ControlApi.parseExpiry(''), isNull);
    });
  });

  group('存檔', () {
    test('存了再讀回來一樣', () async {
      final dir = await Directory.systemTemp.createTemp('gmctl');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/control.json');
      final a = ControlStore(file);
      final s = ControlService(a, TokenSigner(utf8.encode('k' * 32)));
      a.settings.maintenance = true;
      final c = s.createCodes(note: '備註', maxDevices: 3, bypass: true).single;
      s.activate(input: c.code, deviceId: 'device-0001', platform: 'ios');
      s.upsertRelease(version: '1.29.0', build: 78, notes: '一\n二');
      await a.save();

      final b = ControlStore(file);
      await b.load();
      expect(b.settings.maintenance, isTrue);
      expect(b.codes.single.code, c.code);
      expect(b.codes.single.bypass, isTrue);
      expect(b.codes.single.devices.single.platform, 'ios');
      expect(b.releases.single.notes, '一\n二');
    });
  });
}

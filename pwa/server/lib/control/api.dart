import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../rate_limit.dart';
import 'admin_page.dart';
import 'service.dart';
import 'tokens.dart';

/// App 控制台的 HTTP 端點。
///
/// * `/api/app/*`：App 與網頁版用——狀態（維護／測試碼／更新）、輸入測試碼、
///   更新日誌、SideStore 來源。
/// * `/admin` 與 `/api/admin/*`：後台，要密碼登入；發版腳本另外用部署金鑰。
///
/// 自己的 cookie 一律 `gmx_` 開頭，轉發論壇時整批濾掉（見 ForumProxy），
/// 不會送到論壇去。
class ControlApi {
  ControlApi(
    this.service, {
    this.adminPassword = '',
    this.deployToken = '',
  });

  final ControlService service;
  final String adminPassword;
  final String deployToken;

  static const betaCookie = 'gmx_beta';
  static const adminCookie = 'gmx_admin';
  static const _adminDays = 14;

  // 測試碼 2^49 種、每 IP 每 10 分鐘只給試 10 次，用猜的猜不到
  final _activateLimit = RateLimiter(maxPerWindow: 10, window: const Duration(minutes: 10));
  final _loginLimit = RateLimiter(maxPerWindow: 6, window: const Duration(minutes: 10));

  Router get router => Router()
    ..get('/api/app/status', _status)
    ..post('/api/app/activate', _activate)
    ..post('/api/app/unbind', _unbind)
    ..get('/api/app/changelog', _changelog)
    ..get('/api/app/source.json', _source)
    ..get('/admin', (Request r) => Response.ok(adminPageHtml, headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
          'x-frame-options': 'DENY',
          'referrer-policy': 'no-referrer',
        }))
    ..post('/api/admin/login', _login)
    ..post('/api/admin/logout', _logout)
    ..get('/api/admin/state', _auth(_state))
    ..put('/api/admin/settings', _auth(_saveSettings))
    ..post('/api/admin/codes', _auth(_createCodes))
    ..patch('/api/admin/codes/<id>', _auth(_updateCode))
    ..delete('/api/admin/codes/<id>', _auth(_deleteCode))
    ..delete('/api/admin/codes/<id>/devices/<device>', _auth(_unbindDevice))
    ..post('/api/admin/releases', _auth(_saveRelease, allowDeploy: true))
    ..delete('/api/admin/releases/<build>', _auth(_deleteRelease));

  /// 網頁版的論壇轉發要不要放行（null＝放行）
  Response? gate(Request r) {
    final block = service.gate(betaToken(r));
    return block == null ? null : _json(block.status, block.body);
  }

  // ── App ──────────────────────────────────────────────

  /// 原生 App 用標頭帶，網頁版靠 HttpOnly cookie（JS 讀不到、也不必讀）
  static String? betaToken(Request r) =>
      r.headers['x-gm-token'] ?? cookies(r)[betaCookie];

  Response _status(Request r) {
    final q = r.url.queryParameters;
    String h(String k) {
      try {
        return Uri.decodeComponent(r.headers[k] ?? '');
      } catch (_) {
        return '';
      }
    }

    final body = service.status(
      platform: q['platform'] ?? '',
      build: int.tryParse(q['build'] ?? '') ?? 0,
      token: betaToken(r),
      report: DeviceReport(
        platform: q['platform'] ?? '',
        version: q['version'] ?? '',
        model: h('x-gm-model'),
        os: h('x-gm-os'),
        ip: clientIp(r),
        forumUid: int.tryParse(r.headers['x-gm-forum-uid'] ?? ''),
        forumName: h('x-gm-forum-name'),
      ),
    );
    body['sourceUrl'] = '${_origin(r)}/api/app/source.json';
    return _json(200, body);
  }

  Future<Response> _activate(Request r) async {
    if (!_activateLimit.allow(clientIp(r))) {
      return _json(429, {'ok': false, 'message': '嘗試太多次，請 10 分鐘後再試'});
    }
    final j = await _body(r);
    final platform = '${j['platform'] ?? ''}';
    final res = service.activate(
      input: '${j['code'] ?? ''}',
      deviceId: '${j['device'] ?? ''}',
      report: DeviceReport(
        platform: platform,
        model: '${j['model'] ?? ''}',
        os: '${j['os'] ?? ''}',
        version: '${j['version'] ?? ''}',
        ip: clientIp(r),
        forumUid: (j['forumUid'] as num?)?.toInt(),
        forumName: '${j['forumName'] ?? ''}',
      ),
    );
    if (!res.ok) return _json(400, {'ok': false, 'message': res.message});

    final web = platform == 'web';
    return _json(
      200,
      {
        'ok': true,
        // 網頁版的 token 只放在 HttpOnly cookie，不交給 JS
        if (!web) 'token': res.token,
        'hint': res.code!.hint,
      },
      headers: web
          ? {'set-cookie': _cookie(betaCookie, res.token!, path: '/', maxAge: 365 * 86400, sameSite: 'Lax')}
          : const {},
    );
  }

  Response _unbind(Request r) {
    final ok = service.unbind(betaToken(r));
    return _json(ok ? 200 : 400, {'ok': ok},
        headers: {'set-cookie': _cookie(betaCookie, '', path: '/', maxAge: 0, sameSite: 'Lax')});
  }

  Response _changelog(Request r) => _json(200, {
        'releases': [
          for (final rel in service.store.releases.take(60))
            {
              'version': rel.version,
              'build': rel.build,
              'date': rel.date.toIso8601String(),
              'notes': rel.notes,
            },
        ],
      });

  /// SideStore／AltStore 的「來源」格式：加進 SideStore 之後，它自己會顯示
  /// 新版、一鍵重簽安裝。只列有 iOS 安裝檔的版本。
  Response _source(Request r) {
    final origin = _origin(r);
    final ios = [
      for (final rel in service.store.releases)
        if (rel.iosUrl.isNotEmpty) rel,
    ];
    final icon = '$origin/icons/Icon-1024.png';
    const desc = 'GameMale 論壇的第三方客戶端：看帖、回覆、簽到、私訊、勳章與道具。';
    final latest = ios.isEmpty ? null : ios.first;
    return _json(200, {
      'name': 'GameMale',
      'identifier': 'xyz.852111.gamemale',
      'subtitle': 'GameMale 論壇客戶端',
      'description': desc,
      'iconURL': icon,
      'website': origin,
      'tintColor': '#70A128',
      'apps': [
        {
          'name': 'GameMale',
          'bundleIdentifier': 'com.fengying.gamemale',
          'developerName': 'FengYing',
          'subtitle': 'GameMale 論壇客戶端',
          'localizedDescription': desc,
          'iconURL': icon,
          'tintColor': '#70A128',
          'category': 'social',
          'versions': [
            for (final rel in ios)
              {
                'version': rel.version,
                'buildVersion': '${rel.build}',
                'date': rel.date.toIso8601String(),
                'localizedDescription': rel.notes,
                'downloadURL': rel.iosUrl,
                'size': rel.iosSize,
                'minOSVersion': '15.0',
              },
          ],
          // 舊版 AltStore／SideStore 只認這幾個平鋪欄位
          if (latest != null) ...{
            'version': latest.version,
            'versionDate': latest.date.toIso8601String(),
            'versionDescription': latest.notes,
            'downloadURL': latest.iosUrl,
            'size': latest.iosSize,
          },
        },
      ],
      'news': [],
    });
  }

  // ── 後台 ─────────────────────────────────────────────

  Future<Response> _login(Request r) async {
    if (adminPassword.isEmpty) {
      return _json(503, {'error': '後台沒有設定密碼（GM_ADMIN_PASSWORD）'});
    }
    if (!_loginLimit.allow(clientIp(r))) {
      return _json(429, {'error': '嘗試太多次，請 10 分鐘後再試'});
    }
    final j = await _body(r);
    if (!constantTimeEquals('${j['password'] ?? ''}', adminPassword)) {
      return _json(401, {'error': '密碼不對'});
    }
    final exp = service.now.add(const Duration(days: _adminDays)).millisecondsSinceEpoch ~/ 1000;
    final token = service.signer.sign({'k': 'admin', 'exp': exp});
    return _json(200, {'ok': true}, headers: {
      'set-cookie': _cookie(adminCookie, token,
          path: '/api/admin', maxAge: _adminDays * 86400, sameSite: 'Strict'),
    });
  }

  Response _logout(Request r) => _json(200, {'ok': true}, headers: {
        'set-cookie': _cookie(adminCookie, '', path: '/api/admin', maxAge: 0, sameSite: 'Strict'),
      });

  bool _isAdmin(Request r) {
    final p = service.signer.verify(cookies(r)[adminCookie]);
    if (p == null || p['k'] != 'admin') return false;
    final exp = (p['exp'] as num?)?.toInt() ?? 0;
    return exp > service.now.millisecondsSinceEpoch ~/ 1000;
  }

  /// 後台驗證。會改資料的請求要帶 `X-GM-Admin: 1`：別的網站沒辦法
  /// 讓瀏覽器帶自訂標頭跨站送出（會被 CORS 預檢擋下），加上 SameSite=Strict
  /// 就擋掉了跨站偽造請求。發版腳本用部署金鑰，只開放給發佈版本那一支。
  Handler _auth(Handler h, {bool allowDeploy = false}) => (Request r) async {
        if (allowDeploy && deployToken.isNotEmpty) {
          final auth = r.headers['authorization'] ?? '';
          if (constantTimeEquals(auth, 'Bearer $deployToken')) return h(r);
        }
        if (!_isAdmin(r)) return _json(401, {'error': '請先登入後台'});
        if (r.method != 'GET' && r.headers['x-gm-admin'] != '1') {
          return _json(403, {'error': '缺少後台標頭'});
        }
        return h(r);
      };

  Response _state(Request r) {
    final s = service.store;
    return _json(200, {
      'settings': s.settings.toJson(),
      'codes': [for (final c in s.codes) c.toJson()],
      'releases': [for (final rel in s.releases) rel.toJson()],
      'webBuild': service.webBuild?.call() ?? 0,
      'now': service.now.toIso8601String(),
    });
  }

  Future<Response> _saveSettings(Request r) async {
    final j = await _body(r);
    final s = service.settings;
    if (j['betaRequired'] is bool) s.betaRequired = j['betaRequired'] as bool;
    if (j['maintenance'] is bool) s.maintenance = j['maintenance'] as bool;
    if (j['maintenanceMessage'] is String) {
      s.maintenanceMessage = _clip(j['maintenanceMessage'] as String, 500);
    }
    if (j['minBuild'] is num) s.minBuild = (j['minBuild'] as num).toInt().clamp(0, 1 << 30);
    await service.store.save();
    return _json(200, {'settings': s.toJson()});
  }

  Future<Response> _createCodes(Request r) async {
    final j = await _body(r);
    final created = service.createCodes(
      count: (j['count'] as num?)?.toInt() ?? 1,
      note: '${j['note'] ?? ''}',
      maxDevices: (j['maxDevices'] as num?)?.toInt() ?? 2,
      expiresAt: parseExpiry(j['expiresAt']),
      bypass: j['bypass'] == true,
    );
    return _json(200, {'codes': [for (final c in created) c.toJson()]});
  }

  Future<Response> _updateCode(Request r) async {
    final c = service.store.codeById(r.params['id'] ?? '');
    if (c == null) return _json(404, {'error': '找不到這組碼'});
    final j = await _body(r);
    if (j['note'] is String) c.note = _clip(j['note'] as String, 200);
    if (j['maxDevices'] is num) c.maxDevices = (j['maxDevices'] as num).toInt().clamp(0, 1000);
    if (j.containsKey('expiresAt')) c.expiresAt = parseExpiry(j['expiresAt']);
    if (j['enabled'] is bool) c.enabled = j['enabled'] as bool;
    if (j['bypass'] is bool) c.bypass = j['bypass'] as bool;
    await service.store.save();
    return _json(200, {'code': c.toJson()});
  }

  Future<Response> _deleteCode(Request r) async {
    final s = service.store;
    final before = s.codes.length;
    s.codes.removeWhere((c) => c.id == r.params['id']);
    if (s.codes.length == before) return _json(404, {'error': '找不到這組碼'});
    await s.save();
    return _json(200, {'ok': true});
  }

  Future<Response> _unbindDevice(Request r) async {
    final c = service.store.codeById(r.params['id'] ?? '');
    if (c == null) return _json(404, {'error': '找不到這組碼'});
    c.devices.removeWhere((d) => d.id == r.params['device']);
    await service.store.save();
    return _json(200, {'code': c.toJson()});
  }

  Future<Response> _saveRelease(Request r) async {
    final j = await _body(r);
    final version = '${j['version'] ?? ''}'.trim();
    final build = (j['build'] as num?)?.toInt() ?? 0;
    if (version.isEmpty || build <= 0) {
      return _json(400, {'error': '版本號與 build 號都要填'});
    }
    String url(String k) {
      final v = '${j[k] ?? ''}'.trim();
      return v.startsWith('https://') ? v : '';
    }

    final rel = service.upsertRelease(
      version: version,
      build: build,
      date: DateTime.tryParse('${j['date'] ?? ''}'),
      notes: _clip('${j['notes'] ?? ''}', 8000),
      iosUrl: url('iosUrl'),
      androidUrl: url('androidUrl'),
      iosSize: (j['iosSize'] as num?)?.toInt() ?? 0,
      androidSize: (j['androidSize'] as num?)?.toInt() ?? 0,
    );
    return _json(200, {'release': rel.toJson()});
  }

  Future<Response> _deleteRelease(Request r) async {
    final build = int.tryParse(r.params['build'] ?? '');
    service.store.releases.removeWhere((rel) => rel.build == build);
    await service.store.save();
    return _json(200, {'ok': true});
  }

  // ── 工具 ─────────────────────────────────────────────

  /// 後台填的到期日：`2026-10-31` 算到當天台灣時間 23:59:59；空字串＝不過期
  static DateTime? parseExpiry(Object? v) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty || s == 'null') return null;
    final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (d != null) {
      return DateTime.utc(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!), 15, 59, 59);
    }
    return DateTime.tryParse(s)?.toUtc();
  }

  static Map<String, String> cookies(Request r) {
    final out = <String, String>{};
    for (final part in (r.headers['cookie'] ?? '').split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }

  static String _cookie(String name, String value,
          {required String path, required int maxAge, required String sameSite}) =>
      '$name=$value; Path=$path; Max-Age=$maxAge; HttpOnly; Secure; SameSite=$sameSite';

  /// 對外的網址。Caddy 在前面終結 TLS，所以預設 https
  static String _origin(Request r) {
    final host = r.headers['x-forwarded-host'] ?? r.headers['host'] ?? r.requestedUri.authority;
    final proto = r.headers['x-forwarded-proto'] ??
        (host.startsWith('localhost') || host.startsWith('127.') ? 'http' : 'https');
    return '$proto://$host';
  }

  static Future<Map<String, Object?>> _body(Request r) async {
    try {
      final text = await r.readAsString();
      if (text.length > 64 * 1024) return const {};
      final j = json.decode(text);
      return j is Map ? j.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;

  static Response _json(int status, Object body, {Map<String, String> headers = const {}}) =>
      Response(status, body: json.encode(body), headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ...headers,
      });
}

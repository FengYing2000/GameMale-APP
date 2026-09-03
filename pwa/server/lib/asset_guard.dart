/// `/gmimg` 圖片代理的守門規則。
///
/// 這支代理**不能只開白名單**：帖子裡的圖常常放在第三方圖床
/// （i.imgs.ovh 之類），而那些幾乎都沒送 CORS 標頭。Flutter 網頁版是把圖
/// 讀進 canvas 的，跨網域讀像素會被瀏覽器擋掉，所以第三方圖床的圖只能
/// 由自己這台代抓再同源送出。
///
/// 主機一放開，就得自己補回兩道界線，否則這支等於免費送人一個萬用代理：
///   1. [isPrivateHost]：擋掉會打到內網的位址（SSRF 跳板）
///   2. [isImageType]：回應不是圖片就不轉
library;

import 'dart:io';

/// 會打到內網的主機就不代理。
///
/// 少了這道，任何人都能拿 `/gmimg?u=http://127.0.0.1:8080/...` 當跳板，
/// 探測這台機器上其他只綁 localhost 的服務。
bool isPrivateHost(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (h.isEmpty ||
      h == 'localhost' ||
      h.endsWith('.localhost') ||
      h.endsWith('.internal') ||
      h.endsWith('.local')) {
    return true;
  }

  final ip = InternetAddress.tryParse(h);
  // 不是字面 IP 就是網域名稱。這裡不做 DNS 解析——解析結果跟等一下真正
  // 連線時拿到的未必相同（DNS rebinding），擋不住卻會拖慢每一張圖。
  // 真正的界線是下面的「只回圖片」。
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;

  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 0 || // 0.0.0.0/8
        b[0] == 10 || // 私有
        b[0] == 127 || // 迴環
        (b[0] == 169 && b[1] == 254) || // link-local（雲端 metadata 就在這）
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) || // CGNAT
        b[0] >= 224; // 多播／保留
  }
  // IPv6：::1、fc00::/7（唯一本地）、fe80::/10（link-local）
  if (b.every((x) => x == 0)) return true;
  if ((b[0] & 0xfe) == 0xfc) return true;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true;
  // ::ffff:a.b.c.d 這種包著 IPv4 的寫法，要照 IPv4 的規則再看一次
  if (b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
    return isPrivateHost('${b[12]}.${b[13]}.${b[14]}.${b[15]}');
  }
  return false;
}

/// 回應是不是圖片。少了這道，`/gmimg` 就成了萬用的內容代理。
bool isImageType(String? contentType) =>
    (contentType ?? '').trim().toLowerCase().startsWith('image/');

/// 代理單張圖的大小上限
const int kMaxAssetBytes = 25 * 1024 * 1024;

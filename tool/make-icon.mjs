/**
 * 產生 App 圖示（1024×1024 PNG，無 alpha —— App Store 與 iOS 都要求不透明）。
 * 只用 Node 內建的 zlib 寫 PNG，不依賴任何影像套件，Windows 上也能跑。
 */
import { deflateSync } from 'node:zlib'
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'

const SIZE = 1024
const SS = 3            // 每軸超取樣倍率，用來做邊緣抗鋸齒

/* ── 幾何：有號距離函式，負值代表在形狀內 ── */
const sdRoundRect = (px, py, cx, cy, hw, hh, r) => {
  const qx = Math.abs(px - cx) - (hw - r)
  const qy = Math.abs(py - cy) - (hh - r)
  const ax = Math.max(qx, 0), ay = Math.max(qy, 0)
  return Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - r
}
const sdCircle = (px, py, cx, cy, r) => Math.hypot(px - cx, py - cy) - r
/** 三角形尾巴：三個半平面的交集 */
const sdTriangle = (px, py, a, b, c) => {
  const side = (p, q, r) => (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
  const d1 = side([px, py], a, b), d2 = side([px, py], b, c), d3 = side([px, py], c, a)
  const neg = d1 < 0 || d2 < 0 || d3 < 0
  const pos = d1 > 0 || d2 > 0 || d3 > 0
  return neg && pos ? 1 : -1
}

const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t)

const BG_TOP = [141, 185, 67]     // #8db943
const BG_BOT = [95, 138, 33]      // 比 #70a128 再深一點，對角漸層更立體
const WHITE = [255, 255, 255]

/** 回傳某個取樣點的顏色 */
function shade (x, y) {
  // 背景：左上到右下的對角漸層
  const t = Math.min(1, Math.max(0, (x / SIZE * 0.45 + y / SIZE * 0.55)))
  let col = mix(BG_TOP, BG_BOT, t)

  // 主體對話框
  const bubble = sdRoundRect(x, y, 512, 470, 300, 232, 78)
  const tail = sdTriangle(x, y, [372, 660], [470, 660], [366, 790])
  const inBubble = Math.min(bubble, tail < 0 ? -1 : 1)

  if (inBubble < 0) {
    col = WHITE
    // 框內三個點，用背景色挖回去
    for (const cx of [392, 512, 632]) {
      if (sdCircle(x, y, cx, 470, 40) < 0) col = mix(BG_TOP, BG_BOT, t)
    }
  }
  return col
}

/* ── 逐像素上色（超取樣後平均） ── */
const raw = Buffer.alloc(SIZE * (SIZE * 3 + 1))
let o = 0
for (let y = 0; y < SIZE; y++) {
  raw[o++] = 0                                   // 每列的 filter type
  for (let x = 0; x < SIZE; x++) {
    let r = 0, g = 0, b = 0
    for (let sy = 0; sy < SS; sy++) {
      for (let sx = 0; sx < SS; sx++) {
        const c = shade(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
        r += c[0]; g += c[1]; b += c[2]
      }
    }
    const n = SS * SS
    raw[o++] = Math.round(r / n)
    raw[o++] = Math.round(g / n)
    raw[o++] = Math.round(b / n)
  }
}

/* ── 組 PNG ── */
const CRC_TABLE = (() => {
  const t = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c
  }
  return t
})()
const crc32 = buf => {
  let c = -1
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length)
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body))
  return Buffer.concat([len, body, crc])
}

const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(SIZE, 0)
ihdr.writeUInt32BE(SIZE, 4)
ihdr[8] = 8      // bit depth
ihdr[9] = 2      // color type 2 = truecolour，無 alpha
ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0))
])

const out = resolve(process.argv[2] || 'resources/icon-1024.png')
mkdirSync(dirname(out), { recursive: true })
writeFileSync(out, png)
console.log(`圖示已產生：${out}  (${(png.length / 1024).toFixed(1)} KB)`)

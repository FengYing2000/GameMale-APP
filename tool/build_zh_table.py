# -*- coding: utf-8 -*-
"""產生 assets/s2t.json（簡→繁，台灣用語）。

一對一的字沒有判斷空間，機械對應即可；會轉錯的部分全部寫在 zh_rules.py，
規則改完跑這支重新產生。

用法：python tool/build_zh_table.py
"""
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zh_rules import EXCLUDE, CHAR, DISAMBIGUATE, TAIWAN  # noqa: E402

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'assets', 's2t.json')


def load_pairs(fn):
    """讀 `簡體<TAB>繁體候選1 候選2 …` 格式"""
    out = {}
    for line in io.open(os.path.join(BASE, fn), encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) < 2:
            continue
        out[parts[0]] = parts[1].split(' ')
    return out


def main():
    raw_chars = load_pairs('chars.txt')
    tw_variants = {k: v[0] for k, v in load_pairs('tw_variants.txt').items()}

    chars = {}
    ambiguous = 0
    for simp, cands in raw_chars.items():
        if simp in EXCLUDE:
            continue                       # 完全不轉
        if len(cands) > 1:
            ambiguous += 1
        pick = CHAR.get(simp, cands[0])    # 有指定就用指定的
        pick = ''.join(tw_variants.get(c, c) for c in pick)
        if pick != simp:
            chars[simp] = pick

    def by_char(s):
        return ''.join(chars.get(c, c) for c in s)

    # 詞表只留「逐字轉會不一樣」的，其餘是冗餘。
    # 消歧義與台灣用語分開存 —— 前者是正確性（这里→這裡），後者是換詞
    # （软件→軟體），換詞會讓帖子標題跟論壇原文對不起來，所以要能關掉。
    def trim(d):
        return {src: dst for src, dst in d.items() if by_char(src) != dst}

    phrases = trim(DISAMBIGUATE)
    taiwan = {src: dst for src, dst in trim(TAIWAN).items()
              if src not in phrases}

    io.open(OUT, 'w', encoding='utf-8').write(
        json.dumps({'chars': chars, 'phrases': phrases, 'taiwan': taiwan},
                   ensure_ascii=False, separators=(',', ':')))

    print('單字表   : %d（其中一對多 %d 個由 zh_rules.CHAR 決定）' % (len(chars), ambiguous))
    print('排除轉換 : %d 個字 → %s' % (len(EXCLUDE), ' '.join(sorted(EXCLUDE))))
    print('消歧義詞 : %d 條（原始 %d）' % (len(phrases), len(DISAMBIGUATE)))
    print('台灣用語 : %d 條（原始 %d，可在 App 設定裡關掉）'
          % (len(taiwan), len(TAIWAN)))
    print('輸出     : %s (%d KB)' % (OUT, os.path.getsize(OUT) // 1024))


if __name__ == '__main__':
    main()

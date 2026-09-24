#!/usr/bin/env python3
"""發佈一個版本：CI 建好的 IPA／APK 放到公開的 GameMale-Releases，並登記到控制台。

公開 repo 只放安裝檔、不放程式碼；App 的「檢查更新」與 SideStore 來源讀的是
852111.xyz 控制台登記的網址，所以兩邊都要做。

流程（在 repo 根目錄）：
  1. pubspec.yaml 改版本、CHANGELOG.md 寫這一版的更新內容 → commit → push
  2. git tag v1.29.0 && git push origin v1.29.0     ← 觸發 iOS 與 Android 建置
  3. python tool/publish_release.py                  ← 會等兩個建置跑完

需要：
  * gh 登入過 FengYing2000（不必是使用中的帳號，腳本自己拿它的 token）
  * 部署金鑰：環境變數 GM_DEPLOY_TOKEN，或 tool/.deploy_token（已在 .gitignore）

選項：
  --no-register   只上傳安裝檔，不登記到控制台
  --dry-run       只印出會做什麼
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SOURCE_REPO = 'FengYing2000/GameMale-APP'
RELEASES_REPO = 'FengYing2000/GameMale-Releases'
CONTROL = 'https://852111.xyz'
ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = {
    'ios': ('建置 iOS IPA', 'GameMale-unsigned-ipa', 'GameMale.ipa'),
    'android': ('建置 Android APK', 'GameMale-apk', 'GameMale.apk'),
}

# Windows 主控台預設 cp950，印中文會炸
for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding='utf-8')
    except Exception:
        pass


def sh(*args, env=None, capture=True):
    r = subprocess.run(args, env=env, cwd=ROOT, capture_output=capture, text=True, encoding='utf-8')
    if r.returncode != 0:
        raise SystemExit(f'失敗：{" ".join(args)}\n{r.stderr or r.stdout}')
    return (r.stdout or '').strip()


def pubspec_version():
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    m = re.search(r'^version:\s*([\d.]+)\+(\d+)', text, re.M)
    if not m:
        raise SystemExit('pubspec.yaml 讀不到 version')
    return m.group(1), int(m.group(2))


def changelog_notes(version):
    text = (ROOT / 'CHANGELOG.md').read_text(encoding='utf-8')
    m = re.search(rf'^##\s*{re.escape(version)}\b[^\n]*\n(.*?)(?=^##\s|\Z)', text, re.M | re.S)
    if not m or not m.group(1).strip():
        raise SystemExit(f'CHANGELOG.md 沒有 {version} 這一節的內容')
    return m.group(1).strip()


def deploy_token():
    t = os.environ.get('GM_DEPLOY_TOKEN', '').strip()
    f = ROOT / 'tool' / '.deploy_token'
    if not t and f.exists():
        t = f.read_text(encoding='utf-8').strip()
    return t


def wait_runs(sha, env):
    """同一個 commit 的 iOS 與 Android 建置，等到都成功"""
    deadline = time.time() + 45 * 60
    while True:
        runs = json.loads(sh('gh', 'run', 'list', '--repo', SOURCE_REPO, '--commit', sha,
                             '--json', 'databaseId,workflowName,status,conclusion,createdAt',
                             '--limit', '20', env=env))
        found, pending = {}, []
        for key, (name, _, _) in WORKFLOWS.items():
            mine = sorted((r for r in runs if r['workflowName'] == name),
                          key=lambda r: r['createdAt'], reverse=True)
            ok = next((r for r in mine if r['conclusion'] == 'success'), None)
            if ok:
                found[key] = ok['databaseId']
            elif mine and mine[0]['status'] != 'completed':
                pending.append(name)
            else:
                state = mine[0]['conclusion'] if mine else '找不到'
                raise SystemExit(f'{name}：{state}。有推 v 標籤嗎？失敗的話修好重推標籤。')
        if not pending:
            return found
        if time.time() > deadline:
            raise SystemExit('等太久了：' + '、'.join(pending))
        print('等待建置：' + '、'.join(pending) + '…', flush=True)
        time.sleep(30)


def main():
    dry = '--dry-run' in sys.argv
    register = '--no-register' not in sys.argv
    version, build = pubspec_version()
    tag = f'v{version}'
    notes = changelog_notes(version)
    token = deploy_token()
    if register and not token:
        raise SystemExit('沒有部署金鑰：設 GM_DEPLOY_TOKEN 或建立 tool/.deploy_token')

    env = dict(os.environ)
    env['GH_TOKEN'] = sh('gh', 'auth', 'token', '--user', 'FengYing2000')
    sha = sh('git', 'rev-list', '-n', '1', tag)
    print(f'發佈 {version}（build {build}），標籤 {tag} → {sha[:7]}')
    print('更新內容：\n' + notes + '\n')
    if dry:
        return

    runs = wait_runs(sha, env)
    urls, sizes = {}, {}
    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for key, (_, artifact, filename) in WORKFLOWS.items():
            d = Path(tmp) / key
            sh('gh', 'run', 'download', str(runs[key]), '--repo', SOURCE_REPO,
               '-n', artifact, '-D', str(d), env=env)
            ext = filename.rsplit('.', 1)[1]
            out = Path(tmp) / f'GameMale-{version}.{ext}'
            (d / filename).rename(out)
            files.append(str(out))
            sizes[key] = out.stat().st_size
            urls[key] = f'https://github.com/{RELEASES_REPO}/releases/download/{tag}/{out.name}'

        notes_file = Path(tmp) / 'notes.md'
        notes_file.write_text(notes, encoding='utf-8')
        exists = subprocess.run(['gh', 'release', 'view', tag, '--repo', RELEASES_REPO],
                                env=env, capture_output=True).returncode == 0
        if exists:
            sh('gh', 'release', 'upload', tag, *files, '--repo', RELEASES_REPO, '--clobber', env=env)
            sh('gh', 'release', 'edit', tag, '--repo', RELEASES_REPO,
               '--notes-file', str(notes_file), env=env)
        else:
            sh('gh', 'release', 'create', tag, *files, '--repo', RELEASES_REPO,
               '--title', f'GameMale {version}', '--notes-file', str(notes_file), env=env)
    print(f'已上傳到 https://github.com/{RELEASES_REPO}/releases/tag/{tag}')

    if not register:
        return
    body = json.dumps({
        'version': version,
        'build': build,
        'date': datetime.now(timezone.utc).isoformat(),
        'notes': notes,
        'iosUrl': urls['ios'],
        'androidUrl': urls['android'],
        'iosSize': sizes['ios'],
        'androidSize': sizes['android'],
    }).encode('utf-8')
    req = urllib.request.Request(f'{CONTROL}/api/admin/releases', data=body, method='POST', headers={
        'content-type': 'application/json',
        'authorization': f'Bearer {token}',
    })
    with urllib.request.urlopen(req, timeout=30) as res:
        if res.status != 200:
            raise SystemExit(f'登記失敗：HTTP {res.status}')
    print('已登記到控制台，App 的檢查更新與 SideStore 來源會看到這一版')


if __name__ == '__main__':
    main()

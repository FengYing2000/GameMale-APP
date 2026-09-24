"""部署 GameMale 網頁版＋控制台到香港 VPS（/opt/stacks/gamemale-pwa，非 git repo）。

先在本機 `flutter build web --wasm --release --pwa-strategy=none`，再：
  VPS_PASS=… python tool/deploy_pwa.py

上傳 build/web（先清空再解壓，tar 是疊加的）、packages/gm_api、pwa/server、
Dockerfile 與 compose，再 docker compose build（內含 dart analyze && dart test）&& up -d。
build 失敗會中止（pipefail），不會默默跑舊映像。

VPS 密碼只從環境變數讀。第一次部署（VPS 上還沒有 .env）時，會用環境變數
GM_ADMIN_PASSWORD／GM_DEPLOY_TOKEN 建立 .env；之後不覆蓋。
"""
import io
import os
import sys
import tarfile

import paramiko

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REMOTE = "/opt/stacks/gamemale-pwa"
SKIP = {".dart_tool", "build", ".packages"}


def tar_of(pairs):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for local, arc in pairs:
            def filt(ti):
                parts = ti.name.replace("\\", "/").split("/")
                return None if any(p in SKIP for p in parts[1:]) else ti
            t.add(local, arcname=arc, filter=filt)
    buf.seek(0)
    return buf


def run(ssh, cmd):
    print(f"$ {cmd}", flush=True)
    _, out, err = ssh.exec_command(cmd, get_pty=True)
    for line in iter(out.readline, ""):
        sys.stdout.write(line)
    code = out.channel.recv_exit_status()
    if code != 0:
        raise SystemExit(f"exit {code}: {cmd}")


def main():
    pw = os.environ.get("VPS_PASS")
    if not pw:
        raise SystemExit("VPS_PASS not set")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect("160.236.111.8", username="root", password=pw, timeout=20)
    sftp = ssh.open_sftp()

    web = tar_of([(os.path.join(ROOT, "build", "web"), "web")])
    src = tar_of([
        (os.path.join(ROOT, "packages", "gm_api", "lib"), "packages/gm_api/lib"),
        (os.path.join(ROOT, "packages", "gm_api", "pubspec.yaml"), "packages/gm_api/pubspec.yaml"),
        (os.path.join(ROOT, "pwa", "server"), "pwa/server"),
        (os.path.join(ROOT, "pwa", "Dockerfile"), "pwa/Dockerfile"),
        (os.path.join(ROOT, "docker-compose.yml"), "docker-compose.yml"),
        (os.path.join(ROOT, ".dockerignore"), ".dockerignore"),
    ])
    sftp.putfo(web, "/tmp/gm_web.tgz")
    sftp.putfo(src, "/tmp/gm_src.tgz")

    # 控制台的機密只在第一次建立 .env；之後部署不覆蓋（改密碼直接改 VPS 上的檔）
    admin_pw = os.environ.get("GM_ADMIN_PASSWORD", "")
    deploy = os.environ.get("GM_DEPLOY_TOKEN", "")
    try:
        sftp.stat(f"{REMOTE}/.env")
        print(".env 已存在，不覆蓋")
    except FileNotFoundError:
        if admin_pw and deploy:
            sftp.putfo(io.BytesIO(f"GM_ADMIN_PASSWORD={admin_pw}\nGM_DEPLOY_TOKEN={deploy}\n".encode()),
                       f"{REMOTE}/.env")
            sftp.chmod(f"{REMOTE}/.env", 0o600)
            print("已建立 .env")
    sftp.close()
    run(ssh, f"mkdir -p {REMOTE}/data && chmod 700 {REMOTE}/data")

    run(ssh, f"cd {REMOTE} && rm -rf build/web packages/gm_api/lib && mkdir -p build "
             f"&& tar xzf /tmp/gm_web.tgz -C build && tar xzf /tmp/gm_src.tgz -C . "
             f"&& rm -f /tmp/gm_web.tgz /tmp/gm_src.tgz && cat build/web/version.json")
    # pipefail：不然結束碼是 tail 的，build 失敗照樣 up 舊映像
    run(ssh, f"bash -o pipefail -c 'cd {REMOTE} && docker compose build --progress plain 2>&1 "
             f"| tail -15' && cd {REMOTE} && docker compose up -d 2>&1 | tail -3")
    ssh.close()


if __name__ == "__main__":
    main()

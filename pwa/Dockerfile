# ⚠️ build context 是**專案根目錄**，不是 pwa/。
# 伺服器透過 path 依賴共用 packages/gm_api（跟 Flutter App 同一套論壇解析），
# 那個資料夾在 pwa/ 外面，context 設在 pwa/ 會 pub get 失敗。
# compose 裡是 `context: ..` + `dockerfile: pwa/Dockerfile`。
FROM dart:stable AS build
WORKDIR /src

# 先只放 pubspec，這樣改原始碼不會把相依套件的快取層打掉
COPY packages/gm_api/pubspec.yaml packages/gm_api/
COPY pwa/server/pubspec.yaml pwa/server/pubspec.lock pwa/server/
WORKDIR /src/pwa/server
RUN dart pub get

WORKDIR /src
COPY packages/gm_api packages/gm_api
COPY pwa/server pwa/server
WORKDIR /src/pwa/server
RUN dart pub get --offline \
 && dart analyze \
 && dart test \
 && dart compile exe bin/server.dart -o /src/gm_server

FROM debian:bookworm-slim
# ca-certificates：連 push service 的 HTTPS 要用
# tzdata：沒有它 TZ 設了也沒用，通知時間會差 8 小時
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/gm_server /usr/local/bin/gm_server
COPY pwa/web/ /srv/web/
# 簡繁轉換表，通知文字要用；讀不到的話會原樣輸出簡體，不會掛
COPY assets/s2t.json /srv/assets/s2t.json
ENV WEB_ROOT=/srv/web \
    DATA_FILE=/data/subs.json \
    ASSET_DIR=/srv/assets \
    TZ=Asia/Taipei \
    PORT=8080
EXPOSE 8080
VOLUME /data
CMD ["gm_server"]

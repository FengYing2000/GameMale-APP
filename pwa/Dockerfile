# ⚠️ build context 是**專案根目錄**，不是 pwa/。
# 伺服器透過 path 依賴共用 packages/gm_api（跟 Flutter App 同一套論壇解析），
# 那個資料夾在 pwa/ 外面，context 設在 pwa/ 會 pub get 失敗。
# compose 裡是 `context: .` + `dockerfile: pwa/Dockerfile`。
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
# ca-certificates：轉發論壇與抓圖的 HTTPS 要用
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/gm_server /usr/local/bin/gm_server
# Flutter 網頁版（先在本機 flutter build web 產好再一起送上來）。
# 不在映像裡編：那要整包 Flutter SDK，映像會肥好幾 GB。
COPY build/web/ /srv/app/
ENV APP_ROOT=/srv/app \
    TZ=Asia/Taipei \
    PORT=8080
EXPOSE 8080
CMD ["gm_server"]

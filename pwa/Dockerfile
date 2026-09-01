# 編譯成單一原生執行檔，跑起來不需要 Dart runtime
FROM dart:stable AS build
WORKDIR /app
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/ ./
RUN dart pub get --offline \
 && dart analyze \
 && dart test \
 && dart compile exe bin/server.dart -o /app/gm_server

FROM debian:bookworm-slim
# 要 ca-certificates 才連得上 push service 的 HTTPS
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/gm_server /usr/local/bin/gm_server
COPY web/ /srv/web/
ENV WEB_ROOT=/srv/web \
    DATA_FILE=/data/subs.json \
    PORT=8080
EXPOSE 8080
VOLUME /data
CMD ["gm_server"]

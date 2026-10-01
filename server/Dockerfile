# Backend image: compiles bin/serve.dart ahead of time and runs it as an
# unprivileged user. See deploy/README.md for how it is run in production.

FROM dart:stable AS build
WORKDIR /src
COPY pubspec.yaml ./
RUN dart pub get
COPY . .
# `dart build cli` (not `dart compile exe`) runs the sqlite3 package's build
# hook, which bundles the native SQLite library next to the executable.
RUN dart pub get --offline \
    && dart build cli --target bin/serve.dart --output /out

FROM debian:stable-slim
# ca-certificates: the probes call HTTPS APIs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --no-create-home --home-dir /app --shell /usr/sbin/nologin monitor \
    && mkdir -p /data \
    && chown monitor /data
COPY --from=build /out/bundle /app
WORKDIR /app
USER monitor

# Listen on the container network (the reverse proxy is the only thing that
# reaches it); serve.dart refuses this without API_TOKEN.
ENV HOST=0.0.0.0 \
    PORT=8080 \
    DB_PATH=/data/probes.db
EXPOSE 8080
VOLUME /data
CMD ["/app/bin/serve"]

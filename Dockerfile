# Exact Elixir 1.20.4 / OTP 29.1.1, verified against the image's release metadata.
FROM hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim@sha256:037687742ae12c329b59a681a230d62ef3ddd555c0275e577ce41c61539e5248 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile --warnings-as-errors && mix assets.setup && mix assets.deploy

COPY config/runtime.exs config/runtime.exs
COPY rel rel
RUN mix release

FROM debian:bookworm-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libstdc++6 libncurses6 libtinfo6 libssl3 libodbc1 libsctp1 locales \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true PORT=4000
COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/choreocal ./
USER nobody
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl --fail --silent --output /dev/null "http://127.0.0.1:${PORT}/health" || exit 1
CMD ["/app/bin/server"]

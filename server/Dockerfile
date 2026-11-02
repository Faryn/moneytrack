ARG BUILDER_IMAGE=elixir:1.20.4-otp-29-slim@sha256:6245171c91cf90808437f203f22856738d0095d310f4f9030219e53111823ff8
ARG RUNNER_IMAGE=debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
FROM ${BUILDER_IMAGE} AS builder
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV MIX_ENV=prod ERL_FLAGS="+S 2:2 +A 4" MAKEFLAGS=-j2
WORKDIR /build
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.setup && mix compile --warnings-as-errors && mix assets.deploy
COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE} AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 libncurses6 openssl ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10100 moneytrack \
    && useradd --uid 10100 --gid 10100 --no-create-home --home-dir /tmp moneytrack
WORKDIR /app
COPY --from=builder --chown=10100:10100 /build/_build/prod/rel/moneytrack ./
ARG VCS_REF=unknown
LABEL org.opencontainers.image.revision=${VCS_REF}
ENV PHX_SERVER=true PORT=4018 HOME=/tmp LANG=C.UTF-8 \
    ERL_FLAGS="+S 2:2 +A 4" RELEASE_DISTRIBUTION=none
USER 10100:10100
CMD ["/app/bin/moneytrack", "start"]

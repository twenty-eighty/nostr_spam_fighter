ARG ELIXIR_VERSION=1.20.3
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=bookworm-20260824-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build

RUN apt-get update -y && apt-get install -y build-essential git curl && apt-get clean && rm -f /var/lib/apt/lists/*_*

# rustler / nostr_elixir
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod && mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

RUN chmod +x rel/overlays/bin/*

# Colocated CSS/JS is written under _build during compile; assets must run after.
RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:${DEBIAN_VERSION}

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod
ENV PHX_SERVER=true
# Override with ERL_FLAGS at runtime if the instance is larger than 512 MB.
ENV ERL_FLAGS="+S 2:2 +sbwt none +sbwtdcpu none +sbwtdio none"

COPY --from=build --chown=nobody:root /app/_build/prod/rel/nostr_spam_fighter ./

USER nobody

CMD ["/app/bin/server"]

FROM rust:1.98.1-bookworm AS builder
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --release --locked

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
COPY --from=builder /build/target/release/smartkeys-community-server /usr/local/bin/smartkeys-community-server
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/smartkeys-community-server"]

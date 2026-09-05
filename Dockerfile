# ════════════════════════════════════════════════════════════════════
#  Bantu FS & Power Demo — Multi-stage Dockerfile
#
#  Stage 1: build the Bantu interpreter v1.3.0 from source
#           (Ubuntu 22.04 base ⇒ ABI-compatible with the runtime image)
#  Stage 2: runtime image — bantu binary + our app + libc + curl
# ════════════════════════════════════════════════════════════════════

# ─── Stage 1: Builder ──────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Build tools + dev headers for SQLite, libcurl, and libffi (for FFI builtins).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        g++ \
        gcc \
        make \
        binutils \
        file \
        libsqlite3-dev \
        libcurl4-openssl-dev \
        libffi-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy the Bantu interpreter source tree (vendored in this repo)
COPY bantu-src/compiler/ /build/compiler/

# Build Bantu inside Ubuntu 22.04 — guaranteed ABI compatibility.
RUN cd /build/compiler \
    && chmod +x build.sh \
    && ./build.sh

# Verify the binary exists and is a Linux executable.
RUN test -f /build/compiler/build/bantu \
    && file /build/compiler/build/bantu \
    && cp /build/compiler/build/bantu /build/bantu \
    && chmod +x /build/bantu

# ─── Stage 2: Runtime ──────────────────────────────────────────────
FROM ubuntu:22.04

# Avoid tzdata / interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Runtime libraries the Bantu binary needs:
#   - libsqlite3-0  → SQLite runtime
#   - libcurl4       → HTTP client runtime (OpenSSL flavor)
#   - libffi8        → FFI runtime (loadlib/func builtins)
#   - ca-certificates → TLS roots for HTTPS
#   - coreutils + procps → `ls`, `stat`, `uname`, `uptime`, `hostname`,
#     `whoami`, `cat`, `head`, `grep`, `df` — used by the demo endpoints
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        ca-certificates \
        libcurl4 \
        libffi8 \
        coreutils \
        procps \
        net-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the freshly-built Bantu binary from the builder stage
COPY --from=builder /build/bantu /usr/local/bin/bantu
RUN chmod +x /usr/local/bin/bantu

# Copy the Bantu application (backend + static frontend + standard library)
COPY server.b /app/server.b
COPY public/  /app/public/
COPY lib/     /app/lib/

# Create the workspace directory where file-system demos will create files.
# World-writable so the bantu process can write regardless of UID Render uses.
RUN mkdir -p /app/workspace && chmod 777 /app/workspace

# Default port (Render injects $PORT; we honor it)
ENV PORT=8080
ENV WORKSPACE=/app/workspace
EXPOSE 8080

# Pre-flight check: verify the binary can actually start.
RUN echo "=== Bantu binary pre-flight ===" \
    && ldd /usr/local/bin/bantu \
    && /usr/local/bin/bantu --version

# Run the Bantu interpreter on server.b.
# Bantu's sua.server.listen($PORT) blocks forever, accepting HTTP.
CMD ["bantu", "run", "server.b"]

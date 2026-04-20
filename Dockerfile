# ─────────────────────────────────────────────
# Stage 1: 下载预编译 llama-server
# ─────────────────────────────────────────────
FROM debian:bookworm-slim AS downloader

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG LLAMA_VERSION=v1.3.1

# 下载预编译的 llama-server
RUN case "${TARGETARCH}" in \
    amd64) ARCH="x64" ;; \
    arm64) ARCH="arm64" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && curl -sL "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/llama-server-${ARCH}-linux-${TARGETARCH}.zip" \
    -o /tmp/llama-server.zip \
    && unzip -j /tmp/llama-server.zip "llama-server-${ARCH}-linux-${TARGETARCH}" -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/llama-server \
    && rm /tmp/llama-server.zip \
    && llama-server --version


# ─────────────────────────────────────────────
# Stage 2: 运行时镜像（极简 ~120MB）
# ─────────────────────────────────────────────
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# 运行时依赖：OpenBLAS + gcc 运行时
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenblas0 \
    libgomp1 \
    libstdc++6 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=downloader /usr/local/bin/llama-server /usr/local/bin/llama-server
COPY entrypoint.sh /entrypoint.sh
COPY models/ /models/

RUN chmod +x /usr/local/bin/llama-server /entrypoint.sh

# 默认参数，可通过 -e 覆盖
ENV LLAMA_HOST=0.0.0.0
ENV LLAMA_PORT=8080
ENV LLAMA_CTX_SIZE=2048
ENV LLAMA_THREADS=4
ENV LLAMA_BATCH_SIZE=256
ENV LLAMA_UBATCH_SIZE=128
ENV LLAMA_MODEL=/models/PaddleOCR-VL-1.5.gguf
ENV LLAMA_MMPROJ=/models/PaddleOCR-VL-1.5-mmproj.gguf

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

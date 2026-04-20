# ─────────────────────────────────────────────
# Stage 1: 下载 llama-server 和模型
# ─────────────────────────────────────────────
FROM debian:bookworm-slim AS downloader

ENV DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# 下载 llama-server
ARG LLAMA_VERSION=v1.3.1
RUN case "${TARGETARCH}" in \
    amd64) ARCH="x64" ;; \
    arm64) ARCH="arm64" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && echo "Downloading llama-server-${ARCH}..." \
    && curl -sL -f \
    "https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/llama-server-${ARCH}-linux-${TARGETARCH}.zip" \
    -o /tmp/llama-server.zip \
    && unzip -j /tmp/llama-server.zip "llama-server-${ARCH}-linux-${TARGETARCH}" -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/llama-server \
    && rm /tmp/llama-server.zip \
    && /usr/local/bin/llama-server --version

# 下载模型文件
ARG HF_TOKEN
ENV HF_TOKEN=${HF_TOKEN}
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip install -q huggingface-hub \
    && mkdir -p /models \
    && echo "Downloading PaddleOCR-VL-1.5.gguf..." \
    && huggingface-cli download PaddlePaddle/PaddleOCR-VL-1.5-GGUF PaddleOCR-VL-1.5.gguf \
        --token ${HF_TOKEN} \
        --local-dir /models \
        --local-dir-use-symlinks False \
    && echo "Downloading PaddleOCR-VL-1.5-mmproj.gguf..." \
    && huggingface-cli download PaddlePaddle/PaddleOCR-VL-1.5-GGUF PaddleOCR-VL-1.5-mmproj.gguf \
        --token ${HF_TOKEN} \
        --local-dir /models \
        --local-dir-use-symlinks False \
    && ls -lh /models/


# ─────────────────────────────────────────────
# Stage 2: 运行时镜像（极简）
# ─────────────────────────────────────────────
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# 运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    libopenblas0 \
    libgomp1 \
    libstdc++6 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=downloader /usr/local/bin/llama-server /usr/local/bin/llama-server
COPY --from=downloader /models/ /models/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/llama-server /entrypoint.sh

# 默认参数
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

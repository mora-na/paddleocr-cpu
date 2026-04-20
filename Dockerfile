# ─────────────────────────────────────────────
# Stage 1: 编译 llama-server
# ─────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git \
    libopenblas-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git /build

RUN cmake -B /build/build /build \
    -DGGML_BLAS=ON \
    -DGGML_BLAS_VENDOR=OpenBLAS \
    -DGGML_AVX2=ON \
    -DGGML_FMA=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_CUDA=OFF \
    -DGGML_METAL=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /build/build \
    --target llama-server \
    --config Release \
    -j$(nproc)


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

COPY --from=builder /build/build/bin/llama-server /usr/local/bin/llama-server
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

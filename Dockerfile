# ─────────────────────────────────────────────
# Stage 1: 编译 llama-server
# ─────────────────────────────────────────────
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git \
    libopenblas-dev pkg-config ca-certificates \
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
# Stage 2: 安装 Python 依赖
# ─────────────────────────────────────────────
FROM ubuntu:22.04 AS pybuilder

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3-pip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python3.10 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip \
    && pip install paddlepaddle==3.2.1 \
       -i https://www.paddlepaddle.org.cn/packages/stable/cpu/ \
       --trusted-host www.paddlepaddle.org.cn \
    && pip install "paddleocr[doc-parser]"


# ─────────────────────────────────────────────
# Stage 3: 最终运行时镜像
# ─────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/venv/bin:$PATH"

# 仅保留运行时必要的共享库
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    libopenblas0 \
    libgomp1 \
    libstdc++6 \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder  /build/build/bin/llama-server /usr/local/bin/llama-server
COPY --from=pybuilder /opt/venv /opt/venv
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/llama-server /entrypoint.sh \
    && mkdir -p /models /tmp/paddle_cache

# 默认参数，全部可通过 -e 覆盖
ENV LLAMA_HOST=0.0.0.0
ENV LLAMA_PORT=8080
ENV LLAMA_CTX_SIZE=2048
ENV LLAMA_THREADS=4
ENV LLAMA_BATCH_SIZE=256
ENV LLAMA_UBATCH_SIZE=128
ENV LLAMA_MODEL=/models/PaddleOCR-VL-1.5.gguf
ENV LLAMA_MMPROJ=/models/PaddleOCR-VL-1.5-mmproj.gguf

# PaddlePaddle 静默 + 节省内存
ENV PADDLE_CPP_LOG_LEVEL=3
ENV FLAGS_mkldnn_cache_capacity=0
ENV HOME=/tmp
ENV PADDLEOCR_HOME=/tmp/paddle_cache

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -sf http://localhost:8080/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

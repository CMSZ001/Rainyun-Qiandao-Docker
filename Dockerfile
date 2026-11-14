# 构建期：下载 Chrome + 同版本 ChromeDriver、安装 Python 依赖
# 构建工具（curl/unzip/jq）与压缩包都留在本阶段，不进最终镜像
FROM python:3.9-slim AS builder

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

SHELL ["/bin/bash", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl unzip jq; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
        amd64) PLATFORM=linux64 ;; \
        arm64) PLATFORM=linux-arm64 ;; \
        *) echo "不支持的架构: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    CFTS=$(curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json); \
    CHROME_URL=$(echo "$CFTS" | jq -r --arg p "$PLATFORM" '.channels.Stable.downloads.chrome[] | select(.platform == $p) | .url'); \
    DRIVER_URL=$(echo "$CFTS" | jq -r --arg p "$PLATFORM" '.channels.Stable.downloads.chromedriver[] | select(.platform == $p) | .url'); \
    curl -fsSL -o /tmp/chrome.zip "$CHROME_URL"; \
    unzip -q -o /tmp/chrome.zip -d /opt; \
    mv "/opt/chrome-${PLATFORM}" /opt/chrome; \
    curl -fsSL -o /tmp/cd.zip "$DRIVER_URL"; \
    unzip -q -o /tmp/cd.zip -d /tmp; \
    mv "/tmp/chromedriver-${PLATFORM}/chromedriver" /opt/chromedriver; \
    chmod +x /opt/chrome/chrome /opt/chromedriver; \
    [ -d /opt/chrome/locales ] && find /opt/chrome/locales -type f ! -name 'en-US.pak' -delete || true; \
    rm -rf /opt/chrome/hyphen-data /opt/chrome/ABOUT /opt/chrome/deb.deps /opt/chrome/rpm.deps \
           /tmp/* /var/lib/apt/lists/* /var/cache/apt/*

COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm -rf /tmp/requirements.txt \
    && find /usr/local/lib/python3.9/site-packages -name '__pycache__' -prune -exec rm -rf {} +

# 运行期：只装 Chrome 的共享库依赖（取自其官方 deb.deps），不带任何构建工具
FROM python:3.9-slim

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    PIP_NO_CACHE_DIR=1 \
    LINUX_MODE=true \
    HEADLESS=true \
    DEBUG=false \
    MAX_WORKERS=2 \
    MAX_RETRIES=1 \
    CHROMEDRIVER_PATH=/usr/bin/chromedriver

SHELL ["/bin/bash", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates fonts-liberation tzdata \
        libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 \
        libcurl4 libdbus-1-3 libdrm2 libexpat1 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 \
        libnss3 libpango-1.0-0 libudev1 libvulkan1 libx11-6 libxcb1 libxcomposite1 \
        libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libxss1; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /usr/share/doc/* /usr/share/man/* /usr/share/locale/*; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    python -c 'import time; print("tz:", time.strftime("%Z %z"))'

COPY --from=builder /opt/chrome /opt/chrome
COPY --from=builder /opt/chromedriver /usr/bin/chromedriver
COPY --from=builder /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages

# rainyun.py 只认 /usr/bin/chromedriver，且不设 binary_location，ChromeDriver 会按 PATH
# 找 google-chrome / google-chrome-stable
# Chrome 的共享库只装在 final 阶段，故版本断言必须放在这里而不是 builder
RUN set -eux; \
    ln -sf /opt/chrome/chrome /usr/local/bin/google-chrome; \
    ln -sf /opt/chrome/chrome /usr/local/bin/google-chrome-stable; \
    CHROME_VER=$(google-chrome --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'); \
    DRIVER_VER=$(chromedriver --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'); \
    test "${CHROME_VER%%.*}" = "${DRIVER_VER%%.*}" || { echo "Chrome 与 ChromeDriver 主版本不一致: $CHROME_VER vs $DRIVER_VER" >&2; exit 1; }; \
    echo "Chrome $CHROME_VER / ChromeDriver $DRIVER_VER"; \
    python -c 'import cv2, selenium, requests; print("deps ok")'

WORKDIR /app

COPY rainyun.py notify.py ICR.py stealth.min.js ./

CMD ["python", "rainyun.py"]

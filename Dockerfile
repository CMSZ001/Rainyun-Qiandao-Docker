FROM python:3.9-slim

ARG TARGETARCH

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    LINUX_MODE=true \
    HEADLESS=true \
    DEBUG=false \
    MAX_WORKERS=2 \
    MAX_RETRIES=1 \
    CHROMEDRIVER_PATH=/usr/bin/chromedriver

SHELL ["/bin/bash", "-c"]

# Google 的 apt 源只发 amd64 的 Chrome deb，但 Chrome for Testing 提供两个架构的
# 官方 Chrome 构建（同版本号），故统一从 CfT 取 Chrome + ChromeDriver。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip jq \
        libasound2 libatk-bridge2.0-0 libatk1.0-0 libcairo2 libcups2 libdbus-1-3 \
        libdrm2 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 \
        libu2f-udev libvulkan1 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
        libxfixes3 libxkbcommon0 libxrandr2 libxss1 fonts-liberation xdg-utils; \
    ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$ARCH" in \
        amd64) PLATFORM=linux64 ;; \
        arm64) PLATFORM=linux-arm64 ;; \
        *) echo "不支持的架构: $ARCH" >&2; exit 1 ;; \
    esac; \
    CFTS=$(curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json); \
    CHROME_URL=$(echo "$CFTS" | jq -r --arg p "$PLATFORM" '.channels.Stable.downloads.chrome[] | select(.platform == $p) | .url'); \
    DRIVER_URL=$(echo "$CFTS" | jq -r --arg p "$PLATFORM" '.channels.Stable.downloads.chromedriver[] | select(.platform == $p) | .url'); \
    curl -fsSL -o /tmp/chrome.zip "$CHROME_URL"; \
    unzip -q -o /tmp/chrome.zip -d /opt; \
    mv "/opt/chrome-${PLATFORM}" /opt/chrome; \
    ln -sf /opt/chrome/chrome /usr/local/bin/google-chrome; \
    ln -sf /opt/chrome/chrome /usr/local/bin/google-chrome-stable; \
    curl -fsSL -o /tmp/chromedriver.zip "$DRIVER_URL"; \
    unzip -q -o /tmp/chromedriver.zip -d /tmp; \
    mv "/tmp/chromedriver-${PLATFORM}/chromedriver" /usr/bin/chromedriver; \
    chmod +x /usr/bin/chromedriver; \
    /opt/chrome/chrome --version; \
    chromedriver --version; \
    rm -rf /tmp/* /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rainyun.py notify.py ICR.py stealth.min.js ./

CMD ["python", "rainyun.py"]

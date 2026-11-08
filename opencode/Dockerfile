FROM ghcr.io/anomalyco/opencode:latest

USER root

# Maak de opencode gebruiker en home-directory expliciet aan
RUN addgroup -g 1000 opencode \
 && adduser -u 1000 -G opencode -s /bin/sh -D opencode

RUN apk add --no-cache \
    git \
    python3 \
    py3-yaml \
    py3-jinja2 \
    py3-pip \
    nodejs \
    npm \
    chromium \
    nss \
    freetype \
    fontconfig \
    ttf-freefont \
    libstdc++ \
 && npm install -g playwright@latest \
 && npx playwright install chromium --with-deps 2>/dev/null || true \
 && rm -rf /var/cache/apk/* /tmp/* /root/.cache /root/.npm

# Zorg dat de nieuw aangemaakte user ook rechten heeft op zijn eigen home & browser cache
ENV PLAYWRIGHT_BROWSERS_PATH=/home/opencode/.cache/ms-playwright
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV CI=true
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN mkdir -p /home/opencode/.cache /workspace \
 && chown -R opencode:opencode /home/opencode /workspace

USER opencode
ENV HOME=/home/opencode
WORKDIR /workspace

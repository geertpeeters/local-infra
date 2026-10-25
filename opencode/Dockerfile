FROM ghcr.io/anomalyco/opencode:latest

RUN apk add --no-cache git \
 && addgroup -g 1000 opencode \
 && adduser -D -u 1000 -G opencode -h /home/opencode opencode \
 && mkdir -p /home/opencode/.local /home/opencode/.config/opencode /workspace \
 && chown -R opencode:opencode /home/opencode /workspace

USER opencode
ENV HOME=/home/opencode
WORKDIR /workspace

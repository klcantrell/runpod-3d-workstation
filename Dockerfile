# Ephemeral 3D workstation for Runpod: KDE desktop streamed to the browser
# (Selkies, WebSocket transport, so Runpod's HTTP proxy on 8080 is enough),
# Blender baked in, Isaac Sim and Unreal installed on demand, and work synced
# to Cloudflare R2 so the pod itself can be thrown away.
FROM ghcr.io/selkies-project/selkies-egl-desktop:26.04

ARG BLENDER_VERSION=5.2.3
ARG RCLONE_VERSION=1.76.0
ARG RUNPODCTL_VERSION=3.1.0

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl ca-certificates unzip zstd xz-utils pv \
        libxi6 libxkbcommon0 libsm6 libxxf86vm1 libgl1 libegl1 libvulkan1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Blender
RUN mkdir -p /opt/blender && \
    curl -fsSL "https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /opt/blender --strip-components=1 && \
    ln -s /opt/blender/blender /usr/local/bin/blender

# rclone (R2 sync), runpodctl (self-terminate), uv (Python 3.12 for Isaac Sim)
RUN curl -fsSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" -o /tmp/rclone.zip && \
    unzip -j /tmp/rclone.zip '*/rclone' -d /usr/local/bin && rm /tmp/rclone.zip && \
    curl -fsSL "https://github.com/runpod/runpodctl/releases/download/v${RUNPODCTL_VERSION}/runpodctl-linux-amd64" -o /usr/local/bin/runpodctl && \
    chmod 755 /usr/local/bin/rclone /usr/local/bin/runpodctl
COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /usr/local/bin/

COPY rootfs/ /
RUN chmod 755 /usr/local/bin/ws-* /usr/local/bin/install-* /usr/local/bin/isaacsim /usr/local/bin/unreal \
      /etc/service/r2-sync/run /etc/service/r2-sync/finish && \
    chown -R 1000:1000 /etc/service/r2-sync

USER 1000
ENV WS_AUTOSAVE_MINUTES=10 \
    ISAACSIM_VERSION=6.2.0.0

# Shortcuts on the desktop (KDE only runs desktop files there if they're executable)
RUN mkdir -p "$HOME/Desktop" && \
    for f in blender isaacsim unreal ws-save ws-save-and-terminate; do \
      install -m 755 "/usr/share/applications/$f.desktop" "$HOME/Desktop/"; \
    done

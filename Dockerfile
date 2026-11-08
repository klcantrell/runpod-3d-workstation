# Ephemeral 3D workstation for Runpod: KDE desktop streamed to the browser
# (Selkies, WebSocket transport, so Runpod's HTTP proxy on 8080 is enough),
# Blender baked in, Isaac Sim and Unreal installed on demand, and work synced
# to Cloudflare R2 so the pod itself can be thrown away.
#
# Versions are pinned and bumped by Renovate PRs (see renovate.json). The base
# is pinned to a timestamped tag plus digest because upstream re-pushes 26.04
# every few days and deletes old digests; if this one disappears the build
# fails loudly and the pending Renovate PR is the fix.
FROM ghcr.io/selkies-project/selkies-egl-desktop:26.04-20261029144750@sha256:1439af71c8d403719d37967d50222b592aa6187e6f296e4379859b263a531608

# renovate: datasource=github-tags depName=blender/blender extractVersion=^v(?<version>.+)$
ARG BLENDER_VERSION=5.2.3
# renovate: datasource=github-releases depName=rclone/rclone extractVersion=^v(?<version>.+)$
ARG RCLONE_VERSION=1.76.0
# renovate: datasource=github-releases depName=runpod/runpodctl extractVersion=^v(?<version>.+)$
ARG RUNPODCTL_VERSION=3.1.0
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.311
# renovate: datasource=git-tags depName=https://projects.blender.org/lab/blender_mcp.git extractVersion=^v(?<version>.+)$
ARG BLENDER_MCP_VERSION=1.0.3
# renovate: datasource=pypi depName=isaacsim
ARG ISAACSIM_VERSION=6.2.0.0

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl ca-certificates git unzip zstd xz-utils libnotify-bin \
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
    chown -R 1000:1000 /etc/service/r2-sync /opt/ws

# Refuses to start on missing or unresolved secrets, then runs the base entrypoint
ENTRYPOINT ["/usr/local/bin/ws-entrypoint"]

USER 1000
# SELKIES_ENABLE_HTTPS=false: Runpod's proxy terminates TLS and talks plain HTTP
# to the pod. The MCP add-on (a system extension), and a startup script that
# enables it, are shipped outside the synced ~/.config/blender so image
# upgrades replace them.
ENV WS_AUTOSAVE_MINUTES=10 \
    WS_MAX_HOURS=8 \
    ISAACSIM_VERSION=${ISAACSIM_VERSION} \
    PATH="/home/ubuntu/.local/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/ubuntu/.claude \
    DISABLE_AUTOUPDATER=1 \
    SELKIES_ENABLE_HTTPS=false \
    BLENDER_SYSTEM_SCRIPTS=/opt/ws/blender \
    BLENDER_SYSTEM_EXTENSIONS=/opt/ws/blender/extensions \
    RUNPOD_NO_UPDATE_CHECK=1

# Claude Code. Updates come from bumping CLAUDE_CODE_VERSION (Renovate does it);
# an auto-update on an ephemeral pod would be lost anyway.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_VERSION" && claude --version

# Blender MCP (Blender Lab): the add-on runs a socket server inside Blender
# (auto-starts on launch) and the MCP server Claude Code spawns talks to it.
# Both come from the same tag; ws-reconcile registers the server at boot.
# Cloned because the forge blocks archive downloads. Fails the build if Blender
# can't enable the add-on.
RUN git -c advice.detachedHead=false clone -q --depth 1 --branch "v${BLENDER_MCP_VERSION}" \
      https://projects.blender.org/lab/blender_mcp.git /tmp/blender_mcp && \
    mkdir -p /opt/ws/blender/extensions/system && \
    cp -R /tmp/blender_mcp/addon/blender_mcp_addon /opt/ws/blender/extensions/system/mcp && \
    export UV_PYTHON_INSTALL_DIR=/opt/ws/python UV_NO_CACHE=1 && \
    uv venv -q --python 3.12 /opt/ws/blender-mcp && \
    uv pip install -q --python /opt/ws/blender-mcp /tmp/blender_mcp/mcp && \
    rm -rf /tmp/blender_mcp && \
    /opt/ws/blender-mcp/bin/blender-mcp --help >/dev/null && \
    blender -b --python-exit-code 1 --python /usr/local/lib/blender-check-mcp.py

# Nothing may be left in the synced folders: restore skips R2 files that are
# older than local ones, so anything baked here would hide the user's copy.
# Shortcuts on the desktop (KDE only runs desktop files there if they're executable).
RUN rm -rf "$HOME/.claude" "$HOME/.config/blender" "$HOME/.config/Epic" "$HOME/work" && \
    mkdir -p "$HOME/Desktop" && \
    for f in blender isaacsim unreal ws-save ws-save-and-terminate; do \
      install -m 755 "/usr/share/applications/$f.desktop" "$HOME/Desktop/"; \
    done

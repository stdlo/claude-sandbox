# The container Claude Code runs in. Plain Debian (13, trixie, slim) rather than a language image:
# Node comes from fnm and Python from uv, so each project can pick its own version.
FROM debian:trixie-slim

ARG NODE_VERSION=24
ARG PYTHON_VERSION=3.13

# Tools (the slim image has no curl or CA certificates), ripgrep, ShellCheck, the everyday tools a shell session
# expects (diff, patch, jq, ps, file, make, xz, zip, less, tree) and a few for debugging (dig, nc, lsof, strace,
# sqlite3), nothing that reaches a cluster or a database server; the GitHub CLI (Debian's package lags far behind,
# so it comes from the release); and the non-root user. The user keeps the uid, gid, home and shell of
# the Red Hat UBI image this started from (1001, 0, /opt/app-root/src, bash), so an existing ~/.claude volume
# still belongs to it and the gh login in it keeps working. /workspace is the mount point for the
# claude-workspace folder.
USER 0
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip ripgrep shellcheck tzdata \
      diffutils patch jq procps file make xz-utils zip less tree \
      bind9-dnsutils netcat-openbsd lsof strace sqlite3 \
 && rm -rf /var/lib/apt/lists/* \
 && rg --version \
 && GH=2.101.0 \
 && case "$(uname -m)" in \
      aarch64) A=arm64 ;; \
      x86_64)  A=amd64 ;; \
    esac \
 && curl -fsSL "https://github.com/cli/cli/releases/download/v$GH/gh_${GH}_linux_$A.tar.gz" \
    | tar -xz -C /tmp \
 && mv "/tmp/gh_${GH}_linux_$A/bin/gh" /usr/local/bin/gh \
 && rm -rf /tmp/gh_* \
 && gh --version \
 && mkdir -p /opt/app-root \
 && useradd -u 1001 -g 0 -d /opt/app-root/src -m -s /bin/bash default \
 && mkdir -p /workspace \
 && chown -R 1001:0 /workspace /opt/app-root/src

USER 1001
# The owner's local time, so dates in the container (git, logs, Claude's notes) read as they do on the Mac.
ENV TZ=America/Los_Angeles
ENV HOME=/opt/app-root/src
# ~/.local/bin: fnm, uv, uvx, the default python/python3, and Claude Code.
# fnm's aliases/default/bin: the default node/npm/npx, so they work in any shell, interactive or not.
# gh keeps its login in GH_CONFIG_DIR. Its default, ~/.config/gh, is not on a persisted volume, so it goes
# under ~/.claude, the one volume every run mounts, and `gh auth login` survives a container restart.
ENV PATH=$HOME/.local/bin:$HOME/.local/share/fnm/aliases/default/bin:$PATH \
    FNM_DIR=$HOME/.local/share/fnm \
    GH_CONFIG_DIR=$HOME/.claude/gh \
    CLAUDE_CONFIG_DIR=$HOME/.claude \
    USE_BUILTIN_RIPGREP=0

# fnm with a default Node, uv with a default Python, then Claude Code (a native binary; needs neither).
# Interactive shells also get `fnm env --use-on-cd`, so a .node-version or .nvmrc switches Node on cd. Only
# interactive ones: Claude Code's tool shells source .bashrc without the per-shell PATH, and the cd hook
# then warns on every cd (and aborts it when the pinned version is missing).
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/bin" --skip-shell \
 && fnm install "$NODE_VERSION" \
 && fnm default "$NODE_VERSION" \
 && printf '\n%s\n' 'case $- in *i*) eval "$(fnm env --use-on-cd --shell bash)";; esac' >> "$HOME/.bashrc" \
 && curl -LsSf https://astral.sh/uv/install.sh | sh \
 && uv python install "$PYTHON_VERSION" --default \
 && curl -fsSL https://claude.ai/install.sh | bash \
 && node --version && npm --version && python3 --version && uv --version && claude --version

WORKDIR /workspace

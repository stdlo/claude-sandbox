# The container Claude Code runs in. A small Debian base gives the standard Linux layout that downloaded programs
# expect; every tool comes from Nix, from one pinned nixpkgs revision. A repo's own tools (its Node, its devshell)
# come from Nix per repo, not from this image.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

# Bump NIXPKGS_REV to update every tool at once.
ARG NIX_VERSION=2.35.4
ARG NIXPKGS_REV=1d060086d60cb76a40cf37109f979d88a5bd6396

# Debian's security fixes since the pinned base, only what the Nix installer needs, the non-root user, and the
# mount point for the workspace folder.
USER 0
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -u 1000 -U -m -s /bin/bash claude \
 && mkdir -m 0755 /nix /workspace \
 && chown claude:claude /nix /workspace

USER claude
# Nix's programs read certificates and time zones from these paths, since nothing loads Nix's shell profile.
# gh keeps its login under ~/.claude, the volume every run mounts, so it survives a restart.
ENV HOME=/home/claude \
    USER=claude \
    LANG=C.UTF-8 \
    TZ=America/Los_Angeles \
    TZDIR=/home/claude/.nix-profile/share/zoneinfo \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PATH=/home/claude/.local/bin:/home/claude/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin \
    CLAUDE_CONFIG_DIR=/home/claude/.claude \
    GH_CONFIG_DIR=/home/claude/.claude/gh \
    USE_BUILTIN_RIPGREP=0

# Nix, single-user with no daemon, configured in its per-user file. The versioned installer checks the release's
# SHA-256. The build sandbox is off, as in Nix's own container image, since a container can't usually create the
# namespaces it needs.
RUN mkdir -p "$HOME/.config/nix" \
 && printf '%s\n' 'experimental-features = nix-command flakes' 'sandbox = false' >"$HOME/.config/nix/nix.conf" \
 && curl -fsSL "https://releases.nixos.org/nix/nix-$NIX_VERSION/install" \
    | sh -s -- --no-daemon --no-channel-add --no-modify-profile \
 && nix --version \
 && nix config show experimental-features

# Everyday tools and a few for debugging; nothing that reaches a cluster or a database server.
RUN n="github:NixOS/nixpkgs/$NIXPKGS_REV" \
 && nix profile add \
      "$n#git" "$n#gh" "$n#python3" "$n#ripgrep" "$n#jq" "$n#shellcheck" "$n#fish" "$n#sops" "$n#age" \
      "$n#gnupatch" "$n#procps" "$n#file" "$n#gnumake" "$n#zip" "$n#unzip" "$n#less" "$n#tree" "$n#tzdata" \
      "$n#dig" "$n#netcat-openbsd" "$n#lsof" "$n#strace" "$n#sqlite" \
 && git --version && gh --version && python3 --version && rg --version && date

# Claude Code, its native build.
RUN curl -fsSL https://claude.ai/install.sh | bash \
 && claude --version

WORKDIR /workspace

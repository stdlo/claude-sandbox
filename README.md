# claude-sandbox

The container image Claude Code runs in. A small Debian 13 base, pinned by digest, gives the standard Linux layout
that downloaded programs expect. Every tool comes from Nix, all from one pinned nixpkgs revision: git, `gh`,
Python, ripgrep, jq, ShellCheck, fish, sops, age, and the everyday shell and debugging tools. Nothing in it reaches a
cluster or a database server. Claude Code runs as the non-root user `claude` (uid 1000, home `/home/claude`) in
`/workspace`, a mount of the folder that holds the repos Claude may work in.

## A repo's own tools

The image carries no language toolchain. A repo brings its own through Nix:

- A repo with a `flake.nix`: `nix develop` gives a shell with exactly what its `flake.lock` pins, and
  `nix develop -c <command>` runs one command in it.
- Anything else: `nix shell nixpkgs#nodejs_24 -c npm test`, for example, gives a tool for one command.

Nix is single-user, with flakes on and its build sandbox off (as in Nix's own container image, since a container
can't usually create the namespaces it needs). The store, `/nix`, is the container's own and shared with no other.

## Updating

Every tool moves together: bump `NIXPKGS_REV` in the Dockerfile. The base moves by its digest. Claude Code is the
current release at each build; the weekly build keeps it fresh.

## Running it

With Podman (with Docker, leave out `--userns` and the volume's `:U`):

    podman run -it --rm --init \
      --userns=keep-id:uid=1000,gid=1000 \
      -v "$HOME/path/to/repos":/workspace \
      -v claude-config:/home/claude/.claude:U \
      ghcr.io/stdlo/claude-sandbox claude

- `--userns=keep-id` maps you to `claude`, so files written in `/workspace` are yours on the host.
- `claude-config` is a named volume at `~/.claude` that keeps Claude Code's login and state, and the `gh` login,
  between runs. It is not your machine's `~/.claude`.
- `--init` reaps finished processes, which Claude Code doesn't, so a long run never runs out of them.

Mount nothing else: no home folder, no `~/.kube`, `~/.aws`, or `~/.ssh`, and no container engine socket. What isn't
mounted can't be reached.

## GitHub access

Give `gh` a **fine-grained personal access token limited to the repositories Claude should see**; a token can't
see a repository it wasn't granted, so the token is the fence. Avoid `gh auth login`'s browser flow, which issues a
token that reaches every repository your account can.

1. On GitHub: Settings › Developer settings › Personal access tokens › Fine-grained tokens › Generate new token.
2. Repository access: **Only select repositories**, then the ones shared with Claude.
3. Permissions: **Contents: read-only** (Metadata is added). Add Pull requests or Issues only if Claude should use
   them.
4. In the container: `gh auth login --with-token`, then paste the token. It's kept in `~/.claude/gh`, on the volume.
5. Check it: `gh api repos/<owner>/<a repo not on the list>` fails with a 404, and a shared one works.

`gh auth setup-git` lets git use the same login for HTTPS; it writes `~/.gitconfig`, which isn't on the volume, so
run it again after a restart.

## Builds

GitHub Actions builds every push to any branch, natively for amd64 and arm64, tagged `sha-<7 characters>`; `main`
also moves `latest`. A weekly build on Mondays picks up Claude Code's newest release.

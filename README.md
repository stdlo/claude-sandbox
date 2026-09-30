# claude-sandbox

The container image Claude Code runs in. Built on plain Debian 13 (trixie, slim), it adds curl, git, ripgrep,
the GitHub CLI (`gh`) and the everyday shell tools (diff, patch, jq, ps, file, make, xz, zip, less, tree,
ShellCheck, and dig, nc, lsof, strace and sqlite3 for debugging; nothing that reaches a cluster or a database
server), creates the non-root user `claude` (uid 1000, gid 1000, home `/home/claude`, Debian's defaults for a first
user), installs Claude Code, and sets `/workspace` as the working directory. `/workspace` is meant to be a mount of
the `claude-workspace` folder that holds every repo shared with Claude.

## Node and Python

Neither is baked in from a language image. Instead:

- **fnm** manages Node. The image installs one default (`NODE_VERSION`, 24). In a shell, `fnm install 22` adds
  another and `fnm use 22` switches. In interactive shells only, a `.node-version` or `.nvmrc` in a repo
  switches automatically on `cd`; Claude's tool shells keep the default Node and don't run the hook. The default's
  `node`, `npm` and `npx` are on `PATH` for non-interactive commands too.
- **uv** manages Python. The image installs one default (`PYTHON_VERSION`, 3.13) as `python3`. `uv python
  install 3.12` adds another; `uv run --python 3.12 …`, a `.python-version` file, or a project's
  `pyproject.toml` picks the version per project.

## GitHub access

GitHub access goes through `gh`, and the only credential to give it is a **fine-grained personal access token
restricted to the repositories Claude should see**. Anything stored in the container is readable by Claude
and persists between sessions, so the token itself has to be the fence: a fine-grained token cannot see
that a repository it wasn't granted exists. Do not use the interactive `gh auth login` browser flow; it
issues a token that reaches every repository your account can, restricted only by permission type.

1. On GitHub: Settings › Developer settings › Personal access tokens › Fine-grained tokens › Generate new
   token.
2. Resource owner: whoever owns the repos, your account or an organization. Repository access: **Only select
   repositories**, then pick exactly the repos that are shared with Claude. Anything left off the list is
   invisible to the token, which is the point.
3. Permissions: **Contents: read-only** and Metadata: read (added automatically). Read-only contents also
   means Claude cannot push, which is the working rule anyway. Add Pull requests and Issues (read and write)
   only if Claude should open or comment on those.
4. Expiration: the maximum is one year. Note the date somewhere you will see it.
5. Inside the container (in a Claude Code session, the `!` prefix runs it there), paste the token when asked:

       ! gh auth login --with-token

   The login is stored in `GH_CONFIG_DIR`, which the image points at `~/.claude/gh` rather than the default
   `~/.config/gh`, so it sits on the `claude-config` volume mounted at `~/.claude` ("Running it" above) and survives a restart. Nothing
   needs to be set on `docker run`.
6. Check the fence. A repo that is not on the token's list must fail with a 404, and a shared one must work:

       gh api repos/<owner>/<repo-not-shared>
       gh repo view <owner>/<shared-repo>

To let git itself use the same login for HTTPS remotes, run `gh auth setup-git`. It writes to
`~/.gitconfig`, which is not persisted, so rerun it after a restart.

## Running it
From your machine (the image sets `TZ=America/Los_Angeles`; pass `-e TZ=…` to override it):

    docker run -it --rm \
      -v "path/to/claude-workspace/":/workspace \
      -v claude-config:/home/claude/.claude \
      ghcr.io/stdlo/claude-sandbox claude

`/workspace` is a folder holding the repos Claude may work in, so everything Claude writes there persists on your
machine. `claude-config` is a named Docker volume mounted at `~/.claude` inside the container
(`/home/claude/.claude`): Claude Code's own state, the `gh` login and Claude's memory live there and survive a
restart; it is not your machine's `~/.claude`. A volume first written by an image whose user had another uid needs
its ownership fixed once, or nothing in it can be read:

    docker run --rm -v claude-config:/v debian:trixie-slim chown -R 1000:1000 /v

**Keeping Claude Code's updates between runs.** Claude Code updates itself into `~/.local`, which is not on a volume,
so with `--rm` every exit discards the update and the next start downloads it again. Either rebuild the image (the
weekly build below carries the current release) or keep one container instead of removing it:

    docker run -it --name claude-sandbox \
      -v "path/to/claude-workspace/":/workspace \
      -v claude-config:/home/claude/.claude \
      ghcr.io/stdlo/claude-sandbox claude

and from then on `docker start -ai claude-sandbox`. The container's own layer keeps whatever the updater wrote until
you remove it (`docker rm claude-sandbox`, for example to move to a rebuilt image).

## Building

GitHub Actions builds the image on every push to any branch, every Monday at 06:00 Pacific (so `latest` carries
the current Claude Code release), and on demand from the Actions tab and publishes it to GitHub's container registry, named after the
repository: `ghcr.io/stdlo/claude-sandbox`. Every build is tagged with its short commit sha, and builds of
`main` also as `latest`, so a branch can be tried (`docker pull …:sha-<commit>`) before it merges. It is built
for `linux/amd64` and `linux/arm64` (Apple silicon), each natively on GitHub's own runners (`ubuntu-latest`
and `ubuntu-24.04-arm`) in parallel, then joined into one multi-arch manifest. There is no schedule; a rebuild
happens only when something is pushed or someone asks for one.

    docker pull ghcr.io/stdlo/claude-sandbox:latest

To build locally, optionally with other defaults:

    docker build -t claude-sandbox .
    docker build -t claude-sandbox --build-arg NODE_VERSION=22 --build-arg PYTHON_VERSION=3.12 .

---
name: install-claude-sidecar
description: "Set up Claude Sidecar in a project. Use when: user asks to 'add claude container', 'setup claude-sidecar', 'integrate claude container', 'install claude-sidecar', 'add claude sidecar', or wants Claude Code running in a container with cross-project access and sensitive-file shadowing."
---

# Claude Sidecar Installer

Set up Claude Sidecar to run Claude Code in a container, with sensitive-file shadowing and optional cross-project mounts. **This skill never touches `compose.yml`.** All claude-sidecar wiring goes into a generated `compose.sidecar.yml` that the host wrapper produces from declarative inputs.

## Architecture (read this once)

The new model has three pieces:

1. **Per-repo `.sidecar/shadow`** — a plain text file listing sensitive paths to shadow (one per line; trailing `/` means directory). Committed with the repo.
2. **Per-user `~/.claude-sidecar/config.yaml`** — declares the container image, optional `host_network` mode, and `extra_mounts` (other repos to mount into Claude sessions).
3. **`claude-sidecar` host wrapper** at `~/.local/bin/claude-sidecar`. Subcommands: bare (drift-check + drop into Claude), `up` (regen + compose up), `exec`, `gen-overlay`. The wrapper generates `compose.sidecar.yml` and runs `docker compose -f compose.yml -f compose.sidecar.yml ...`.

Result: the user's `compose.yml` (their own app services) is untouched. Claude-sidecar lives entirely in a separate, generated, gitignored file.

## Workflow

1. Detect prior install (skip first-time setup if already done).
2. Discover sensitive files in the current project → confirm with user → write `.sidecar/shadow`.
3. **First-time only**: install `~/.local/bin/claude-sidecar` wrapper and create `~/.claude-sidecar/config.yaml`.
4. Ask about sibling repos to extra-mount; ensure each has a `.sidecar/shadow` (run discovery if missing).
5. Append generated files to project `.gitignore`.
6. Print verification commands.

## Step 1: Detect prior install

```bash
# Wrapper installed?
test -x ~/.local/bin/claude-sidecar

# User-level config exists?
test -f ~/.claude-sidecar/config.yaml
```

If both exist, skip Step 3. Otherwise, do first-time setup before per-project setup.

## Step 2: Discover and write `.sidecar/shadow`

### 2.1: Scan for credential files

Run the same patterns the old skill used (kept in [references/credential-shadowing.md](references/credential-shadowing.md)):

```bash
# Patterns from .gitignore + name-based heuristics:
grep -E '\.(env|pem|key|crt|credentials|secret)|\bsecrets?\b|\bcredentials?\b|\.npmrc|service.account' \
  .gitignore .dockerignore 2>/dev/null

find . -maxdepth 3 -type f \( \
  -name ".env*" -o -name "*.pem" -o -name "*.key" \
  -o -name "*credentials*" -o -name "*secret*" \
  -o -name ".npmrc" -o -name "service-account*.json" \
\) 2>/dev/null | grep -vE 'node_modules|vendor|\.git/'
```

### 2.2: Confirm with user

Present the list. Ask: "Which of these should be hidden from Claude? (You can also add paths I didn't find.)"

Also ask: "Any sensitive **directories**? (List them with a trailing slash, e.g. `secrets/`.)"

### 2.3: Write the file

Write one path per line. Lines starting with `#` are comments (use them to document why a path is listed). Example:

```
# .sidecar/shadow
.env
.env.local
.credentials.json
# Service-account JSON used by Firebase Admin SDK
service-account.json
# Encrypted secrets bundle — empty inside Claude
secrets/
```

**Important format rules:**
- Paths are relative to the repo root.
- Trailing `/` = directory shadow (becomes tmpfs in the container).
- No trailing `/` = file shadow (becomes /dev/null bind-mount).
- Blank lines and `#` comments are ignored.

## Step 3: First-time setup (skip if detected in Step 1)

### 3.1: Install the wrapper

Copy from the claude-sidecar repo to `~/.local/bin/`:

```bash
mkdir -p ~/.local/bin
cp /path/to/claude-sidecar/scripts/claude-sidecar ~/.local/bin/
chmod +x ~/.local/bin/claude-sidecar
```

(Alternative: `curl -fsSL <release-url>/claude-sidecar > ~/.local/bin/claude-sidecar && chmod +x ~/.local/bin/claude-sidecar` once releases ship that artifact.)

Verify `~/.local/bin` is on `PATH`. On macOS it usually is via `/etc/paths.d/`; on Linux, may need `export PATH="$HOME/.local/bin:$PATH"` in the shell rc.

### 3.2: Create the user config

Ask the user:
- "What Docker image should Claude Sidecar use? (Default: `ghcr.io/mithredate/claude-sidecar:latest`. Tip: build your own with `FROM ghcr.io/mithredate/claude-sidecar:latest` + extra toolchains for one personal image you reuse across projects.)"
- "Enable host-network mode? (Off by default. On is only needed for OAuth callback flows in MCP SSO.)"

Write `~/.claude-sidecar/config.yaml`:

```yaml
image: ghcr.io/mithredate/claude-sidecar:latest
host_network: false
extra_mounts: []
```

### 3.3: Bootstrap the shared volume + credentials

```bash
# Creates the shared 'claude-sidecar-home' volume and seeds credentials
/path/to/claude-sidecar/scripts/sync-creds.sh
```

## Step 4: Sibling repos (extra_mounts)

Ask: "Do you want Claude in this project to be able to read other repos (e.g. for cross-repo planning)? List them as comma-separated full paths, or skip."

For each path:
1. If the repo has no `.sidecar/shadow`, run Step 2 there. **Always.** A repo can't be mounted without declaring what's sensitive in it — that's the rule that makes the cross-mount safe.
2. Append the path to `extra_mounts:` in `~/.claude-sidecar/config.yaml`.

Example final config:

```yaml
image: ghcr.io/mithredate/claude-sidecar:latest
host_network: false
extra_mounts:
  - /Users/me/projects/dreamograph/mobile
  - /Users/me/projects/dreamograph/backend-api
```

## Step 5: `.gitignore`

Append to the project's `.gitignore` (idempotent — check before adding):

```
# Claude Sidecar
.credentials.json
compose.sidecar.yml
compose.sidecar-local.yml
```

(`.sidecar/shadow` is **committed** — it's the team's declaration of what's sensitive in this repo. Only the generated and credential files are gitignored.)

## Step 6: Verification commands

Print these for the user:

```bash
# Bring claude-sidecar up for this project:
claude-sidecar up

# Drop into Claude (drift-checks shadow files, then exec's claude in the container):
claude-sidecar

# Run any other command inside the claude-sidecar container:
claude-sidecar exec ls -la

# Regenerate after editing .sidecar/shadow or ~/.claude-sidecar/config.yaml:
claude-sidecar up
```

If the safety check fails on first `up` (e.g. shadow declared but the overlay wasn't generated), tell the user to run `claude-sidecar up` again — the wrapper writes `compose.sidecar.yml` *and* brings up, so a single invocation fixes the order.

## Per-project escape hatch: `compose.sidecar-local.yml`

If a project needs an extra env var, additional volume, or other tweak specific to the claude-sidecar container *for this project only*, the user can create `compose.sidecar-local.yml` at the project root. The wrapper auto-merges it after `compose.sidecar.yml`. Gitignored by default.

Example:

```yaml
# compose.sidecar-local.yml
services:
  claude-sidecar:
    environment:
      DEBUG_FOO: "1"
    volumes:
      - ./tmp/cache:/cache
```

## Error Handling

### Wrapper not installed
First-time install (Step 3.1) hasn't run. Re-run the skill, or copy the wrapper manually.

### `claude-sidecar up` fails with "config not found"
`~/.claude-sidecar/config.yaml` is missing. Run Step 3.2.

### "shadow safety check failed" at container start
The container's entrypoint detected paths listed in `.sidecar/shadow` that aren't actually shadowed. Either:
- The user ran `docker compose up` directly without `compose.sidecar.yml`. Fix: `claude-sidecar up`.
- `.sidecar/shadow` was edited but `claude-sidecar up` wasn't run since. Same fix.

### Shadow drift warning on `claude-sidecar exec`
`.sidecar/shadow` (here or in an extra-mount repo) changed since the last `up`. Run `claude-sidecar up` to regenerate. **Recreating the container will end any running Claude session** — finish your work first, then refresh.

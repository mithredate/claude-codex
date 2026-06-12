---
name: install-claude-sidecar
description: "Set up Claude Sidecar integration in any Docker-based project. Use when: user asks to 'add claude container', 'setup claude-sidecar', 'integrate claude container', 'add claude to docker compose', 'containerize claude', 'run claude in docker', or wants Claude Code running as a container service with project toolchains and an egress firewall."
---

# Claude Sidecar Installer

Set up Claude Sidecar to run Claude Code in a single container alongside a project.
Toolchains (node, go, python, …) are installed in-image on demand via
[mise](https://mise.jdx.dev); Claude runs build/test commands directly and reaches
the project's services (db, redis, …) over the compose network by name. There is no
command bridge or Docker socket access. A startup firewall whitelists egress and
Claude runs as a non-root user.

## Workflow

1. Analyze project (tech stack, compose file, services, toolchain version pins)
2. Add/create the `claude` service in the compose file (single-container model)
3. Ensure toolchains resolve (mise reads `.tool-versions` / `mise.toml`)
4. Optionally add `.sidecar/allowed-domains.txt` for the firewall
5. **Ask about credential shadowing** → discover → confirm → apply
6. Seed Claude auth + config from the host

## Step 1: Analyze Project

Identify:

- Tech stack (language, framework, package manager)
- Existing `compose.yml` / `docker-compose.yml` and its services
- Which services Claude's code will need to reach (db, cache, queues) — Claude
  reaches them by service name over the compose network
- Toolchain version pins: look for `.tool-versions`, `mise.toml`, `.nvmrc`,
  `go.mod`, `.python-version`. If none exist, suggest adding a `mise.toml` so
  versions are reproducible (mise still auto-installs a default otherwise).

## Step 2: Add the claude service

Add to the project's compose file (so `claude` shares the project network and can
reach its services). If no compose file exists, create `compose.yml`.

```yaml
services:
  claude:
    image: ghcr.io/mithredate/claude-sidecar:latest
    stdin_open: true
    tty: true
    # Egress firewall (remove this cap_add block to disable the firewall)
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      # Config dir for the firewall's allowed-domains.txt (under the project)
      - SIDECAR_CONFIG_DIR=${PWD}/.sidecar
      # Auto-trust mise configs under the project so toolchain pins work
      - MISE_TRUSTED_CONFIG_PATHS=${PWD}
      # On Linux, match the host user so mounted files are owned correctly:
      # - PUID=1000
      # - PGID=1000
      # Connection info the app code needs (the container holds these for now —
      # credential isolation from the model is not yet implemented):
      # - DATABASE_URL=postgres://app:secret@db:5432/app
    volumes:
      # Mount the project at its REAL host path (source == target) so Claude's
      # per-project MCP config + session history (keyed by absolute path) match.
      - ${PWD}:${PWD}
      # Persistent Claude home: auth, config, and installed toolchains persist.
      - claude-home:/home/claude
      # Read-only auth seeds, copied into the volume on first start only (Step 6).
      - ./.credentials.json:/seed/credentials.json:ro
      - ${HOME}/.claude.json:/seed/claude.json:ro
      # Shadow this project's secret files from the model (Step 5).
      - /dev/null:${PWD}/.env
      - /dev/null:${PWD}/.credentials.json
    working_dir: ${PWD}

volumes:
  claude-home:
```

`${PWD}` and `${HOME}` are interpolated by Docker Compose from the host shell, so
this stays portable across machines and the in-container path equals the host path.

## Step 3: Toolchains (mise)

No bridge or per-command config is needed. mise resolves toolchains per project
from `.tool-versions` / `mise.toml` and installs them on first use (prebuilt — fast).
Installs persist in the `claude-home` volume. `MISE_TRUSTED_CONFIG_PATHS=${PWD}`
(Step 2) lets mise trust the project's config without a manual `mise trust`.

If the project has no version file, recommend creating `mise.toml`:

```toml
[tools]
node = "22"      # or go, python, etc. — match the project
```

## Step 4: Allowed Domains (Optional)

The firewall resolves a whitelist at container start. Create
`.sidecar/allowed-domains.txt` if the project needs hosts beyond the defaults
(GitHub IP ranges are always added):

```text
# Anthropic + Claude Code
api.anthropic.com
console.anthropic.com
statsig.anthropic.com
sentry.io
# Package registry + mise toolchain downloads
registry.npmjs.org
mise.jdx.dev
objects.githubusercontent.com
nodejs.org
go.dev
dl.google.com
storage.googleapis.com
# Project-specific APIs / MCP server hosts
# api.example.com
```

Note: a custom file REPLACES the built-in defaults, so include the Anthropic/npm/
mise hosts above plus any MCP server domains. Add the domains of any MCP servers the
project uses, or they will fail to connect. To disable the firewall entirely, remove
the `cap_add` block from compose.

> Limitation: domains are resolved to IPs once at startup; CDN IP rotation can break
> a long-lived container until restart.

## Step 5: Shadow Credential Files (Optional)

### 5.1: Ask User

"Would you like to shadow credential files? This hides sensitive files (`.env`, keys,
certs) from Claude by mounting `/dev/null` over them. The files stay intact on your
host but appear empty inside the container."

If user declines, skip to Step 6.

### 5.2: Discover Credentials

Use the patterns in [references/credential-shadowing.md](references/credential-shadowing.md):

```bash
grep -E '\.(env|pem|key|crt|credentials|secret)|\bsecrets?\b|\bcredentials?\b|\.npmrc|service.account' .gitignore .dockerignore 2>/dev/null
find . -maxdepth 3 -type f \( -name ".env*" -o -name "*.pem" -o -name "*.key" -o -name "*credentials*" -o -name "*secret*" -o -name ".npmrc" -o -name "service-account*.json" \) 2>/dev/null | grep -vE 'node_modules|vendor'
```

### 5.3–5.4: Confirm + Ask for More

Present discovered files, ask which to shadow, then ask for any others not found.

### 5.5: Apply Shadows

Add each confirmed file as a `/dev/null` mount (note: writable, NOT `:ro` — a `:ro`
bind of `/dev/null` can fail on some setups):

```yaml
volumes:
  - /dev/null:${PWD}/.env
  - /dev/null:${PWD}/config/secrets.yaml
```

See [references/credential-shadowing.md](references/credential-shadowing.md).

## Step 6: Seed Claude Auth + Config

Auth and config are seeded into the `claude-home` volume on first start (only if
absent), so there is no re-auth / re-onboarding across container recreation. Provide
two seeds before `docker compose up`:

1. **`.credentials.json`** — must be the **full** credential blob (`claudeAiOauth`
   *and* `mcpOAuth`, or MCP servers stay unauthenticated):

   ```bash
   # macOS — capture the WHOLE keychain blob
   security find-generic-password -s "Claude Code-credentials" -w > .credentials.json
   # Linux — the file already contains the full blob
   cp ~/.claude/.credentials.json .credentials.json
   ```

   Verify both keys are present:
   ```bash
   python3 -c "import json;print(list(json.load(open('.credentials.json')).keys()))"
   # -> ['claudeAiOauth', 'mcpOAuth']
   ```

2. **`~/.claude.json`** — onboarding state, oauthAccount, per-project `mcpServers`.
   Mounted from the host by compose; no copy needed.

**Add to `.gitignore`:** `.credentials.json`

> Limitation: seeded OAuth credentials are shared with the host account; a host
> re-login can invalidate the container copy. For a long-lived container, prefer
> authenticating it independently (interactive `/login` inside the container, or an
> API key) over seeding.

**Re-authenticate / reset:** `docker compose down -v` (drops the volume; re-seeds next start).

## Post-Setup Commands

```bash
docker compose up -d claude                          # Start
docker compose exec claude claude                    # Run Claude interactively
docker compose exec -e CLAUDE_YOLO=1 claude claude   # YOLO mode (skip permissions)
docker compose down                                  # Stop
```

The `claude` wrapper inside the image drops to the non-root `claude` user
automatically, so `docker compose exec claude claude` works without `-u`.

## Error Handling

### No compose file exists
Create `compose.yml` with the `claude` service from Step 2.

### Toolchain not found / fails to install
The image auto-installs the version pinned by the project's mise config on first use.
If it fails, check the firewall (Step 4) — the toolchain download host is likely not
whitelisted — or that the project pins a real version.

### Claude can't reach the database / a service
Ensure the `claude` service is in the SAME compose file (or network) as the service,
and connect by service name (e.g. `db:5432`). The firewall allows the internal
docker subnet by default.

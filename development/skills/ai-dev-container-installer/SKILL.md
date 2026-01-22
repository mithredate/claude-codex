---
name: ai-dev-container-installer
description: "Set up AI Dev Container integration in any Docker-based project. Use when: user asks to 'add claude container', 'setup ai-dev-container', 'integrate claude container', 'add claude to docker compose', or wants Claude Code running as a container service with bridge command routing to project containers."
---

# AI Dev Container Installer

Set up Claude Brain Sidecar to run Claude Code in a container that delegates commands to project containers via Docker socket proxy.

## Workflow

1. Analyze project structure (tech stack, existing compose file, containers)
2. Update/create compose.yml with required services
3. Create `.aidevcontainer/bridge.yaml` with command mappings
4. Create CLAUDE.md with project documentation
5. Optionally create `.aidevcontainer/allowed-domains.txt` for firewall
6. Optionally shadow credential files to hide secrets from Claude

## Step 1: Analyze Project

Identify:
- Tech stack (language, framework, package manager)
- Existing `compose.yml` or `docker-compose.yml`
- Container services and their purposes
- Container names (format: `<project>-<service>-1`)
- Working directories inside containers

## Step 2: Update Docker Compose

Add these services to compose file (create if missing):

```yaml
services:
  socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    environment:
      CONTAINERS: 1
      EXEC: 1
      POST: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  claude:
    image: ghcr.io/mithredate/ai-dev-container:latest
    depends_on:
      - socket-proxy
    stdin_open: true
    tty: true
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
      BRIDGE_ENABLED: "1"
    volumes:
      - .:/workspaces/${PWD##*/}
      - claude-config:/home/claude/.claude

volumes:
  claude-config:
```

## Step 3: Create Bridge Configuration

Create `.aidevcontainer/bridge.yaml`:

```yaml
version: "1"
default_container: <main-app-container>

containers:
  app: <project>-<service>-1
  # Add other containers as needed

commands:
  <runtime>:
    container: <container-key>
    exec: <executable>
    workdir: <container-workdir>
    paths:
      /workspaces/<project-folder>: <container-workdir>
```

Map commands based on detected tech stack:
- **PHP**: `php`, `composer`
- **Node**: `node`, `npm`, `npx`, `yarn`, `pnpm`
- **Python**: `python`, `pip`, `pytest`, `poetry`
- **Go**: `go`
- **Ruby**: `ruby`, `bundle`, `rails`, `rake`

Note: Commands like `artisan`, `phpunit`, `phpstan` are invoked via `php` and get intercepted automatically.

## Step 4: Create CLAUDE.md

Create `CLAUDE.md` at project root:

```markdown
# Project Name

## Tech Stack
- [Language/Framework]
- [Database]
- [Other services]

## Container Topology

| Container | Purpose | Workdir | Image |
|-----------|---------|---------|-------|
| project-app-1 | Main app | /app | ... |

## Bridge Commands

Run commands via bridge:
- `bridge php artisan migrate`
- `bridge npm install`
- `bridge composer require package`

## Testing
- `bridge <test-command>`

## Do NOT
- Install packages in Claude container (use bridge)
- Run runtime commands directly (use bridge)
- Assume database is on localhost (use container hostname)
- Mount sensitive directories (~/.ssh, ~/.aws)

## Workspace Path
The project is mounted at `/workspaces/<project-folder>` inside the Claude container.
```

## Step 5: Allowed Domains (Optional)

If project needs external API access, create `.aidevcontainer/allowed-domains.txt`:

```
# Package registries
registry.npmjs.org
pypi.org

# Project-specific APIs
api.example.com
```

Default allowed: Anthropic services, GitHub (auto-fetched), npm registry.

## Step 6: Shadow Credential Files (Optional)

Ask the user if they want to hide sensitive credential files from Claude. This mounts `/dev/null` over credential files, making them appear empty to Claude while keeping the actual files intact on the host.

If user wants credential shadowing, add volume mounts to the claude service:

```yaml
services:
  claude:
    # ... other configuration ...
    volumes:
      - .:/workspaces/${PWD##*/}
      - claude-home:/home/claude
      # Shadow credential files (appear empty to Claude)
      - /dev/null:/workspaces/${PWD##*/}/.env:ro
      - /dev/null:/workspaces/${PWD##*/}/.credentials.json:ro
```

Common files to shadow:
- `.env`, `.env.local`, `.env.production`
- `.credentials.json`, `credentials.json`
- `secrets.yaml`, `secrets.json`
- `.npmrc` (if contains auth tokens)
- `service-account.json`

**User instructions for adding more shadowed files:**

To hide additional credential files from Claude, add volume mounts in this format:

```yaml
volumes:
  - /dev/null:/workspaces/<project-folder>/<path-to-sensitive-file>:ro
```

For example, to shadow a database config file:
```yaml
- /dev/null:/workspaces/<project-folder>/config/database.yml:ro
```

## Step 7: Mount Claude Credentials (Optional - macOS)

On macOS, Claude Code stores credentials in the macOS Keychain. To use these credentials in the container, the user can export them to a file and mount it.

**Export credentials from macOS Keychain:**

```bash
security find-generic-password -s "Claude Code-credentials" -w > .credentials.json
```

**Add to `.gitignore`:**

```gitignore
.credentials.json
```

**Mount in compose.yml:**

```yaml
services:
  claude:
    # ... other configuration ...
    volumes:
      - .:/workspaces/${PWD##*/}
      - claude-config:/home/claude/.claude
      - ./.credentials.json:/home/claude/.claude/.credentials.json:ro
```

**Note:** The credentials file contains sensitive API keys. Ensure it's added to `.gitignore` and never committed to version control.

## Post-Setup Commands

Provide these commands to user:

```bash
# Start container
docker compose up -d claude

# Run Claude interactively
docker compose exec claude claude

# Run in YOLO mode (skip permissions)
docker compose exec -e CLAUDE_YOLO=1 claude claude

# Stop container
docker compose down
```

## Viewer (Optional)

If user wants monitoring, add viewer service.

**Important**: The viewer requires the `claude-config` volume to access Claude's data. Ensure the claude service mounts this volume:

```yaml
services:
  claude:
    # ... other configuration ...
    volumes:
      - ...
      - claude-config:/home/claude/.claude  # Required for viewer
```

Then add the viewer service:

```yaml
services:
  viewer:
    image: node:20-alpine
    command: ["npx", "@kimuson/claude-code-viewer@latest", "--hostname", "0.0.0.0"]
    environment:
      - PORT=${VIEWER_PORT:-3000}
      - CCV_GLOBAL_CLAUDE_DIR=/claude-data
    ports:
      - "${VIEWER_PORT:-3000}:${VIEWER_PORT:-3000}"
    volumes:
      - claude-config:/claude-data:ro  # Reads from claude's config volume
    restart: unless-stopped
```

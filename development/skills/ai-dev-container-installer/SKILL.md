---
name: ai-dev-container-installer
description: "Set up Claude Brain Sidecar (ai-dev-container) integration in any Docker-based project. Use when: user asks to 'add claude sidecar', 'setup ai-dev-container', 'integrate claude brain', 'add claude to docker compose', or wants Claude Code running as a container service with bridge command routing to project containers."
---

# AI Dev Container Installer

Set up Claude Brain Sidecar to run Claude Code in a container that delegates commands to project containers via Docker socket proxy.

## Workflow

1. Analyze project structure (tech stack, existing compose file, containers)
2. Update/create compose.yml with required services
3. Create `.aidevcontainer/bridge.yaml` with command mappings
4. Create CLAUDE.md with project documentation
5. Optionally create `.aidevcontainer/allowed-domains.txt` for firewall

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
      - .:/workspace
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
      /workspace: <container-workdir>
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

If user wants monitoring, add viewer service:

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
      - claude-config:/claude-data:ro
    restart: unless-stopped
```

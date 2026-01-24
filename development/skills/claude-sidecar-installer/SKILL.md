---
name: claude-sidecar-installer
description: "Set up Claude Sidecar integration in any Docker-based project. Use when: user asks to 'add claude container', 'setup claude-sidecar', 'integrate claude container', 'add claude to docker compose', 'containerize claude', 'run claude in docker', 'add claude sidecar', or wants Claude Code running as a container service with bridge command routing to project containers."
---

# Claude Sidecar Installer

Set up Claude Sidecar to run Claude Code in a container that delegates commands to project containers via Docker socket proxy.

## Workflow

1. Analyze project structure (tech stack, existing compose file, containers)
2. Update/create compose.yml with required services
3. Create `.sidecar/bridge.yaml` with command mappings
4. Optionally create `.sidecar/allowed-domains.txt` for firewall
5. **Ask user about credential shadowing** -> discover files -> confirm selection -> ask for missing -> apply
6. Mount Claude credentials (macOS/Linux)
7. **Ask user about viewer** -> confirm port -> apply configuration

## Step 1: Analyze Project

Identify:

- Tech stack (language, framework, package manager)
- Existing `compose.yml` or `docker-compose.yml`
- Container services and their purposes
- Container names (format: `<project>-<service>-1`)
- Working directories inside containers

## Step 2: Update Docker Compose

Add these services to compose file. If no compose file exists, create `compose.yml`.

```yaml
services:
  socket-proxy:
    image: tecnativa/docker-socket-proxy:latest
    restart: unless-stopped
    environment:
      CONTAINERS: 1
      EXEC: 1
      POST: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  claude:
    image: ghcr.io/mithredate/claude-sidecar:latest
    depends_on:
      - socket-proxy
    stdin_open: true
    tty: true
    # Optional: Network firewall (remove cap_add to disable)
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
      BRIDGE_ENABLED: "1"
      # Optional: Override config directory location
      # SIDECAR_CONFIG_DIR: /workspaces/myproject/.sidecar
    volumes:
      - .:/workspaces/<project-name>
      - claude-config:/home/claude/.claude
      # Optional: shadow credentials (see Step 5)
      # - /dev/null:/workspaces/<project-name>/.env:ro
      # Optional: mount Claude credentials (see Step 6)
      # - ./.credentials.json:/home/claude/.claude/.credentials.json:ro
    working_dir: /workspaces/<project-name>

volumes:
  claude-config:
```

Replace `<project-name>` with the actual project directory name.

## Step 3: Create Bridge Configuration

Create `.sidecar/bridge.yaml`:

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
      /workspaces/<project-name>: <container-workdir>
```

Map commands based on detected tech stack:

- **PHP**: `php`, `composer`
- **Node**: `node`, `npm`, `npx`, `yarn`, `pnpm`
- **Python**: `python`, `pip`, `pytest`, `poetry`
- **Go**: `go`, `gofmt`
- **Ruby**: `ruby`, `bundle`, `rails`, `rake`

Note: Commands like `artisan`, `phpunit`, `phpstan` are invoked via `php` and get intercepted automatically.

### Container Name Resolution

Container names follow the format `<project>-<service>-1` where `<project>` is the directory name. If containers aren't running yet:

1. Ask user for expected container names, or
2. Use `docker compose config --services` to list services, then derive names

## Step 4: Allowed Domains (Optional)

If project needs external API access beyond defaults, create `.sidecar/allowed-domains.txt`:

```text
# Project-specific APIs
api.example.com
```

Default allowed: Anthropic services, GitHub (dynamic IPs), npm registry.

To disable network firewall entirely, remove the `cap_add` section from compose.yml.

## Step 5: Shadow Credential Files (Optional)

**Interactive credential shadowing workflow:**

### 5.1: Ask User

Ask the user: "Would you like to shadow credential files? This hides sensitive files (like `.env`, API keys, certificates) from Claude by mounting `/dev/null` over them. The files remain intact on your host but appear empty inside the container."

If user declines, skip to Step 6.

### 5.2: Discover Credentials

Scan for credential files using patterns from [references/credential-shadowing.md](references/credential-shadowing.md):

```bash
# Check gitignore patterns
grep -E '\.(env|pem|key|crt|credentials|secret)|\bsecrets?\b|\bcredentials?\b|\.npmrc|service.account' .gitignore .dockerignore 2>/dev/null

# Find actual files
find . -maxdepth 3 -type f \( -name ".env*" -o -name "*.pem" -o -name "*.key" -o -name "*credentials*" -o -name "*secret*" -o -name ".npmrc" -o -name "service-account*.json" \) 2>/dev/null | grep -v node_modules | grep -v vendor
```

### 5.3: Confirm with User

Present discovered files to user:

"I found these potential credential files:

- `.env`
- `.env.local`
- `config/secrets.yaml`

Which of these would you like to shadow? (You can select all, some, or none)"

### 5.4: Ask for Additional Files

After confirming discovered files, ask: "Are there any other sensitive files you'd like to shadow that I didn't find? (e.g., custom config files with API keys, database credentials)"

### 5.5: Apply Shadows

Add confirmed files as volume mounts in compose.yml:

```yaml
volumes:
  # Shadow credential files (appear empty to Claude)
  - /dev/null:/workspaces/<project-name>/.env:ro
  - /dev/null:/workspaces/<project-name>/.env.local:ro
```

See [references/credential-shadowing.md](references/credential-shadowing.md) for mount format and common files.

## Step 6: Mount Claude Credentials (Optional)

Credentials persist in the `claude-config` Docker volume. On first run, Claude prompts for authentication.

For MCP SSO support, extract and mount host credentials:

**macOS:**

```bash
security find-generic-password -s "Claude Code-credentials" -w > .credentials.json
```

**Linux:**

```bash
cp ~/.claude/.credentials.json .credentials.json
```

**Add to `.gitignore`:**

```text
.credentials.json
```

**Uncomment in compose.yml** the credentials mount line under the claude service volumes.

**Re-authenticate:** `docker volume rm <project>_claude-config`

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

## Step 7: Install Viewer (Optional)

**Interactive viewer setup workflow:**

### 7.1: Ask User

Ask the user: "Would you like to install the Claude Code Viewer? It provides a web interface to monitor Claude's activity in real-time."

If user declines, skip to Error Handling section.

### 7.2: Confirm Port

Ask the user: "Which port would you like the viewer to run on? (Default: 3000)"

### 7.3: Apply Configuration

Add viewer service from [references/viewer-setup.md](references/viewer-setup.md) with confirmed port.

Inform user: "Viewer will be accessible at `http://localhost:<port>` after starting containers."

## Error Handling

### No compose.yml exists

Create a new `compose.yml` with the services from Step 2.

### Container names unknown

If containers aren't running and names can't be determined:

1. List services with `docker compose config --services`
2. Derive names using pattern `<directory>-<service>-1`
3. Confirm with user before writing bridge config

### Bridge command failures

Bridge commands may fail silently if the target container isn't running or the command doesn't exist. The bridge does not currently provide error feedback - commands simply won't execute. Ensure containers are running before using bridge commands.

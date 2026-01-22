---
name: ai-dev-container-installer
description: "Set up AI Dev Container integration in any Docker-based project. Use when: user asks to 'add claude container', 'setup ai-dev-container', 'integrate claude container', 'add claude to docker compose', 'containerize claude', 'run claude in docker', 'add claude sidecar', or wants Claude Code running as a container service with bridge command routing to project containers."
---

# AI Dev Container Installer

Set up Claude Brain Sidecar to run Claude Code in a container that delegates commands to project containers via Docker socket proxy.

## Workflow

1. Analyze project structure (tech stack, existing compose file, containers)
2. Update/create compose.yml with required services
3. Create `.aidevcontainer/bridge.yaml` with command mappings
4. Optionally create `.aidevcontainer/allowed-domains.txt` for firewall
5. **Ask user about credential shadowing** → discover files → confirm selection → ask for missing → apply
6. Mount Claude credentials (macOS only)
7. **Ask user about viewer** → confirm port → apply configuration

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
      - claude-home:/home/claude/
      # Optional: Install Viewer (see Viewer (Optional))
      # - claude-config:/home/claude/.claude
      # Optional: shadow credentials (see Step 5)
      # - /dev/null:/workspaces/${PWD##*/}/.env:ro
      # Optional: mount Claude credentials for macOS (see Step 6)
      # - ./.credentials.json:/home/claude/.claude/.credentials.json:ro

volumes:
  claude-home:
  # Optional: Install Viewer (see Viewer (Optional))
  # claude-config:
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

### Container Name Resolution

Container names follow the format `<project>-<service>-1` where `<project>` is the directory name. If containers aren't running yet:

1. Ask user for expected container names, or
2. Use `docker compose config --services` to list services, then derive names

## Step 4: Allowed Domains (Optional)

If project needs external API access, create `.aidevcontainer/allowed-domains.txt`:

```text
# Package registries
registry.npmjs.org
pypi.org

# Project-specific APIs
api.example.com
```

Default allowed: Anthropic services, GitHub (auto-fetched), npm registry.

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
  - /dev/null:/workspaces/${PWD##*/}/.env:ro
  - /dev/null:/workspaces/${PWD##*/}/.env.local:ro
```

See [references/credential-shadowing.md](references/credential-shadowing.md) for mount format and common files.

## Step 6: Mount Claude Credentials (Optional - macOS)

On macOS, Claude Code stores credentials in the macOS Keychain. To use these credentials in the container:

**Export credentials:**

```bash
security find-generic-password -s "Claude Code-credentials" -w > .credentials.json
```

**Add to `.gitignore`:**

```text
.credentials.json
```

**Uncomment in compose.yml** the credentials mount line under the claude service volumes.

**Note:** The credentials file contains sensitive API keys. Never commit to version control.

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

1. Uncomment `claude-config` volume mount in claude service
2. Uncomment `claude-config:` in volumes section
3. Add viewer service from [references/viewer-setup.md](references/viewer-setup.md) with confirmed port

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

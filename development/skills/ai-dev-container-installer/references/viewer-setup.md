# Viewer Setup (Optional)

Add a viewer service for monitoring Claude's activity.

## Prerequisites

The viewer requires the `claude-config` volume. Ensure the claude service includes:

```yaml
volumes:
  - claude-config:/home/claude/.claude
```

## Viewer Service

Add to compose.yml:

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

## Access

After starting, access the viewer at `http://localhost:3000` (or configured port).

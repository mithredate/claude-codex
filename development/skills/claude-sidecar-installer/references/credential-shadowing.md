# Credential Shadowing

Hide sensitive credential files from Claude by mounting `/dev/null` over them. Files appear empty to Claude while remaining intact on the host.

## Discovering Credential Files

Check `.gitignore` and `.dockerignore` for credential patterns:

```bash
grep -E '\.(env|pem|key|crt|credentials|secret)|\bsecrets?\b|\bcredentials?\b|\.npmrc|service.account' .gitignore .dockerignore 2>/dev/null
```

Look for:

- `.env*` files (`.env`, `.env.local`, `.env.production`)
- `*.pem`, `*.key`, `*.crt` (certificates and keys)
- `*credentials*`, `*secrets*` (credential files)
- `.npmrc`, `.pypirc` (package manager auth)
- `service-account*.json` (cloud provider credentials)

Present discovered files to user when asking about credential shadowing.

## Applying Shadows

Add volume mounts to the claude service:

```yaml
volumes:
  # Shadow credential files (appear empty to Claude)
  - /dev/null:/workspaces/<project-name>/.env:ro
  - /dev/null:/workspaces/<project-name>/.credentials.json:ro
```

Replace `<project-name>` with the actual project directory name.

## Common Files to Shadow

- `.env`, `.env.local`, `.env.production`
- `.credentials.json`, `credentials.json`
- `secrets.yaml`, `secrets.json`
- `.npmrc` (if contains auth tokens)
- `service-account.json`

## User Instructions

To shadow additional files, add volume mounts in this format:

```yaml
- /dev/null:/workspaces/<project-name>/<path-to-sensitive-file>:ro
```

Example for a database config:

```yaml
- /dev/null:/workspaces/<project-name>/config/database.yml:ro
```

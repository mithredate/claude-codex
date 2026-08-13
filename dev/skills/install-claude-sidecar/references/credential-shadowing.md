# Credential Shadowing

Hide sensitive credential files from Claude by mounting `/dev/null` over them. Files appear empty to Claude while remaining intact on the host.

> Scope note: shadowing hides files from the *model's view of the workspace*. It does
> NOT isolate credentials the app's code needs at runtime (e.g. a `DATABASE_URL` env
> var) — that code runs in the same container and can read them. Credential isolation
> from the model is deferred future work in claude-sidecar.

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

Present discovered files to the user when asking about credential shadowing.

## Applying Shadows

Add volume mounts to the claude service. Use the project's real host path via
`${PWD}` (matching the `${PWD}:${PWD}` project mount). Mount writable (NOT `:ro` — a
read-only bind of `/dev/null` can fail on some setups):

```yaml
volumes:
  # Shadow credential files (appear empty to Claude)
  - /dev/null:${PWD}/.env
  - /dev/null:${PWD}/.credentials.json
```

## Common Files to Shadow

- `.env`, `.env.local`, `.env.production`
- `.credentials.json`, `credentials.json`
- `secrets.yaml`, `secrets.json`
- `.npmrc` (if it contains auth tokens)
- `service-account.json`

## User Instructions

To shadow additional files, add volume mounts in this format:

```yaml
- /dev/null:${PWD}/<path-to-sensitive-file>
```

Example for a database config:

```yaml
- /dev/null:${PWD}/config/database.yml
```

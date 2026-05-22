# Credential Shadowing

Reference for the install skill's Step 2 (discovery). The actual *mechanism* (how mounts get applied) is owned by `claude-sidecar gen-overlay` — this file is purely about pattern discovery.

## How shadows work (one paragraph)

The user's `.sidecar/shadow` file lists repo-relative paths. The host wrapper passes that list into `bridge gen-overlay`, which emits a `compose.sidecar.yml` that either bind-mounts `/dev/null` over each file or creates a `tmpfs` mount over each directory (trailing `/`). At container start, the entrypoint verifies every declared path is actually shadowed and refuses to start if not. So once a path is in `.sidecar/shadow`, three layers stop Claude from reading it: the kernel (mount), the entrypoint (refusal-on-drift), and the wrapper's drift warning.

## Discovering candidate sensitive files

### From gitignore patterns

```bash
grep -E '\.(env|pem|key|crt|credentials|secret)|\bsecrets?\b|\bcredentials?\b|\.npmrc|service.account' \
  .gitignore .dockerignore 2>/dev/null
```

### From filesystem name patterns

```bash
find . -maxdepth 3 -type f \( \
  -name ".env*" -o -name "*.pem" -o -name "*.key" -o -name "*.crt" \
  -o -name "*credentials*" -o -name "*secret*" \
  -o -name ".npmrc" -o -name ".pypirc" \
  -o -name "service-account*.json" \
\) 2>/dev/null | grep -vE 'node_modules|vendor|\.git/'
```

### Common file patterns to ask about

- `.env*` (`.env`, `.env.local`, `.env.production`, `.env.test`)
- `*.pem`, `*.key`, `*.crt` (certs and private keys)
- `*credentials*.json`, `*-credentials.json` (cloud provider creds)
- `secrets.yaml`, `secrets.json`, `.secrets/`
- `.npmrc`, `.pypirc` (package manager auth tokens)
- `service-account*.json` (Firebase / GCP service accounts)
- `firebase.json` (often contains hosting tokens)
- `.aws/credentials` (if vendored)
- `gcloud/`, `.gcloud/` (vendored gcloud configs)

### Common **directories** to ask about

- `secrets/`
- `config/secrets/`, `config/local/`
- `.aws/` (when committed for layout but values are sensitive)

## Writing `.sidecar/shadow`

One path per line, relative to the repo root. Trailing `/` means directory. Blank lines and `# comments` are skipped. Example:

```
# Environment secrets
.env
.env.local

# Firebase / cloud creds
firebase.json
service-account.json

# Encrypted secrets bundle (shadowed as tmpfs)
secrets/
```

Commit this file. It's the team's declaration of what counts as sensitive in this repo — and other projects that cross-mount this repo will respect the same list automatically.

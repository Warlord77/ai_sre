# opensre Issues

## 1. integrations.json written to wrong path

**Status:** Fixed (workaround)
**Command affected:** `opensre integrations setup <service>`, `opensre integrations list`

### Symptom

`opensre integrations list` shows "No integrations" even after running setup.
`opensre integrations verify postgresql` reports `missing — Not configured in local store or env.`

### Root Cause

opensre reads from `~/.opensre/integrations.json` (defined in `app/constants/__init__.py`).
The setup wizard writes config to `~/.config/opensre/integrations.json` — wrong directory.

### Fix

Copy the file to the correct path:

```bash
cp ~/.config/opensre/integrations.json ~/.opensre/integrations.json
```

---

## 2. `opensre integrations verify postgresql` — psycopg2 not installed

**Status:** Fixed
**Command affected:** `opensre integrations verify postgresql`

### Symptom

```
SERVICE    SOURCE       STATUS   DETAIL
postgresql local store  failed   PostgreSQL connection failed: psycopg2 is not installed.
```

### Root Cause

psycopg2 is an optional dependency not bundled with opensre. When installed via pipx,
the isolated venv lacks psycopg2 by default.

### Fix

```bash
pipx inject opensre psycopg2-binary
```

Note: issue 1 (wrong store path) must also be resolved — if opensre reads stale config from
the wrong directory, this error appears even after psycopg2 is injected.

---

## 3. `opensre integrations verify helm` — `helm version --client` fails

**Status:** Fixed (upstream source edit)
**Command affected:** `opensre integrations verify helm`

### Symptom

```
SERVICE  SOURCE       STATUS  DETAIL
helm     local store  failed  helm version --client failed (exit 1): Error: unknown flag: --client
```

### Root Cause

Helm v4 removed the `--client` flag. opensre calls `helm version --client` in
`app/services/helm/client.py:113`.

### Fix

In `/Users/one2n/work/stuff/opensre/app/services/helm/client.py` line 113, change:

```python
# before
code, ver_out, err = self._run(["version", "--client"], timeout=_PROBE_VERSION_TIMEOUT)

# after
code, ver_out, err = self._run(["version"], timeout=_PROBE_VERSION_TIMEOUT)
```

---

## 4. helm integration — wrong `helm_path` in stored config

**Status:** Fixed
**Command affected:** `opensre integrations verify helm`

### Symptom

```
SERVICE  SOURCE       STATUS   DETAIL
helm     local store  missing  Helm binary not found ('/tmp/helm-trace'). Install Helm or set helm_path to a binary.
```

### Root Cause

`~/.opensre/integrations.json` had `helm_path` set to `/tmp/helm-trace` (a stale/incorrect path).
Actual helm binary is at `/opt/homebrew/bin/helm`.

### Fix

Update `~/.opensre/integrations.json`:

```json
"helm_path": "/opt/homebrew/bin/helm"
```

Or re-run setup: `opensre integrations setup helm`

---

## 5. PostgreSQL port-forward — IPv6 resolution

**Status:** Workaround available

### Symptom

```
connection to server at "localhost" (::1), port 5432 failed
```

### Root Cause

macOS resolves `localhost` to `::1` (IPv6). PostgreSQL in Docker Desktop K8s listens on IPv4 only.

### Fix

Use `127.0.0.1` instead of `localhost` for host. For psql:

```bash
psql -h 127.0.0.1 -p 5432 -U app -d app
```

For opensre config, set `host` to `127.0.0.1` and `ssl_mode` to `disable`.

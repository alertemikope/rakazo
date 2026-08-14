#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.env"
PUBLIC_HOST="${1:-192.168.10.111}"
PUBLIC_ORIGIN="${RAKAZO_PUBLIC_ORIGIN:-http://${PUBLIC_HOST}:5173}"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
fi

python3 - "$ENV_FILE" "$PUBLIC_ORIGIN" <<'PY'
from pathlib import Path
import secrets
import sys

path = Path(sys.argv[1])
origin = sys.argv[2].rstrip("/")
lines = path.read_text().splitlines()
values = {}
for line in lines:
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        values[key] = value

def valid_secret(key: str, placeholder: str) -> str:
    value = values.get(key, "")
    if not value or value == placeholder:
        return secrets.token_hex(32)
    return value

updates = {
    "NODE_ENV": "production",
    "BETTER_AUTH_SECRET": valid_secret(
        "BETTER_AUTH_SECRET", "replace-with-32-plus-character-secret"
    ),
    "ENCRYPTION_KEY": valid_secret(
        "ENCRYPTION_KEY", "replace-with-64-char-hex-or-passphrase"
    ),
    "BETTER_AUTH_URL": origin,
    "API_URL": origin,
    "WEB_ORIGIN": origin,
    "SIGNUPS_ENABLED": "true",
    "SANDBOX_PROVIDER": "docker",
    "AGENT_RUNTIME": "pi",
    "WAKEUP_DRIVER": "graphile",
}

seen = set()
output = []
for line in lines:
    if line and not line.startswith("#") and "=" in line:
        key = line.split("=", 1)[0]
        if key in updates:
            output.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    output.append(line)
for key, value in updates.items():
    if key not in seen:
        output.append(f"{key}={value}")

path.write_text("\n".join(output) + "\n")
path.chmod(0o600)
PY

echo "Rakazo environment prepared for ${PUBLIC_ORIGIN}"
echo "Secrets were generated or preserved in $ENV_FILE (mode 600)."

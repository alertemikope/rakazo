#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="$ROOT/infra/compose/docker-compose.yml"
OVERRIDE="$ROOT/deploy/hitscan/docker-compose.override.yml"
PUBLIC_HOST="${RAKAZO_PUBLIC_HOST:-192.168.10.111}"
DOCKER=(sudo -n docker)

cd "$ROOT"

if [[ ! -f .env ]]; then
  "$ROOT/deploy/hitscan/prepare-env.sh" "$PUBLIC_HOST"
fi

compose() {
  "${DOCKER[@]}" compose --env-file "$ROOT/.env" -f "$BASE" -f "$OVERRIDE" "$@"
}

compose config --quiet
compose up -d --build --remove-orphans

deadline=$((SECONDS + 180))
health=""
until health="$(curl -fsS --max-time 5 http://127.0.0.1:3100/health 2>/dev/null)"; do
  if (( SECONDS >= deadline )); then
    compose ps
    compose logs --tail=120 api worker supervisor
    echo "Rakazo API did not become healthy within 180 seconds." >&2
    exit 1
  fi
  sleep 3
done

python3 - "$health" <<'PY'
import json
import sys

health = json.loads(sys.argv[1])
expected = {"runtime": "pi", "sandbox": "docker", "wakeup": "graphile"}
missing = {key: value for key, value in expected.items() if health.get(key) != value}
if missing:
    raise SystemExit(f"unexpected health response: {health}; expected {expected}")
print("API_HEALTH_OK", json.dumps(health, sort_keys=True))
PY

curl -fsS --max-time 5 http://127.0.0.1:5173/ >/dev/null

# API health alone can pass while the asynchronous worker is crash-looping.
sleep 5
for service in postgres supervisor api worker web; do
  container_id="$(compose ps -q "$service")"
  if [[ -z "$container_id" ]]; then
    echo "Missing Compose service: $service" >&2
    exit 1
  fi
  state="$("${DOCKER[@]}" inspect --format '{{.State.Status}}' "$container_id")"
  if [[ "$state" != "running" ]]; then
    compose logs --tail=120 "$service"
    echo "Compose service $service is $state, expected running." >&2
    exit 1
  fi
done

compose ps
echo "RAKAZO_DEPLOY_OK http://${PUBLIC_HOST}:5173"

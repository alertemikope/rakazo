#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="$ROOT/infra/compose/docker-compose.yml"
OVERRIDE="$ROOT/deploy/hitscan/docker-compose.override.yml"

cd "$ROOT"

sudo -n docker compose --env-file "$ROOT/.env" -f "$BASE" -f "$OVERRIDE" \
  exec -T supervisor node --input-type=module <<'JS'
const base = "http://127.0.0.1:7091";
const botId = "hitscan-smoke-computer";
const workspaceId = "hitscan-smoke-workspace";
const token = process.env.SANDBOX_SUPERVISOR_TOKEN || process.env.BETTER_AUTH_SECRET;
if (!token) throw new Error("supervisor token is unavailable");

const headers = {
  authorization: `Bearer ${token}`,
  "content-type": "application/json",
  "x-rakazo-bot-id": botId,
  "x-rakazo-workspace-id": workspaceId,
};

let computerId;
try {
  const health = await fetch(`${base}/health`).then((response) => response.json());
  if (!health.ok || health.image !== "rakazo/computer:local") {
    throw new Error(`unexpected supervisor health: ${JSON.stringify(health)}`);
  }

  const createdResponse = await fetch(`${base}/computers`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      botId,
      workspaceId,
      homePath: `/data/homes/${botId}`,
    }),
  });
  const created = await createdResponse.json();
  if (!createdResponse.ok || !created.id || !created.screenUrl) {
    throw new Error(`computer create failed: ${JSON.stringify(created)}`);
  }
  computerId = created.id;

  let executed;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const execResponse = await fetch(`${base}/computers/${computerId}/exec`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        argv: [
          "bash",
          "-lc",
          "test \"$DISPLAY\" = :1 && xdpyinfo >/dev/null && xdotool search --class Chromium >/dev/null && echo COMPUTER_OK",
        ],
      }),
    });
    executed = await execResponse.json();
    if (execResponse.ok && executed.code === 0 && executed.stdout.includes("COMPUTER_OK")) {
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (executed?.code !== 0 || !executed?.stdout?.includes("COMPUTER_OK")) {
    throw new Error(`computer exec failed after readiness wait: ${JSON.stringify(executed)}`);
  }

  let desktopReady = false;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    try {
      const desktop = await fetch(created.screenUrl);
      desktopReady = desktop.ok && (await desktop.text()).includes("Rakazo computer");
      if (desktopReady) break;
    } catch {
      // Chromium/noVNC can need a moment after container start.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (!desktopReady) throw new Error(`noVNC did not become ready at ${created.screenUrl}`);

  console.log("COMPUTER_SMOKE_OK", JSON.stringify({ id: computerId, screen: created.screenUrl }));
} finally {
  if (computerId) {
    await fetch(`${base}/computers/${computerId}`, { method: "DELETE", headers }).catch(
      () => undefined,
    );
  }
}
JS

sudo -n rm -rf "$ROOT/data/homes/hitscan-smoke-computer"

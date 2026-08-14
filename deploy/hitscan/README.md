# hitscan deployment

This is the single-host deployment used on the private Linux machine
`hitscan` (`192.168.10.111`). It keeps the complete Rakazo control plane and
all per-bot graphical computers on that machine.

## Why this host

- Native Linux Docker instead of Docker Desktop virtualization.
- Always-on host with enough CPU, memory, and disk for several persistent bot
  homes.
- One isolated Docker computer per bot, including Chromium, Xvfb, x11vnc,
  noVNC, and `xdotool` computer control.
- No E2B, Box, or Rakazo-operated VM service is required.

## Deploy

```bash
./deploy/hitscan/prepare-env.sh 192.168.10.111
./deploy/hitscan/deploy.sh
```

The first command generates or preserves local secrets without printing them.
The second validates Compose, builds the application and graphical computer
images, applies database migrations, starts the services with restart policies,
and checks that the API reports Pi + Docker + Graphile.

Validate the real per-bot computer path after deployment:

```bash
./deploy/hitscan/smoke-computer.sh
```

The smoke test creates an isolated bot computer, verifies X11, Chromium and
noVNC, then removes the test container and home.

Open `http://192.168.10.111:5173`. The first account becomes deployment owner.
Model subscriptions can then be connected through Rakazo's onboarding.

Do not commit `.env` or `data/`.

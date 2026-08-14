FROM node:22-bookworm
RUN corepack enable
WORKDIR /app
COPY . .
RUN pnpm install --frozen-lockfile=false
RUN pnpm --filter @rakazo/db generate
# The Vite config validates its runtime proxy secret. The build only emits
# static client assets, so use an explicit build-only value instead of copying
# the deployment .env (which is excluded by .dockerignore).
RUN BETTER_AUTH_SECRET=rakazo-build-only-secret-not-used-at-runtime \
    pnpm --filter @rakazo/web build
ENV NODE_ENV=production
EXPOSE 3100 5173 7091
CMD ["pnpm", "--filter", "@rakazo/api", "start"]

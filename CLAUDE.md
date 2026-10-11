# CLAUDE.md: Infra

Deployment files for the six-project portfolio platform (Kavach, Hisaab, Dwaarpal, Karya, Sutra, Sanjeevani) on one free Oracle Cloud ARM VM.

- **Source of truth:** the PDF `~/Downloads/Portfolio Projects Complete Build & Free Deployment Plan.pdf` (Steps 4, 5, 7, 8).
- **Progress and deviations:** `../PROGRESS.md`. Log any change to the PDF's design under "Deviations from the plan". Push after every verified change.

## Contents (PDF Step 4)
- `docker-compose.yml`: Caddy, PostgreSQL 16 + pgvector, Redis 7, a locked-down Docker API proxy, 11 app containers (APIs, workers, relay, monitor), 6 static UI containers.
- `Caddyfile`: HTTPS for `api.<domain>` (Dwaarpal), one UI host per project, `status.<domain>` (Sanjeevani). UI hosts send `/api/*` to Dwaarpal with the demo key added server side.
- `.env.example`, `postgres/init/01-init.sh` (one user + one database per project, `vector` extension in `sutra`), `scripts/deploy.sh`, `scripts/backup.sh`, `scripts/smoke-test.sh`.

## Rules
- Never commit `.env`; only `.env.example`. Fill passwords with `openssl rand -hex 24`. `GH_USER` must be lowercase. If the local `.env` is lost while the stack runs, `docker inspect postgres` still holds every value.
- `docker-compose.override.yml` is for local runs only and must not reach the server (gitignored; copy it from `docker-compose.override.example.yml`).
- Only Caddy publishes ports (80, 443) in production. Every container has a `mem_limit`; app containers rotate logs (10 MB × 3).
- `docker-proxy` allows only container list/inspect and restart, on an internal network shared only with Sanjeevani. Set `DOCKER_GID` to the socket's group on the server.
- Images: `ghcr.io/${GH_USER}/<project>:${TAG}` and `<project>-ui`. CI pushes `latest` and the commit SHA.
- `deploy.sh`: lock, pull, start postgres + redis, `alembic upgrade head` per app (stops on the first failure), `up -d --remove-orphans`, prune images.
- Rollback one service: `docker pull ghcr.io/<user>/kavach:<old-sha>`, `docker tag ... :latest`, `docker compose up -d kavach`.

## Local run (PDF Step 5)
```bash
cp .env.example .env && cp docker-compose.override.example.yml docker-compose.override.yml   # fill the passwords
docker compose up -d --build && ./scripts/deploy.sh && docker compose ps && ./scripts/smoke-test.sh
```

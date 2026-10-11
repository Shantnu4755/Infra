#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Six repos deploy through this one script; never run two at once.
if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/portfolio-deploy.lock
  flock 9
fi

export TAG="${TAG:-latest}"
docker compose pull --ignore-buildable   # skips locally built images
docker compose up -d postgres redis

# migrations first; stop the deploy if any fails
for app in kavach karya hisaab dwaarpal sutra sanjeevani; do
  service="$app"; [ "$app" = "karya" ] && service="karya-api"
  docker compose run --rm "$service" alembic upgrade head
done

docker compose up -d --remove-orphans
docker image prune -f                    # keeps disk usage low
docker compose ps

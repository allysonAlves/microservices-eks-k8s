#!/bin/bash
# Copies Dockerfiles from dockerfiles/ into each service directory.
# Optional — only needed if you want to commit the Dockerfile to the service repo.
# docker-compose and push-images.sh use the Dockerfile inside each services/<name>/ directly.
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

for service in auth-service flag-service targeting-service evaluation-service analytics-service; do
  src="${PROJECT_ROOT}/dockerfiles/${service}.Dockerfile"
  dst="${PROJECT_ROOT}/services/${service}/Dockerfile"

  if [ ! -d "${PROJECT_ROOT}/services/${service}" ]; then
    echo "  [skip] services/${service} nao encontrado — rode ./setup.sh primeiro"
    continue
  fi

  cp "$src" "$dst"
  echo "  [ok] dockerfiles/${service}.Dockerfile -> services/${service}/Dockerfile"
done

echo ""
echo "Dockerfiles copiados. Para commitar em cada repo:"
echo "  git -C services/<nome> add Dockerfile && git -C services/<nome> commit -m 'Add Dockerfile' && git -C services/<nome> push"

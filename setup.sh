#!/bin/bash
set -e

# Replace with your GitHub username after forking the repositories
GITHUB_USER="lara-portilho"

clone_or_pull() {
  local repo=$1
  local dir=$2
  if [ -d "$dir/.git" ]; then
    echo "  [pull] $dir"
    git -C "$dir" pull --ff-only
  else
    echo "  [clone] $repo -> $dir"
    rm -rf "$dir"
    git clone "$repo" "$dir"
  fi
}

ensure_go_sum() {
  local dir=$1
  if [ -f "$dir/go.mod" ]; then
    # Remove invalid subpackage entries from go.mod (e.g. pgx/v4/stdlib is a package, not a module)
    sed -i.bak '/jackc\/pgx\/v4\/stdlib/d' "$dir/go.mod" && rm -f "$dir/go.mod.bak"
  fi
  if [ -f "$dir/go.mod" ] && [ ! -f "$dir/go.sum" ]; then
    echo "  [go mod tidy] $dir (go.sum ausente)"
    docker run --rm -v "$(pwd)/$dir":/app -w /app golang:1.21-alpine go mod tidy
  fi
}

echo "==> Cloning microservices from forks..."
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-auth-service"        services/auth-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-flag-service"         services/flag-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-targeting-service"    services/targeting-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-evaluation-service"   services/evaluation-service
clone_or_pull "https://github.com/${GITHUB_USER}/FIAP-DevOps-analytics-service"    services/analytics-service

echo ""
echo "==> Aplicando patches conhecidos nos serviços..."

# auth-service: go.mod tem entrada inválida; handlers.go/key.go/main.go têm imports incorretos
ensure_go_sum "services/auth-service"

HANDLERS="services/auth-service/handlers.go"
if [ -f "$HANDLERS" ]; then
  sed -i.bak '/"crypto\/sha256"/d' "$HANDLERS"
  sed -i.bak '/"encoding\/hex"/d' "$HANDLERS"
  rm -f "$HANDLERS.bak"
  echo "  [patch] $HANDLERS (imports não usados removidos)"
fi

KEY_GO="services/auth-service/key.go"
if [ -f "$KEY_GO" ]; then
  sed -i.bak '/"fmt"/d' "$KEY_GO"
  rm -f "$KEY_GO.bak"
  echo "  [patch] $KEY_GO (import fmt removido)"
fi

MAIN_GO="services/auth-service/main.go"
if [ -f "$MAIN_GO" ]; then
  sed -i.bak '/"fmt"/d' "$MAIN_GO"
  sed -i.bak 's|"github.com/jackc/pgx/v4/stdlib"|_ "github.com/jackc/pgx/v4/stdlib"|' "$MAIN_GO"
  rm -f "$MAIN_GO.bak"
  echo "  [patch] $MAIN_GO (fmt removido, stdlib como blank import)"
fi

# evaluation-service: evaluator.go importa "context" (não usa) e usa os.Getenv sem importar "os"
EVALUATOR="services/evaluation-service/evaluator.go"
if [ -f "$EVALUATOR" ]; then
  sed -i.bak 's|"context"||' "$EVALUATOR"
  if ! grep -q '"os"' "$EVALUATOR"; then
    sed -i.bak 's|"net/http"|"net/http"\n\t"os"|' "$EVALUATOR"
  fi
  rm -f "$EVALUATOR.bak"
  echo "  [patch] $EVALUATOR (imports corrigidos)"
fi
ensure_go_sum "services/evaluation-service"

# flag-service, targeting-service e analytics-service: Werkzeug não pinado, pip instala v3.x que removeu url_quote
for svc in services/flag-service services/targeting-service services/analytics-service; do
  REQ="$svc/requirements.txt"
  if [ -f "$REQ" ] && ! grep -q "Werkzeug" "$REQ"; then
    sed -i.bak 's|Flask==2.2.2|Flask==2.2.2\nWerkzeug==2.3.7|' "$REQ"
    rm -f "$REQ.bak"
    echo "  [patch] $REQ (Werkzeug==2.3.7 adicionado)"
  fi
done

echo ""
echo "Done! Run: docker compose up --build"

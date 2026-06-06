#!/bin/bash
# Creates a new API key in auth-service and updates configs for the target environment.
# Usage: ./setup-service-key.sh [local|aws]   (default: aws)
set -e

ENV=${1:-aws}
NAMESPACE="togglemaster"
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERRO: arquivo .env nao encontrado. Copie .env.example para .env e preencha os valores."
  exit 1
fi

set -a; source "$ENV_FILE"; set +a

if [ -z "$MASTER_KEY" ] || [ "$MASTER_KEY" = "change-me-use-a-strong-secret" ]; then
  echo "ERRO: MASTER_KEY nao configurada no .env"
  exit 1
fi

if [ "$ENV" = "local" ]; then
  AUTH_URL="http://localhost:8001"
else
  echo "==> Obtendo URL do Load Balancer..."
  ELB=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -z "$ELB" ]; then
    echo "ERRO: Ingress nao encontrado. Execute 'terraform apply' e aguarde os pods subirem."
    exit 1
  fi
  AUTH_URL="http://${ELB}/auth"
fi

echo "==> Criando API key em $AUTH_URL..."
RESPONSE=$(curl -s -X POST "${AUTH_URL}/admin/keys" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name": "service-key"}')

NEW_KEY=$(echo "$RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

if [ -z "$NEW_KEY" ]; then
  echo "ERRO: Nao foi possivel extrair a key. Resposta: $RESPONSE"
  exit 1
fi

echo "==> Key gerada: $NEW_KEY"

# Atualiza .env
if grep -q "^SERVICE_API_KEY=" "$ENV_FILE"; then
  sed -i.bak "s|^SERVICE_API_KEY=.*|SERVICE_API_KEY=${NEW_KEY}|" "$ENV_FILE" && rm "${ENV_FILE}.bak"
else
  echo "SERVICE_API_KEY=${NEW_KEY}" >> "$ENV_FILE"
fi

# Atualiza terraform.tfvars para manter em sincronia
TFVARS="$(cd "$(dirname "$0")" && pwd)/terraform/terraform.tfvars"
if [ -f "$TFVARS" ]; then
  sed -i.bak "s|^service_api_key = .*|service_api_key = \"${NEW_KEY}\"|" "$TFVARS" && rm "${TFVARS}.bak"
fi

if [ "$ENV" = "local" ]; then
  echo "==> Reiniciando evaluation-service..."
  docker compose up -d evaluation-service
  echo ""
  echo "Concluido! Atualize api_key no Insomnia (ambiente Local): $NEW_KEY"
else
  echo "==> Atualizando secret no Kubernetes..."
  kubectl patch secret evaluation-service-secrets -n "$NAMESPACE" \
    -p "{\"data\":{\"SERVICE_API_KEY\":\"$(echo -n "$NEW_KEY" | base64)\"}}"

  echo "==> Reiniciando evaluation-service..."
  kubectl rollout restart deployment/evaluation-service -n "$NAMESPACE"
  kubectl rollout status deployment/evaluation-service -n "$NAMESPACE"

  echo ""
  echo "Concluido! Atualize api_key no Insomnia (ambiente AWS): $NEW_KEY"
fi

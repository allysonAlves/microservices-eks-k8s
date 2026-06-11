# ToggleMaster — Fase 2

Ecossistema de 5 microsserviços implantado no Kubernetes (AWS EKS) com infraestrutura provisionada via Terraform.

## Arquitetura

| Serviço | Linguagem | Porta | Dependência |
|---|---|---|---|
| auth-service | Go | 8001 | PostgreSQL |
| flag-service | Python | 8002 | PostgreSQL + auth-service |
| targeting-service | Python | 8003 | PostgreSQL + auth-service |
| evaluation-service | Go | 8004 | Redis + flag-service + targeting-service |
| analytics-service | Python | 8005 | AWS SQS + DynamoDB |

---

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurado (`aws configure`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Git](https://git-scm.com/)
- [hey](https://github.com/rakyll/hey) — gerador de carga para testes de HPA (`brew install hey`)

---

## Setup inicial (uma vez)

### 1. Configurar variáveis de ambiente

```bash
cp .env.example .env
```

Edite o `.env` e defina `MASTER_KEY` com o mesmo valor de `auth_master_key` no `terraform/terraform.tfvars`:

```bash
MASTER_KEY=a835a32fc3fb25b14ed18627ab603b9bd60ea1ce3415f41c
SERVICE_API_KEY=   # deixe em branco — o setup-service-key.sh preencherá automaticamente
```

### 2. Clonar os microsserviços

Abra o `setup.sh` e ajuste o usuário do GitHub:

```bash
# setup.sh — linha 5
GITHUB_USER="seu_usuario_aqui"
```

Depois rode:

```bash
./setup.sh
```

> **O `setup.sh` aplica automaticamente os patches abaixo.** Eles estão documentados aqui por transparência — os repositórios dos serviços possuem bugs conhecidos que impedem o build sem correção.

### Patches aplicados automaticamente pelo setup.sh

#### auth-service — múltiplos erros de imports e `go.mod` inválido

**1. `go.mod`** contém entrada incorreta:

```
github.com/jackc/pgx/v4/stdlib v4.18.3 // indirect
```

`stdlib` é um pacote dentro do módulo `github.com/jackc/pgx/v4`, não um módulo separado. **Correção:** remover essa linha.

**2. `handlers.go`** importa `"crypto/sha256"` e `"encoding/hex"`, que são usados em `key.go`, não aqui. **Correção:** remover esses dois imports.

**3. `key.go`** importa `"fmt"` sem usar. **Correção:** remover o import.

**4. `main.go`** importa `"fmt"` sem usar e importa `"github.com/jackc/pgx/v4/stdlib"` de forma errada — esse pacote é usado apenas para registrar o driver como efeito colateral, portanto precisa de blank import. **Correção:** remover `"fmt"` e trocar o import do stdlib por `_ "github.com/jackc/pgx/v4/stdlib"`.

#### evaluation-service — `evaluator.go` com imports incorretos

- `"context"` está importado mas nunca usado
- `os.Getenv(...)` é chamado no arquivo, mas `"os"` não está nos imports

**Correção:** remover `"context"` e adicionar `"os"` nos imports.

#### flag-service e targeting-service — incompatibilidade Flask 2.2 + Werkzeug 3.x

Os `requirements.txt` de ambos os serviços declaram `Flask==2.2.2` sem pinar o Werkzeug. O pip resolve para a versão mais recente (3.x), que removeu `url_quote` — função ainda usada pelo Flask 2.2. Isso causa o erro em runtime:

```
ImportError: cannot import name 'url_quote' from 'werkzeug.urls'
```

**Correção:** adicionar `Werkzeug==2.3.7` (última versão 2.x) ao `requirements.txt` de ambos os serviços.

---

## Rodar local

```bash
# 1. Sobe os 9 containers (5 apps + 2 PostgreSQL + Redis + DynamoDB Local)
docker compose up --build -d

# 2. Cria a API key e configura o evaluation-service automaticamente
./setup-service-key.sh local

# 3. Atualize o campo api_key no Insomnia com o valor exibido pelo script
#    e selecione o ambiente "Local"
```

Teste os health checks:

```bash
curl http://localhost:8001/health   # auth-service
curl http://localhost:8002/health   # flag-service
curl http://localhost:8003/health   # targeting-service
curl http://localhost:8004/health   # evaluation-service
curl http://localhost:8005/health   # analytics-service
```

Para parar:

```bash
docker compose down -v
```

---

## Rodar na AWS

```bash
# 1. Provisiona toda a infraestrutura (~15-25 min)
cd terraform
terraform init
terraform apply -auto-approve
cd ..

# 2. Configura o kubectl
aws eks update-kubeconfig --region us-east-1 --name togglemaster-cluster

# 3. Build e push das imagens para o ECR
./push-images.sh

# 4. Aguarde todos os pods ficarem prontos (~2-5 min após o push)
kubectl rollout status deployment/auth-service -n togglemaster
kubectl rollout status deployment/flag-service -n togglemaster
kubectl rollout status deployment/targeting-service -n togglemaster
kubectl rollout status deployment/evaluation-service -n togglemaster
kubectl rollout status deployment/analytics-service -n togglemaster

# 5. Cria a API key e configura o evaluation-service automaticamente
./setup-service-key.sh aws

# 6. Atualize o campo api_key no Insomnia com o valor exibido pelo script
#    e selecione o ambiente "AWS"
```

Verifique os pods:

```bash
kubectl get pods -n togglemaster
kubectl get ingress -n togglemaster
kubectl get hpa -n togglemaster
```

---

## Demonstrar escalabilidade

Um único teste exercita o pipeline completo:  
**hey → evaluation-service (CPU ↑ → HPA escala) → SQS → analytics-service (CPU ↑ → HPA escala) → DynamoDB**

```bash
# Obtém a URL do Load Balancer
LB_URL=$(kubectl get ingress -n togglemaster -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Terminal 1 — gera carga no endpoint real de avaliação
hey -z 3m -c 200 \
  "http://$LB_URL/evaluate/evaluate?user_id=user-test&flag_name=dark-mode"

# Terminal 2 — observa os dois HPAs escalando em tempo real
kubectl get hpa -n togglemaster -w

# Após o teste — confirma eventos gravados no DynamoDB
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --select COUNT
```

---

## Destruir a infraestrutura

```bash
./teardown.sh
```

---

## Scripts

| Script | Descrição |
|---|---|
| `setup.sh` | Clona os repositórios dos microsserviços |
| `push-images.sh` | Build e push das imagens Docker para o ECR |
| `setup-service-key.sh local` | Cria API key no ambiente local e reinicia o evaluation-service |
| `setup-service-key.sh aws` | Cria API key no ambiente AWS e atualiza o secret do Kubernetes |
| `teardown.sh` | Remove toda a infraestrutura AWS (LB + terraform destroy) |
| `copy-dockerfiles.sh` | Copia os Dockerfiles de `dockerfiles/` para dentro de cada `services/<nome>/` |

---

## Estrutura do projeto

```
.
├── .env.example                # variáveis de ambiente (copie para .env)
├── docker-compose.yml          # ambiente local (9 containers)
├── setup.sh                    # clona os repositórios dos serviços
├── push-images.sh              # build e push para ECR
├── setup-service-key.sh        # configura a API key em qualquer ambiente
├── scripts/
│   └── init-flags-targeting.sql
├── services/
│   ├── auth-service/
│   ├── flag-service/
│   ├── targeting-service/
│   ├── evaluation-service/
│   └── analytics-service/
└── terraform/
    ├── main.tf                 # providers (aws, kubernetes, helm)
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── vpc.tf                  # VPC, subnets, NAT, security groups
    ├── eks.tf                  # cluster EKS 1.32 + node group + IAM
    ├── ecr.tf                  # 5 repositórios ECR
    ├── rds.tf                  # 3 instâncias RDS PostgreSQL
    ├── elasticache.tf          # Redis ElastiCache
    ├── dynamodb.tf             # tabela DynamoDB
    ├── sqs.tf                  # fila SQS
    ├── helm.tf                 # Metrics Server + Nginx Ingress
    └── k8s.tf                  # Namespace, Secrets, ConfigMaps, Deployments,
                                # Services, Ingress, HPA
```

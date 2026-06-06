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

---

## Rodar local

```bash
# 1. Sobe os 9 containers (5 apps + 2 PostgreSQL + Redis + DynamoDB Local)
docker compose up --build

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

# 4. Cria a API key e configura o evaluation-service automaticamente
./setup-service-key.sh aws

# 5. Atualize o campo api_key no Insomnia com o valor exibido pelo script
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

### HPA do evaluation-service (por CPU)

```bash
# Terminal 1 — gera carga
hey -z 2m -c 50 http://<LB_URL>/evaluate/health

# Terminal 2 — observa o HPA escalar
kubectl get hpa -n togglemaster -w
```

### HPA do analytics-service (por CPU via fila SQS)

```bash
# Envia 50 mensagens para a fila
SQS_URL=$(cd terraform && terraform output -raw sqs_queue_url)
for i in $(seq 1 50); do
  aws sqs send-message \
    --queue-url "$SQS_URL" \
    --message-body "{\"user_id\":\"user-$i\",\"flag_name\":\"test-flag\",\"result\":true}"
done

# Observa o HPA
kubectl get hpa analytics-service-hpa -n togglemaster -w

# Verifica dados no DynamoDB
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1
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

# Roteiro do Vídeo — Tech Challenge Fase 2

> **Escopo:** demonstração completa — projeto rodando **local** (docker compose) e em **produção na AWS** (Kubernetes/EKS).
> **Duração alvo:** ~16-18 min (dentro do limite de 20 min do PDF).
> **Antes de gravar:** ambiente local no ar, infra AWS no ar, pods prontos, `kubectl` configurado. Veja o checklist no fim.

---

## Preparação (NÃO gravar — fazer antes)

### Ambiente local
```bash
# Sobe os 9 containers (5 apps + 2 PostgreSQL + Redis + DynamoDB Local)
docker compose up --build -d

# Cria a API key e configura o evaluation-service local
./setup-service-key.sh local
```

### Ambiente AWS
```bash
# Configura o kubectl
aws eks update-kubeconfig --region us-east-1 --name togglemaster-cluster

# Build + push das imagens pro ECR
./push-images.sh

# Espera os pods subirem
kubectl rollout status deployment/auth-service       -n togglemaster
kubectl rollout status deployment/flag-service       -n togglemaster
kubectl rollout status deployment/targeting-service  -n togglemaster
kubectl rollout status deployment/evaluation-service -n togglemaster
kubectl rollout status deployment/analytics-service  -n togglemaster

# Cria a API key e configura o evaluation-service
./setup-service-key.sh aws
```

**Deixe pronto antes de gravar:**
- Terminais abertos com fonte grande (legível no vídeo).
- A URL do Load Balancer já em uma variável (veja Bloco 5).
- Insomnia/Postman com os ambientes "Local" e "AWS" configurados e as `api_key` atualizadas.
- `hey` instalado (`brew install hey`).
- Aba do console AWS aberta no DynamoDB (pra mostrar os dados no final).

---

## BLOCO 1 — Abertura e arquitetura (≈2 min)

**Mostrar:** sua voz + um diagrama da arquitetura (slide simples ou o desenho do README).

**Falar (roteiro):**
> "Olá! Nesta demonstração vou apresentar o ToggleMaster, um sistema de feature flags que foi reescrito como um ecossistema de 5 microsserviços. Vou mostrar primeiro o projeto rodando localmente e, em seguida, rodando em produção na AWS sobre Kubernetes (EKS).
>
> A arquitetura tem 5 microsserviços:
> - **auth-service** (Go) — gerencia chaves de API e autenticação, com PostgreSQL;
> - **flag-service** (Python) — CRUD das feature flags, com PostgreSQL;
> - **targeting-service** (Python) — regras de segmentação, com PostgreSQL;
> - **evaluation-service** (Go) — o *hot path* de alta performance que devolve a decisão true/false, usando Redis como cache;
> - **analytics-service** (Python) — consome eventos de uma fila SQS e grava no DynamoDB.
>
> No diagrama dá pra ver como eles se comunicam e quais data stores cada um usa: PostgreSQL para dados relacionais, Redis como cache no caminho quente, e SQS + DynamoDB para o pipeline de analytics."

---

## BLOCO 2 — Projeto rodando local (docker compose + Postman/Insomnia) (≈3 min)

**Mostrar:** os 9 containers no ar e chamadas reais pelo Insomnia/Postman.

```bash
# Mostra os 9 containers rodando (5 apps + 2 PostgreSQL + Redis + DynamoDB Local)
docker compose ps
```

Depois, no **Insomnia/Postman** (ambiente "Local"), faça uma sequência de chamadas que prove o fluxo de negócio:

```bash
# (alternativa via terminal) health checks dos 5 serviços
curl -s http://localhost:8001/health   # auth-service
curl -s http://localhost:8002/health   # flag-service
curl -s http://localhost:8003/health   # targeting-service
curl -s http://localhost:8004/health   # evaluation-service
curl -s http://localhost:8005/health   # analytics-service
```

**Sugestão de fluxo no Insomnia (mais rico que health check):**
1. Criar uma feature flag no **flag-service**.
2. (Opcional) Criar uma regra de segmentação no **targeting-service**.
3. Fazer um **evaluate** no evaluation-service e mostrar a resposta `true/false`.

**Falar:**
> "Primeiro, o ambiente local. Com um único `docker compose` eu subo os 9 containers: os 5 microsserviços mais os 4 bancos de dados locais — dois PostgreSQL, um Redis e o DynamoDB Local. Isso prova que todo o ecossistema roda de ponta a ponta na máquina.
>
> Agora vou fazer chamadas reais pelo Insomnia: crio uma feature flag, e em seguida faço uma avaliação no evaluation-service, que me devolve a decisão final. Reparem que a chamada passa pela autenticação por API key e retorna o resultado — o fluxo completo funcionando localmente."

---

## BLOCO 3 — Recursos provisionados na AWS (≈2 min)

**Mostrar:** rapidamente, no console AWS (ou via AWS CLI) confirmando que os recursos existem.

```bash
# Opção via terminal (rápido e objetivo)
aws eks describe-cluster --name togglemaster-cluster --region us-east-1 --query 'cluster.status' --output text
aws rds describe-db-instances --region us-east-1 --query 'DBInstances[].DBInstanceIdentifier' --output text
aws elasticache describe-cache-clusters --region us-east-1 --query 'CacheClusters[].CacheClusterId' --output text
aws dynamodb list-tables --region us-east-1 --query 'TableNames' --output text
aws sqs list-queues --region us-east-1 --query 'QueueUrls' --output text
aws ecr describe-repositories --region us-east-1 --query 'repositories[].repositoryName' --output text
```

Ou no console, mostre brevemente:
- **EKS** → cluster `togglemaster-cluster` ativo.
- **RDS** → 3 instâncias PostgreSQL.
- **ElastiCache** → 1 cluster Redis.
- **DynamoDB** → tabela `ToggleMasterAnalytics`.
- **SQS** → fila `togglemaster-analytics-events`.
- **ECR** → 5 repositórios com imagens.

**Falar:**
> "Agora, o ambiente de produção na AWS. Aqui estão os recursos provisionados: o cluster EKS, as 3 instâncias RDS independentes — uma por serviço que precisa de Postgres —, o Redis no ElastiCache, a tabela do DynamoDB, a fila SQS e os 5 repositórios ECR com as imagens já publicadas."

---

## BLOCO 4 — Cluster, Pods e Namespaces (≈2 min)

**Mostrar:**

```bash
kubectl get nodes
kubectl get namespaces
kubectl get pods -n togglemaster -o wide
kubectl get svc -n togglemaster
```

**Falar:**
> "O cluster está com os nós ativos. As aplicações estão organizadas em namespace próprio (`togglemaster`), seguindo a boa prática de separação lógica pedida no desafio. Aqui vemos os 5 microsserviços rodando como Pods, todos em estado Running, e os Services do tipo ClusterIP que expõem cada um internamente."

> Aproveite pra mencionar: "Cada Deployment usa **requests e limits** de CPU/memória, e **readiness/liveness probes** no endpoint `/health` — boas práticas exigidas no enunciado."
> (Pra provar visualmente: `kubectl describe pod -n togglemaster -l app=auth-service | grep -iE "Liveness|Readiness"`)

---

## BLOCO 5 — Acesso externo via Ingress (≈2 min)

**Mostrar:**

```bash
# Pega a URL do Load Balancer
LB_URL=$(kubectl get ingress -n togglemaster -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo "$LB_URL"

kubectl get ingress -n togglemaster
```

Em seguida, prove o roteamento por path com chamadas reais (curl e/ou Insomnia):

```bash
# Health checks via Ingress, provando o roteamento por rota
curl -s "http://$LB_URL/auth/health";       echo
curl -s "http://$LB_URL/flags/health";      echo
curl -s "http://$LB_URL/targeting/health";  echo
curl -s "http://$LB_URL/evaluate/health";   echo
```

> Se preferir, mostre uma chamada de negócio real no Insomnia (ambiente "AWS": criar uma flag, fazer um evaluate) com a `api_key` configurada — fica mais rico que só health check.

**Falar:**
> "O acesso externo é feito pelo Nginx Ingress, que provisionou esse Load Balancer na AWS. O Ingress roteia por path: `/auth` vai pro auth-service, `/flags` pro flag-service, e assim por diante. Vou fazer chamadas reais pra cada rota pra provar que o roteamento e os serviços estão respondendo."

---

## BLOCO 6 — Escalabilidade do evaluation-service (HPA por CPU) (≈3 min)

**Mostrar:** dois terminais lado a lado.

**Terminal A** (observação, deixe rodando):
```bash
watch -n 2 kubectl get hpa,pods -n togglemaster
# ou, se preferir o stream:
# kubectl get hpa -n togglemaster -w
```

**Terminal B** (gera carga no endpoint real de avaliação):
```bash
LB_URL=$(kubectl get ingress -n togglemaster -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

hey -z 3m -c 200 \
  "http://$LB_URL/evaluate/evaluate?user_id=user-test&flag_name=dark-mode"
```

**Falar (enquanto a carga sobe):**
> "Agora vou demonstrar a escalabilidade. Estou gerando carga no evaluation-service com a ferramenta `hey` — 200 conexões concorrentes por 3 minutos, batendo no endpoint real de avaliação.
>
> No terminal da esquerda, observem o HPA do evaluation-service: conforme a CPU ultrapassa os 30% configurados, o HPA vai criando réplicas adicionais automaticamente (até o máximo de 4). Reparem nos Pods novos passando de Pending pra Running."

> Espere aparecer pelo menos 1-2 réplicas novas antes de seguir. Aponte na tela: "Saiu de 1 réplica pra N — o autoscaling está funcionando."

---

## BLOCO 7 — Escalabilidade do analytics-service + SQS + DynamoDB (≈4 min)

> Este bloco cobre 3 bullets do PDF de uma vez: **envio manual ao SQS**, **HPA do analytics escalando** e **dados no DynamoDB**.
> ✅ Schema confirmado a partir de `services/analytics-service/app.py`: campos `user_id` (string), `flag_name` (string), `result` (**boolean**), `timestamp` (string). Todos obrigatórios — se faltar um, a mensagem vira poison pill e volta pra fila.

**Mostrar:** deixe o Terminal A ainda com o `watch kubectl get hpa,pods`.

**Terminal B — envio manual em massa no SQS:**
```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name togglemaster-analytics-events \
  --region us-east-1 --query QueueUrl --output text)

# Conta inicial no DynamoDB (antes)
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --select COUNT

# Envio SUSTENTADO por ~2 min: mantém backlog na fila pra CPU ficar alta
# tempo suficiente pro HPA do analytics escalar 1→2→3.
END=$((SECONDS+120)); i=0
while [ $SECONDS -lt $END ]; do
  for n in $(seq 1 30); do
    i=$((i+1))
    aws sqs send-message --queue-url "$QUEUE_URL" --region us-east-1 \
      --message-body "{\"user_id\":\"user-$i\",\"flag_name\":\"dark-mode\",\"result\":true,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
      >/dev/null &
  done
  wait
done
echo "Enviadas $i mensagens"
```

**Falar:**
> "Agora demonstro a escalabilidade do analytics-service. Vou injetar manualmente centenas de mensagens diretamente na fila SQS. O analytics-service consome essas mensagens, e à medida que processa, a CPU dele sobe — disparando o HPA, que escala os Pods.
>
> No terminal da esquerda, vejam o HPA do analytics-service reagindo e criando réplicas. Esse é exatamente o workaround de escalabilidade orientada a fila usando HPA por CPU."

**Depois que escalou — confirme os dados gravados:**
```bash
# Conta final no DynamoDB (depois)
aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --select COUNT
```
E mostre no **console do DynamoDB** os itens aparecendo na tabela.

**Falar:**
> "E aqui está o resultado: a contagem de itens no DynamoDB subiu — os eventos que mandei pela fila foram processados pelo analytics-service e persistidos. Pipeline completo funcionando: SQS → analytics-service → DynamoDB."

---

## BLOCO 8 — Explicações exigidas pelo PDF (≈3 min)

> Estes pontos são **obrigatórios** nos entregáveis. Fale com calma, de preferência com um slide de apoio.

### 8.1 — Arquitetura e desafios encontrados
**Falar:**
> "Cada microsserviço tem seu próprio Deployment e Service dentro de um namespace dedicado. As credenciais e URLs internas são injetadas via Secrets e ConfigMaps — nada hardcoded nas imagens.
>
> O principal desafio foram erros de build nas imagens: dependências desatualizadas, imports quebrados, incompatibilidade de versão do Werkzeug no Python. Foram ajustes pontuais, mas que bloqueiam o deploy se não forem resolvidos antes do push pro ECR."

### 8.2 — Escalabilidade do analytics: HPA por CPU vs KEDA (justificar a escolha)
**Falar:**
> "Para escalar o analytics-service, usei o HPA padrão do Kubernetes, medindo CPU. A lógica é direta: quando a fila enche, o serviço processa mais, a CPU sobe, e o HPA cria novas réplicas.
>
> Existe uma solução mais elegante pra esse caso — o KEDA, que escalaria olhando diretamente o tamanho da fila SQS, sem depender de CPU. Mas o KEDA precisa de permissões IAM específicas que não estão disponíveis em todas as contas. O HPA por CPU resolve o problema e funciona em qualquer cluster, então foi a escolha mais segura aqui."

### 8.3 — Diferença entre os 3 data stores (RDS, ElastiCache, DynamoDB)
**Falar:**
> "Os três data stores têm propósitos distintos:
> - **RDS (PostgreSQL)** — banco **relacional/transacional**, usado por auth, flag e targeting, onde há dados estruturados, relações e necessidade de consistência (ACID).
> - **ElastiCache (Redis)** — **cache in-memory** no hot path do evaluation-service, pra respostas em latência mínima, evitando ir ao banco a cada avaliação.
> - **DynamoDB** — banco **NoSQL** de alta escala pro analytics-service, ideal pra ingestão de grande volume de eventos com escrita rápida e schema flexível, sem precisar de relações."

---

## BLOCO 9 — Encerramento (≈30 s)

**Falar:**
> "Recapitulando: mostrei o ecossistema rodando localmente com docker compose, depois os 5 microsserviços rodando na AWS sobre Kubernetes, organizados por namespace e expostos via Nginx Ingress com roteamento por path. Demonstrei o autoscaling do evaluation-service por carga HTTP e do analytics-service por processamento de fila SQS, com os dados persistidos no DynamoDB. Obrigado!"

> **Não esquecer (fora do vídeo):** rodar `./teardown.sh` depois de gravar pra parar a cobrança.

---

## Checklist de bullets do PDF cobertos por este roteiro

- [x] `docker compose up` com os 9 containers (5 apps + 4 DBs) — Bloco 2
- [x] Cluster Kubernetes na nuvem (EKS) — Bloco 3 e 4
- [x] 5 microsserviços rodando como Pods (`kubectl get pods`) — Bloco 4
- [x] Nginx Ingress funcionando (chamada curl/Postman ao LB) — Bloco 5
- [x] Gerar carga no evaluation-service + HPA aumentando réplicas — Bloco 6
- [x] Enviar manualmente mensagens ao SQS — Bloco 7
- [x] HPA do analytics-service detectando carga e escalando — Bloco 7
- [x] Dados aparecendo no DynamoDB — Bloco 7
- [x] Explicar arquitetura e desafios (ex: LabRole) — Bloco 8.1
- [x] Explicar escalabilidade do analytics (HPA vs KEDA) e justificar — Bloco 8.2
- [x] Explicar diferença entre RDS, ElastiCache e DynamoDB — Bloco 8.3

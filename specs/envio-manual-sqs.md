# Pendência: envio manual de eventos no SQS (vídeo Fase 2)

> Tarefa a fazer **junto com o Claude** depois de clonar os serviços (`./setup.sh`).

## Contexto

O PDF da Fase 2 lista como bullet **explícito e separado** dos entregáveis:
> "Envie manualmente várias mensagens para a fila SQS."

O teste com `hey` (do README) já aciona o pipeline real
(`hey → evaluation-service → SQS → analytics-service → DynamoDB`),
mas **não substitui** o envio manual por dois motivos:

1. **Rubrica literal** — o avaliador marca bullet a bullet; o vídeo precisa mostrar um envio manual ao SQS.
2. **Risco técnico** — o HPA do analytics-service escala por **CPU a 70%** (não é KEDA por fila).
   Não é garantido que o `hey` gere volume de SQS suficiente pra estourar a CPU do consumidor
   e fazer o analytics escalar de 1→3 na câmera. A injeção manual em massa **garante** o spike.

## Plano (fazer no vídeo)

- [ ] `hey` → mostra evaluation HPA escalando + pipeline real alimentando o analytics
- [ ] Envio manual em massa no SQS → garante analytics HPA escalando + cumpre o bullet do PDF
- [ ] Confirmar dados aparecendo no DynamoDB (`aws dynamodb scan ... --select COUNT`)

## A FAZER COM O CLAUDE (depende dos serviços clonados)

**Ler o código do `analytics-service`** (consumidor da fila) e descobrir o
**schema exato do `--message-body`** — os mesmos campos que o `evaluation-service` publica no SQS.

Sem o formato certo, o consumidor pode dar erro por mensagem, não subir CPU "útil"
e não gravar no DynamoDB.

## ✅ RESOLVIDO — schema confirmado

Fonte: `services/analytics-service/app.py:50-62` (`process_message`).
O corpo é JSON com **4 campos obrigatórios**:

| Campo | Tipo | Observação |
|---|---|---|
| `user_id` | string | |
| `flag_name` | string | |
| `result` | **boolean** | JSON `true`/`false`, não string (vai pra DynamoDB como `BOOL`) |
| `timestamp` | string | qualquer string (ex: ISO 8601) |

> `event_id` é gerado pelo próprio serviço (uuid) — não enviar.
> ⚠️ Se faltar qualquer campo → `KeyError` → a mensagem **não é deletada** e volta pra fila (poison loop). Por isso os 4 são obrigatórios.

## Dados do ambiente

- Fila SQS: `togglemaster-analytics-events` (região `us-east-1`)
- HPA analytics: CPU 70% de 100m request (= 70m) → escala fácil se houver backlog. min 1, máx 3
- Service consumidor: `analytics-service` (Python, porta 8005, worker single-thread) → grava em DynamoDB `ToggleMasterAnalytics`

## Comando final (pronto pra usar)

Worker é single-thread/I-O bound → o segredo é **manter backlog**. Envio sustentado por ~2 min:

```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name togglemaster-analytics-events \
  --region us-east-1 --query QueueUrl --output text)

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

Validação: `aws dynamodb scan --table-name ToggleMasterAnalytics --region us-east-1 --select COUNT` (antes e depois).

# Spec 02: VPC Gateway Endpoints (DynamoDB + S3)

> Melhoria de arquitetura — fazer **junto com o Claude**. Não bloqueia a gravação;
> é otimização + ponto de explicação no vídeo.

## Objetivo

Adicionar **Gateway Endpoints** (grátis) para **DynamoDB** e **S3**, fazendo o tráfego
dos pods sair pela rede interna da AWS em vez de passar pelo NAT Gateway.

## Por quê

Hoje os nós estão em subnets privadas com rota default `0.0.0.0/0 → NAT Gateway`
(`vpc.tf:73-80`). Todo tráfego pra serviços AWS sai pra internet via NAT.

Gateway Endpoint troca isso por uma rota interna pra `prefix-list` do serviço:

```
SEM endpoint:  pod (privada) → NAT → IGW → internet → DynamoDB/S3
COM endpoint:  pod (privada) → Gateway Endpoint → DynamoDB/S3 (backbone AWS)
```

| Serviço | Quem usa no projeto | Ganho |
|---|---|---|
| **DynamoDB** | `analytics-service` grava eventos | tráfego não passa no NAT, fica interno |
| **S3** | ECR guarda os **layers** das imagens Docker no S3; nós puxam de lá | pull de imagem fica interno, alivia o NAT |

### Os 3 ganhos
- 💰 **Custo**: sai do data-processing do NAT (~US$ 0,045/GB) — e o endpoint é grátis
- 🔒 **Segurança**: tráfego no backbone AWS, nunca na internet pública
- ⚡ **Latência/confiabilidade**: caminho interno

> Só DynamoDB e S3 têm Gateway Endpoint (grátis). SQS/ECR-API/STS só têm Interface
> Endpoint (~US$ 0,01/h cada) → não compensam pra demo curta.

## Implementação proposta (terraform/vpc.tf)

Adicionar ~10 linhas, associando às route tables das subnets privadas:

```hcl
# ── VPC Gateway Endpoints (grátis) ──────────────────────────────────────────

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-dynamodb-endpoint" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-s3-endpoint" }
}
```

## Checklist

- [x] Adicionar os 2 `aws_vpc_endpoint` em `vpc.tf` (usando `var.aws_region`, já existente no projeto)
- [x] `terraform validate` + `terraform fmt` → configuração válida
- [ ] `terraform plan` → confirmar que só **cria** 2 recursos (não altera/destrói nada) — **precisa das credenciais AWS**
- [ ] `terraform apply`
- [ ] Validar: `analytics-service` continua gravando no DynamoDB; pods continuam puxando imagem do ECR
- [ ] (opcional) Mencionar no vídeo como otimização de tráfego de saída

## Notas

- Não quebra nada do que já funciona — Gateway Endpoint só **adiciona** rota; o NAT
  continua existindo pra todo o resto (SQS, ECR-API, STS, internet em geral).
- Referências no código atual: route table privada em `vpc.tf:73`, NAT em `vpc.tf:57`.

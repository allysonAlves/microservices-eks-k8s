#!/bin/bash
# Removes all AWS resources created by terraform apply.
# Run from the project root.
set -e

REGION="us-east-1"
CLUSTER_NAME="togglemaster-cluster"
NAMESPACE="togglemaster"

echo "==> Atualizando kubeconfig..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

echo "==> Removendo Load Balancer criado pelo Kubernetes..."
LB_ARNS=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || true)

if [ -n "$LB_ARNS" ]; then
  for ARN in $LB_ARNS; do
    echo "    Deletando: $ARN"
    aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$ARN"
  done
  echo "    Aguardando LBs serem removidos..."
  sleep 30
else
  echo "    Nenhum Load Balancer encontrado."
fi

echo "==> Removendo recursos Kubernetes do state do Terraform..."
cd terraform
terraform state list 2>/dev/null | grep -E "^(kubernetes_|helm_)" | while read -r resource; do
  terraform state rm "$resource" 2>/dev/null || true
done

echo "==> Destruindo infraestrutura AWS..."
terraform destroy -auto-approve

echo ""
echo "==> Verificando se tudo foi removido..."
echo "EKS:          $(aws eks list-clusters --region $REGION --output text 2>/dev/null || echo '-')"
echo "RDS:          $(aws rds describe-db-instances --region $REGION --query 'DBInstances[*].DBInstanceIdentifier' --output text 2>/dev/null || echo '-')"
echo "ElastiCache:  $(aws elasticache describe-cache-clusters --region $REGION --query 'CacheClusters[*].CacheClusterId' --output text 2>/dev/null || echo '-')"
echo "VPC custom:   $(aws ec2 describe-vpcs --region $REGION --filters 'Name=isDefault,Values=false' --query 'Vpcs[*].VpcId' --output text 2>/dev/null || echo '-')"
echo "Load Balancer:$(aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[*].LoadBalancerName' --output text 2>/dev/null || echo '-')"
echo ""
echo "Teardown concluido!"

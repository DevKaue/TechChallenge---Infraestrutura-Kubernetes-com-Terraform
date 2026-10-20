# Addons gerenciados. Três deles corrigem falhas silenciosas conhecidas:
#   - vpc-cni com enableNetworkPolicy: sem isso as NetworkPolicies são ACEITAS
#     e não aplicadas — o mesmo comportamento do Docker Desktop que engana quem
#     testa isolamento localmente.
#   - metrics-server: não vem por padrão no EKS. Sem ele o HPA fica <unknown> e
#     o requisito de escalabilidade simplesmente não funciona.
#   - amazon-cloudwatch-observability: Container Insights (métricas + logs de
#     pod) sem nenhum YAML nosso.

# Versão de cada addon amarrada à versão do Kubernetes. Sem `addon_version`, a
# EKS instala a versão padrão do dia da criação e NÃO a atualiza quando o
# control plane sobe de versão: o vpc-cni/kube-proxy antigos ficam rodando num
# cluster novo até alguém perceber. most_recent = false = a versão padrão que a
# AWS testou para aquele Kubernetes, que muda menos entre runs que a mais nova.
data "aws_eks_addon_version" "this" {
  for_each = toset([
    "vpc-cni",
    "coredns",
    "kube-proxy",
    "eks-pod-identity-agent",
    "metrics-server",
    "amazon-cloudwatch-observability",
  ])

  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.this["vpc-cni"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = local.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.this["coredns"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # NÃO remover este depends_on achando que é redundante: `cluster_name` é um
  # output que depende apenas do aws_eks_cluster, NÃO do managed node group.
  # Addons que sobem pod (CoreDNS, metrics-server, CloudWatch agent) precisam de
  # nó pronto — e é o depends_on no módulo inteiro que garante isso.
  depends_on = [module.eks]

  tags = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.this["kube-proxy"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = data.aws_eks_addon_version.this["eks-pod-identity-agent"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.this["metrics-server"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks]

  tags = local.tags
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = data.aws_eks_addon_version.this["amazon-cloudwatch-observability"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Application Signals DESLIGADO — sem isto o deploy não sobe.
  #
  # O addon vem com `applicationSignals.enabled = true` e
  # `autoMonitor.monitorAllServices = true`, ou seja, um webhook mutante que
  # injeta containers de auto-instrumentação do OpenTelemetry em TODO pod do
  # cluster. Esses containers injetados não declaram `allowPrivilegeEscalation:
  # false` nem `capabilities.drop: [ALL]`, então o Pod Security `restricted` do
  # namespace REJEITA a criação do pod:
  #
  #   violates PodSecurity "restricted:v1.32": container
  #   "opentelemetry-auto-instrumentation-java" must set
  #   securityContext.allowPrivilegeEscalation=false
  #
  # Resultado: Deployment com 0 pods e o erro só visível em `get events` — nada
  # aparece em `kustomize build`, `kubeconform` ou `terraform validate`.
  #
  # Container Insights (métricas + logs de pod), que é o que queremos, é
  # controlado por `containerInsights` e continua ligado.
  configuration_values = jsonencode({
    applicationSignals = {
      enabled = false
    }
  })

  depends_on = [module.eks]

  tags = local.tags
}

module "eks" {
  # [PATCH FIAP lab] Módulo vendored: cópia local do registry module
  # terraform-aws-modules/eks/aws v20.37.2 com o input cluster_creator_arn.
  # O módulo do registry não tem como informar o ARN do criador do cluster —
  # ele resolve automaticamente via data aws_iam_session_context, que chama
  # iam:GetRole, negado explicitamente pela política da conta do AWS Academy
  # (Pvoclabs). No vendoring, o data source só é lido quando
  # cluster_creator_arn é nulo.
  # Histórico (antes do vendoring):
  #   source  = "terraform-aws-modules/eks/aws"
  #   version = "20.37.2"
  source = "./modules/eks"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  # [PATCH FIAP lab] ARN do criador do cluster. No lab é a role voclabs
  # (arn:aws:iam::<conta>:role/voclabs), que passa a admin do cluster via
  # access entry — mesmo padrão do exemplo da aula (access-entry.tf).
  cluster_creator_arn = var.cluster_creator_arn

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint público: sem ele seria preciso bastion ou VPN para rodar kubectl.
  # O acesso continua autenticado por IAM + autorizado por RBAC.
  cluster_endpoint_public_access = true

  # AWS Academy: role do cluster = LabRole, e sem provider OIDC (o IRSA fica
  # desligado; os controllers usam a credencial do nó).
  create_iam_role = !local.lab_mode
  iam_role_arn    = local.lab_mode ? var.lab_role_arn : null
  enable_irsa     = !local.lab_mode

  # Access entries (API), não o ConfigMap aws-auth — que está em depreciação.
  # Quem roda o apply vira admin do cluster automaticamente.
  enable_cluster_creator_admin_permissions = true

  access_entries = merge(
    # Admins do cluster: policy gerenciada da AWS.
    {
      for arn in var.cluster_admin_arns : "admin-${basename(arn)}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    # Leitura para diagnóstico: SEM policy da AWS — a autorização vem do
    # RoleBinding do namespace (k8s/base/rbac.yaml), que faz o bind neste grupo.
    # É o IAM autenticando e o RBAC autorizando, cada um no seu papel.
    {
      for arn in var.cluster_readonly_arns : "readonly-${basename(arn)}" => {
        principal_arn     = arn
        type              = "STANDARD"
        kubernetes_groups = ["techchallenge:readonly"]
      }
    }
  )

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_group_size.min
      max_size       = var.node_group_size.max
      desired_size   = var.node_group_size.desired

      # Nós em subnet privada, saindo pelo NAT. O ALB fica nas públicas.
      subnet_ids = module.vpc.private_subnets

      # AWS Academy: role dos nós = LabRole. Nesse modo o anexo de policy abaixo
      # é ignorado pelo módulo, e as permissões do CloudWatch são as da LabRole.
      create_iam_role = !local.lab_mode
      iam_role_arn    = local.lab_mode ? var.lab_role_arn : null

      iam_role_additional_policies = {
        # O agente do Container Insights publica métricas e logs com a role do
        # nó. Sem esta policy o addon instala e não envia nada — falha silenciosa.
        cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }
  }

  # SEM esta regra o HPA nunca sai de `<unknown>` e a escalabilidade não existe.
  #
  # O metrics-server do addon EKS escuta na porta 10251, mas as regras padrão do
  # módulo liberam Cluster API → nós apenas em 443, 4443, 6443, 8443, 9443 e
  # 10250. O kube-apiserver não alcança o pod, o APIService
  # v1beta1.metrics.k8s.io fica `Available=False` com "context deadline
  # exceeded", e `kubectl top` responde "Metrics API not available".
  #
  # O sintoma engana: os pods do metrics-server ficam `Running` e saudáveis —
  # o problema é firewall, não o addon.
  node_security_group_additional_rules = {
    metrics_server = {
      description                   = "Cluster API to metrics-server (10251)"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Logs do control plane no CloudWatch — é o único lugar onde aparece por que
  # uma chamada à API foi negada. Os cinco tipos: `scheduler` e
  # `controllerManager` explicam pod que não agenda e réplica que não sobe,
  # que é exatamente o que se depura num cluster com HPA.
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  tags = local.tags
}

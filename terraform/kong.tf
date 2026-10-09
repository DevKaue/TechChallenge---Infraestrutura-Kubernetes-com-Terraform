# Kong como API Gateway: Kong Ingress Controller + gateway em modo DB-less.
#
# A configuração de rotas e plugins NÃO mora aqui: ela vem dos Ingress,
# KongPlugin e KongConsumer do overlay aws do repositório da aplicação. O
# controller observa esses objetos e empurra a config para os pods do gateway.
# Este arquivo só instala o Kong e dá a ele a permissão de invocar a Lambda.
#
# Tráfego: NLB (criado pelo AWS LB Controller a partir do Service do proxy)
# → pods do gateway → pods da aplicação.

locals {
  kong_namespace       = "kong"
  kong_service_account = "kong-gateway"

  # Labels que o chart kong/ingress põe nos pods (o alias do subchart vira o
  # app.kubernetes.io/name; o release vira o instance).
  kong_gateway_selector = {
    "app.kubernetes.io/name"     = "gateway"
    "app.kubernetes.io/instance" = "kong"
  }
  kong_controller_selector = {
    "app.kubernetes.io/name"     = "controller"
    "app.kubernetes.io/instance" = "kong"
  }

  # Convenção compartilhada com o repositório da Lambda e com o KongPlugin
  # aws-lambda do repositório da aplicação.
  auth_lambda_name = "${var.project}-auth-${var.environment}"

  # Sem IRSA no AWS Academy: o Kong usa a credencial do nó (LabRole) via IMDSv2.
  kong_use_irsa = !local.lab_mode
}

data "aws_iam_policy_document" "kong_invoke_auth_lambda" {
  count = local.kong_use_irsa ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = ["arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:${local.auth_lambda_name}"]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "kong_invoke_auth_lambda" {
  count = local.kong_use_irsa ? 1 : 0

  name   = "${local.name}-kong-invoke-auth-lambda"
  policy = data.aws_iam_policy_document.kong_invoke_auth_lambda[0].json
  tags   = local.tags
}

# IRSA: o plugin aws-lambda do Kong lê AWS_ROLE_ARN e AWS_WEB_IDENTITY_TOKEN_FILE,
# injetados pelo webhook do EKS por causa da anotação na ServiceAccount.
module "kong_irsa" {
  count = local.kong_use_irsa ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name = "${local.name}-kong-gateway"

  role_policy_arns = {
    invoke_auth_lambda = aws_iam_policy.kong_invoke_auth_lambda[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.kong_namespace}:${local.kong_service_account}"]
    }
  }

  tags = local.tags
}

resource "helm_release" "kong" {
  name             = "kong"
  repository       = "https://charts.konghq.com"
  chart            = "ingress"
  version          = "0.24.0"
  namespace        = local.kong_namespace
  create_namespace = true

  # O helm espera o Service LoadBalancer receber endereço; o NLB pode passar
  # dos 300s padrão para ficar pronto.
  timeout = 600

  values = [yamlencode({
    controller = {
      ingressController = {
        ingressClass = "kong"
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
      }
    }

    gateway = {
      # A região da invocação vem do KongPlugin aws-lambda (aws_region) e do
      # AWS_REGION que o webhook do IRSA injeta no pod.
      env = {
        # Kong Manager OSS fica só leitura em DB-less. Acesso apenas por
        # port-forward (8002 e 8001): sem login no OSS, nunca expor.
        admin_gui_url     = "http://localhost:8002"
        admin_gui_api_url = "http://localhost:8001"
      }

      deployment = {
        serviceAccount = {
          create = true
          name   = local.kong_service_account
          annotations = local.kong_use_irsa ? {
            "eks.amazonaws.com/role-arn" = module.kong_irsa[0].iam_role_arn
          } : {}
        }
      }

      replicaCount = 2

      autoscaling = {
        enabled     = true
        minReplicas = 2
        maxReplicas = 5
        metrics = [{
          type = "Resource"
          resource = {
            name   = "cpu"
            target = { type = "Utilization", averageUtilization = 70 }
          }
        }]
      }

      podDisruptionBudget = {
        enabled        = true
        maxUnavailable = 1
      }

      resources = {
        requests = { cpu = "250m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }

      # Réplicas em nós e zonas diferentes: com 2 pods no mesmo nó, a queda do
      # nó derruba o gateway inteiro. ScheduleAnyway, como no overlay da API.
      topologySpreadConstraints = [
        for key in ["topology.kubernetes.io/zone", "kubernetes.io/hostname"] : {
          maxSkew           = 1
          topologyKey       = key
          whenUnsatisfiable = "ScheduleAnyway"
          labelSelector = {
            matchLabels = local.kong_gateway_selector
          }
        }
      ]

      proxy = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          # preserve_client_ip: com target-type ip o NLB não preserva o IP do
          # cliente por padrão, e o rate-limiting por IP veria todos como um só.
          # deregistration_delay: precisa ficar abaixo do terminationGracePeriod
          # (30s) dos pods, senão o NLB ainda envia tráfego para pod encerrado.
          "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes" = "preserve_client_ip.enabled=true,deregistration_delay.timeout_seconds=20"
        }
        # Sem certificado ACM ainda: só HTTP, como o ALB que este NLB substitui.
        tls = { enabled = false }
      }

      admin = {
        http = { enabled = true }
      }

      manager = {
        type = "ClusterIP"
      }

      # A Admin API (8444 e 8001) não tem autenticação: o mTLS com o controller
      # vem desligado no chart. Em DB-less, um POST /config de qualquer pod do
      # cluster trocaria a config inteira, inclusive removendo o plugin jwt.
      # Só o proxy é aberto; a Admin API, só para o controller; o status, só da
      # VPC (kubelet e coletor de métricas). O port-forward do Kong Manager
      # passa pelo kubelet e não é afetado.
      extraObjects = [{
        apiVersion = "networking.k8s.io/v1"
        kind       = "NetworkPolicy"
        metadata   = { name = "kong-gateway-ingress" }
        spec = {
          podSelector = { matchLabels = local.kong_gateway_selector }
          policyTypes = ["Ingress"]
          ingress = [
            { ports = [{ port = 8000, protocol = "TCP" }] },
            {
              from  = [{ podSelector = { matchLabels = local.kong_controller_selector } }]
              ports = [{ port = 8444, protocol = "TCP" }]
            },
            {
              from  = [{ ipBlock = { cidr = var.vpc_cidr } }]
              ports = [{ port = 8100, protocol = "TCP" }]
            },
          ]
        }
      }]
    }
  })]

  # O NLB é provisionado pelo AWS LB Controller; sem ele o Service ficaria
  # <pending> e o Kong nunca receberia tráfego.
  depends_on = [helm_release.alb_controller]
}

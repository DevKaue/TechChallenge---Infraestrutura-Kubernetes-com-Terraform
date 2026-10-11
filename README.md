# Tech Challenge - Infraestrutura Kubernetes (Terraform)

**Repositório 2 do projeto.** Infrastructure as Code (Terraform) da camada
Kubernetes na AWS: **VPC, ECR, EKS, addons, ALB Controller, Kong (API Gateway) e
IAM/OIDC**. Todo o ciclo de vida (criar, atualizar e destruir) é versionado aqui
e executado pelo **HCP Terraform (Terraform Cloud)**, com um workspace por
ambiente.

## Escopo

Este repositório cuida **apenas** da infraestrutura de Kubernetes. Ele **não**
contém o código da aplicação, os manifestos Kustomize, nem o banco de dados:

| Repositório | Responsabilidade |
|---|---|
| 1. Lambda | Function serverless |
| **2. Infraestrutura Kubernetes (este)** | VPC, ECR, EKS, addons, ALB Controller, Kong, IAM/OIDC |
| 3. Infraestrutura do Banco Gerenciado | RDS PostgreSQL (Terraform) |
| 4. Aplicação principal em Kubernetes | Código da API, Dockerfile, manifestos Kustomize e deploy no cluster |

### Contrato com os outros repositórios

- **Expõe para os repositórios 3 e 4**: `vpc_id`, `private_subnet_ids`,
  `node_security_group_id`, `vpc_cidr`, `ecr_url`, `ecr_repository_name`,
  `cluster_name`, `github_app_deploy_role_arn`, `github_lambda_deploy_role_arn`
  e `jwt_secret_ssm_path`.
- O **namespace** e o **Secret** da aplicação são criados pelo overlay Kustomize
  do repositório 4 (dono único), não por este repositório. O segredo JWT
  compartilhado é publicado aqui no SSM (`jwt_secret_ssm_path`), consumido pela
  Lambda, pelo app e pelo Kong.
- A **Lambda** (repo 1) e a **aplicação** (repo 4) continuam deployando por
  **GitHub Actions** com OIDC. Este repositório roda no HCP Terraform.

## Estrutura

```
terraform/            toda a infraestrutura como código
├── versions.tf       required_version, providers e bloco cloud (HCP Terraform)
├── providers.tf      aws / helm
├── modules/eks/      terraform-aws-modules/eks v20.37.2 vendored
│                     (fork local: input `cluster_creator_arn` no lugar
│                     do `aws_iam_session_context`, que exige iam:GetRole)
├── vpc.tf            VPC 3 AZ, NAT único, tags de subnet para o ALB
├── ecr.tf            repositório com tag imutável e lifecycle
├── eks.tf            cluster 1.32, managed node group, access entries
├── addons.tf         vpc-cni (network policy), coredns, kube-proxy,
│                     metrics-server, pod-identity, Container Insights
├── alb-controller.tf IRSA + Helm do AWS Load Balancer Controller
├── kong.tf           Kong Ingress Controller DB-less + NLB + permissão da Lambda
├── secrets.tf        segredo JWT compartilhado no SSM
├── github-oidc.tf    OIDC provider + roles de deploy (app e Lambda)
└── outputs.tf        valores consumidos pelos repositórios 3 e 4
.github/workflows/    ci.yml (fmt + validate em PR)
```

## HCP Terraform (CI/CD)

O `plan`/`apply` roda no **HCP Terraform**, não mais em GitHub Actions. Há um
**workspace por ambiente**, casados pela tag `techchallenge-infra` do bloco
`cloud` (`terraform/versions.tf`):

| Workspace | `environment` | Observação |
|---|---|---|
| `techchallenge-infra-prod` | `prod` | produção |
| `techchallenge-infra-staging` | `staging` | precisa de apply próprio antes do deploy de homologação do app |

Passos:

1. Crie os workspaces no HCP Terraform com a tag `techchallenge-infra`.
2. O runner padrão do TFC **não tem o AWS CLI**, e o provider Helm autentica com
   `aws eks get-token` (`terraform/providers.tf`). Configure **Execution Mode →
   Agent** e registre um **agent self-hosted** com o AWS CLI instalado.
3. Variáveis do workspace:
   - **Env (sensitive)**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
     `AWS_SESSION_TOKEN` — credenciais temporárias do Academy, renovadas a cada
     sessão (~4h).
   - **Terraform**: `environment` (`prod`/`staging`),
     `lab_role_arn = arn:aws:iam::<conta>:role/LabRole`,
     `cluster_creator_arn = arn:aws:iam::<conta>:role/voclabs` e
     `node_instance_types = ["t3.medium"]`.
4. Conecte o VCS (GitHub) do workspace para plan/apply automáticos, ou rode pelo
   CLI definindo `TF_WORKSPACE`.

> O campo `organization` do bloco `cloud` está como `REPLACE_ORG`: troque pelo
> slug da sua organização no `app.terraform.io`.

> **Módulo EKS vendored** (`terraform/modules/eks`): cópia local do
> `terraform-aws-modules/eks/aws` v20.37.2 com um input a mais,
> `cluster_creator_arn`. O módulo original resolve o criador do cluster
> com o data source `aws_iam_session_context`, que chama `iam:GetRole` —
> negado explicitamente pela política da conta do AWS Academy (`Pvoclabs`).
> Com o ARN da role `voclabs` passado por variável, o access entry de
> admin do criador fica explícito, igual ao padrão da aula, sem a
> chamada IAM. Os pontos alterados no módulo estão marcados com
> `[PATCH FIAP lab]` e o código original preservado em comentários.

## Migração do state S3 existente

O state sai do bucket S3 `techchallenge-fiap-v1` e passa para o HCP Terraform.
Preservar o state mantém o `random_password.jwt_secret` já gravado — recriá-lo
rotacionaria o segredo e quebraria os tokens da Lambda, do app e do Kong.

Por workspace, uma vez:

```powershell
terraform login
$env:TF_WORKSPACE = "techchallenge-infra-prod"
Set-Location terraform
terraform init -migrate-state   # responda que sim para copiar o state ao TFC
```

Depois, remova do state os recursos que saíram do código, para o Terraform **não
destruir** o namespace/Secret da aplicação (que agora pertencem ao Kustomize):

```powershell
terraform state rm 'kubernetes_namespace.app'      # se existir no state
terraform state rm 'kubernetes_secret.app'         # se existir no state
terraform state rm 'random_password.password_salt'
terraform state rm 'random_password.webhook_secret'
```

Confirme com `terraform plan` que nenhuma destruição indevida aparece antes de
aplicar.

## Regras de proteção (configurar no GitHub)

- Branch `main` e `develop` protegidas — **sem push direto**.
- Merge somente via **Pull Request** (com o `ci.yml` verde obrigatório).
- O deploy da infraestrutura é disparado pelo HCP Terraform ao detectar o merge.

## Uso local

Pré-requisitos: Terraform `~> 1.10`, AWS CLI autenticado (credenciais do lab) e
`kubectl`. Para operar contra um workspace do TFC, exporte `TF_WORKSPACE` com o
nome do workspace (o valor precisa estar contido nas tags `techchallenge-infra`)
e rode `terraform init`, `terraform plan` e `terraform apply`. Para destruir a
infraestrutura, `terraform destroy`.

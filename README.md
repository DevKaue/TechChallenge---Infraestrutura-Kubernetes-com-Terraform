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

- **Rede descoberta por tag**: os repositórios de banco e da Lambda acham a VPC
  e as subnets privadas pelas tags `Project`, `Environment` e `ManagedBy`
  (`default_tags` do provider) e `kubernetes.io/role/internal-elb`. Mudar essas
  tags aqui quebra os dois.
- **Publica no SSM** (path previsível, ninguém lê o state deste repositório):
  - `/techchallenge/<env>/auth/jwt-secret`: segredo JWT compartilhado entre
    Lambda, aplicação e Kong.
  - `/techchallenge/<env>/eks/node-sg-id`: SG dos nós do EKS. O repositório de
    banco libera a 5432 a partir dele.
- **Outputs** para configurar os repositórios 1 e 4 (GitHub Environments):
  `cluster_name`, `ecr_repository_name`, `ecr_url`, `vpc_cidr` e
  `auth_lambda_name`.
- O **namespace** e o **Secret** da aplicação são criados pelo overlay Kustomize
  do repositório 4 (dono único), não por este repositório.
- A **Lambda** (repo 1) e a **aplicação** (repo 4) deployam por **GitHub
  Actions**. Este repositório e o de banco (repo 3) rodam no **HCP Terraform**.

### Ordem de deploy

```
1. Infra Kubernetes (este, TFC)  → VPC, EKS, Kong, JWT e SG dos nós no SSM
2. Infra Banco (TFC)             → descobre a VPC, libera o SG dos nós, publica /db/*
3. Lambda (GitHub Actions)       → descobre a VPC, anexa o SG de cliente do banco
4. Aplicação (GitHub Actions)    → build, push no ECR e apply no cluster
```

Uma VPC e um cluster **por ambiente** (`techchallenge-prod`,
`techchallenge-staging`). Em todos os repositórios, `develop` faz deploy de
staging e `main` de produção.

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
├── eks.tf            cluster (versão por variável), managed node group AL2023,
│                     access entries
├── addons.tf         vpc-cni (network policy), coredns, kube-proxy,
│                     metrics-server, pod-identity, Container Insights
│                     (versão de cada addon amarrada à do Kubernetes)
├── alb-controller.tf IRSA + Helm do AWS Load Balancer Controller
├── kong.tf           Kong Ingress Controller DB-less + NLB + permissão da Lambda
├── secrets.tf        segredo JWT compartilhado no SSM
├── discovery.tf      SG dos nós publicado no SSM para o repositório de banco
├── github-oidc.tf    OIDC provider + roles de deploy (app e Lambda), fora do lab
└── outputs.tf        valores para configurar os repositórios 1 e 4
.github/workflows/    ci.yml (fmt + validate em PR)
```

## HCP Terraform (CI/CD)

O `plan`/`apply` roda no **HCP Terraform**, não mais em GitHub Actions. Há um
**workspace por ambiente**, casados pela tag `techchallenge-infra` do bloco
`cloud` (`terraform/versions.tf`):

| Workspace | Branch (VCS) | `environment` | Observação |
|---|---|---|---|
| `techchallenge-infra-prod` | `main` | `prod` | produção |
| `techchallenge-infra-staging` | `develop` | `staging` | sobe só quando for usar: dobra o custo (EKS, NAT, NLB) |

Organização: `tech-challenge-infra` (bloco `cloud` em `terraform/versions.tf`).

Passos, por workspace:

1. Crie o workspace com a tag `techchallenge-infra` e fixe a **Terraform
   version** em `1.16.5` (a mesma do `ci.yml`).
2. **Settings → General → Terraform Working Directory**: `terraform`. O código
   não fica na raiz do repositório.
3. O runner padrão do TFC **não tem o AWS CLI**, e o provider Helm autentica com
   `aws eks get-token` (`terraform/providers.tf`). Configure **Execution Mode →
   Agent** e registre um **agent self-hosted** com o AWS CLI instalado (a imagem
   oficial `hashicorp/tfc-agent` não traz o AWS CLI: use uma imagem derivada).
4. Credenciais: um **Variable Set** compartilhado com os workspaces do banco,
   com as variáveis **Env (sensitive)** `AWS_ACCESS_KEY_ID`,
   `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`. São as credenciais temporárias
   do Academy (*AWS Details → AWS CLI*), renovadas a cada sessão (~4h): atualize
   no Variable Set e todos os workspaces passam a usar. Comece o apply com a
   sessão recém-aberta: criar o EKS leva ~20 min.
5. Variáveis **Terraform** do workspace:
   - `environment`: `prod` ou `staging` (obrigatória, sem default).
   - `kubernetes_version`: obrigatória, sem default. Use uma versão em suporte
     padrão (`aws eks describe-cluster-versions --region us-east-1`); hoje,
     `1.35`.
   - `vpc_cidr`: opcional. Sugestão: `10.0.0.0/16` em prod e `10.1.0.0/16` em
     staging.
   - `lab_mode` (default `true`) e `node_instance_types` (default
     `["t3.medium"]`) já servem para o Academy.

   O ID da conta **não precisa** de variável: `main.tf` monta
   `arn:aws:iam::<conta>:role/LabRole` e `.../role/voclabs` com a conta das
   próprias credenciais do run (`data.aws_caller_identity`). Só defina
   `aws_account_id` (ou as ARNs completas `lab_role_arn`/`cluster_creator_arn`)
   se a LabRole tiver nome diferente.
6. Conecte o VCS (GitHub) na branch da tabela. PRs recebem *speculative plan*
   automaticamente. Deixe o **apply manual** em prod: o plan é revisado antes de
   confirmar.

Para destruir pelo TFC é preciso a variável Env `CONFIRM_DESTROY=1` no
workspace. Antes, remova o deploy da aplicação (`kubectl delete -k` no
repositório 4): o ALB que o LB Controller cria a partir do Ingress fica fora do
state e trava a exclusão da VPC.

> **Módulo EKS vendored** (`terraform/modules/eks`): cópia local do
> `terraform-aws-modules/eks/aws` v20.37.2 com um input a mais,
> `cluster_creator_arn`. O módulo original resolve o criador do cluster
> com o data source `aws_iam_session_context`, que chama `iam:GetRole` —
> negado explicitamente pela política da conta do AWS Academy (`Pvoclabs`).
> Com o ARN da role `voclabs` passado por variável, o access entry de
> admin do criador fica explícito, igual ao padrão da aula, sem a
> chamada IAM. Os pontos alterados no módulo estão marcados com
> `[PATCH FIAP lab]` e o código original preservado em comentários.

## State

Não há state anterior a migrar: o state do HCP Terraform nasce no primeiro
apply de cada workspace, que cria a infraestrutura do zero. O backend S3 antigo
(`techchallenge-fiap-v1`) era de outra conta e não é usado.

## Regras de proteção (configurar no GitHub)

- Branch `main` e `develop` protegidas — **sem push direto**.
- Merge somente via **Pull Request** (com o `ci.yml` verde obrigatório).
- O deploy da infraestrutura é disparado pelo HCP Terraform ao detectar o merge.

## Uso local

Pré-requisitos: Terraform `1.16.x` (`required_version = "~> 1.16"`), AWS CLI
autenticado (credenciais do lab) e `kubectl`. Para operar contra um workspace do
TFC, rode `terraform login`, exporte `TF_WORKSPACE` com o nome do workspace (o
workspace precisa ter a tag `techchallenge-infra`) e rode `terraform init`,
`terraform plan` e `terraform apply`. Com o workspace em modo Agent, o plan roda
no agent, não na sua máquina.

Depois do apply, para apontar o kubectl para o cluster:

```bash
aws eks update-kubeconfig --name techchallenge-prod --region us-east-1
```

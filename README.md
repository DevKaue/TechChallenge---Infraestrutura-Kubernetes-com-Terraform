# Tech Challenge - Infraestrutura Kubernetes (Terraform)

**Repositório 2 do projeto.** Infrastructure as Code (Terraform) da camada
Kubernetes na AWS: **VPC, ECR, EKS, addons, ALB Controller, IAM/OIDC e o
namespace/Secret da aplicação**. Todo o ciclo de vida (criar, atualizar e
destruir) é versionado aqui e executado por **GitHub Actions**, com deploy
automático das branches de **homologação** e **produção**.

## Escopo

Este repositório cuida **apenas** da infraestrutura de Kubernetes. Ele **não**
contém o código da aplicação, os manifestos Kustomize, nem o banco de dados:

| Repositório | Responsabilidade |
|---|---|
| 1. Lambda | Function serverless |
| **2. Infraestrutura Kubernetes (este)** | VPC, ECR, EKS, addons, ALB Controller, IAM/OIDC, namespace/Secret |
| 3. Infraestrutura do Banco Gerenciado | RDS PostgreSQL (Terraform) |
| 4. Aplicação principal em Kubernetes | Código da API, Dockerfile, manifestos Kustomize e deploy no cluster |

### Contrato com os outros repositórios

- **Lê do repositório 3** (remote state S3): `db_endpoint`, `db_name`,
  `db_username`, `db_password` — usados para montar o `DATABASE_URL` do Secret
  da aplicação. Aplique o repositório 3 **antes** deste.
- **Expõe para os repositórios 3 e 4**: `vpc_id`, `private_subnet_ids`,
  `node_security_group_id`, `vpc_cidr`, `ecr_url`, `cluster_name`,
  `github_deploy_role_arn`.

## Estrutura

```
terraform/            toda a infraestrutura como código
├── versions.tf       required_version, providers e backend S3
├── providers.tf      aws / kubernetes / helm
├── vpc.tf            VPC 3 AZ, NAT único, tags de subnet para o ALB
├── ecr.tf            repositório com tag imutável e lifecycle
├── eks.tf            cluster 1.32, managed node group, access entries
├── addons.tf         vpc-cni (network policy), coredns, kube-proxy,
│                     metrics-server, pod-identity, Container Insights
├── alb-controller.tf IRSA + Helm do AWS Load Balancer Controller
├── secrets.tf        namespace + Secret com as 4 chaves exigidas pela API
├── remote-state.tf   leitura dos outputs do repositório de banco
├── github-oidc.tf    OIDC provider e role de deploy (sem chave estática)
└── outputs.tf        valores consumidos pelos repositórios 3 e 4
.github/workflows/    ci.yml (validação) e deploy.yml (apply por ambiente)
```

## CI/CD

| Workflow | Dispara em | Faz |
|---|---|---|
| `ci.yml` | PR e push em `develop`/`main` | `terraform fmt -check`, `init -backend=false`, `validate` e scan de misconfiguração (trivy) |
| `deploy.yml` | push em `develop` (homolog) e `main` (produção), ou manual | `terraform init` com state por ambiente, `plan` e `apply` |

O deploy autentica por **OIDC** — não existe `AWS_ACCESS_KEY_ID` no repositório.
Configure em *Settings → Secrets and variables → Actions*:

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `AWS_DEPLOY_ROLE` | `terraform output -raw github_deploy_role_arn` |
| Variable | `AWS_REGION` | `terraform output -raw region` |

O environment `production` é usado no deploy de `main` — crie-o em
*Settings → Environments* para exigir aprovação manual. O environment `homolog`
atende `develop`.

## Regras de proteção (configurar no GitHub)

- Branch `main` e `develop` protegidas — **sem push direto**.
- Merge somente via **Pull Request** (com CI verde obrigatório).
- Deploy automático: `develop` → homologação, `main` → produção.

## Uso local

Veja [`terraform/README.md`](terraform/README.md) para pré-requisitos, bootstrap
do backend S3, `plan`/`apply` e `destroy`.

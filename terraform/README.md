# Terraform — infraestrutura Kubernetes na AWS

Cria a camada Kubernetes do projeto: VPC, ECR, EKS, addons, namespace, Secret da
aplicação, ALB Controller e a role de deploy do CI.

```
versions.tf           required_version, providers e backend S3
providers.tf          configuração de aws / kubernetes / helm
main.tf               AZs e tags comuns
vpc.tf                VPC 3 AZ, NAT único, TAGS de subnet para o ALB
ecr.tf                repositório com tag imutável e lifecycle
eks.tf                cluster 1.32, managed node group, access entries
addons.tf             vpc-cni (network policy), coredns, kube-proxy,
                      metrics-server, pod-identity, Container Insights
secrets.tf            namespace + Secret com as 4 chaves de validateEnv()
remote-state.tf       leitura dos outputs do repositório de banco
alb-controller.tf     IRSA + Helm do AWS Load Balancer Controller
github-oidc.tf        OIDC provider e role de deploy (sem chave estática)
outputs.tf            valores consumidos pelos repositórios de banco e aplicação
```

> O **banco de dados (RDS) não vive aqui** — pertence ao repositório 3
> (Infraestrutura do Banco Gerenciado). Este repositório apenas lê os outputs
> dele via `remote-state.tf` para montar o `DATABASE_URL` do Secret.

## Pré-requisitos

- Terraform ~> 1.10 (o backend usa `use_lockfile`, que exige 1.10+)
- AWS CLI v2, `kubectl`, `helm`
- Credenciais com permissão de admin (`aws sts get-caller-identity` responde)

## Ordem de aplicação

1. **Repositório 3 (banco)** — cria o RDS e publica `db_endpoint`, `db_name`,
   `db_username` e `db_password` no state S3 (key padrão `db/prod/terraform.tfstate`).
2. **Este repositório** — lê esses outputs e cria VPC/EKS/ECR/ALB/Secret.

Sem o state do banco publicado, o `plan`/`apply` daqui falha ao ler os outputs.

## Bootstrap do backend (uma vez por conta)

O state fica em S3 para que o time compartilhe o mesmo estado e o arquivo — que
contém `DATABASE_URL`, `JWT_SECRET`, `PASSWORD_SALT` e `WEBHOOK_SECRET` em texto
claro — não more no laptop de uma pessoa. O bucket precisa existir **antes** do
primeiro `init`:

```bash
aws s3api create-bucket --bucket techchallenge-fiap-v1 --region us-east-1
# Versionamento é o que permite recuperar um state corrompido ou sobrescrito.
aws s3api put-bucket-versioning --bucket techchallenge-fiap-v1 \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket techchallenge-fiap-v1 \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Locking é nativo do S3 (`use_lockfile = true`) — não há tabela DynamoDB.

## Uso

```bash
cd terraform
cp example.tfvars terraform.tfvars      # gitignored
$EDITOR terraform.tfvars

terraform init
terraform plan -out=tfplan              # LEIA o plano antes
terraform apply tfplan                  # ~20 min (EKS ~10)

eval "$(terraform output -raw kubeconfig_command)"
kubectl get nodes
```

O primeiro `apply` precisa de credenciais locais: a role OIDC do CI é criada
pelo próprio Terraform. Os applies seguintes podem rodar pelo `deploy.yml`.

## Destruir

```bash
terraform plan -destroy -out=tfdestroy    # LEIA o que será apagado
terraform apply tfdestroy
```

Sai limpo de propósito: `force_delete` no ECR. Em produção real seria o inverso —
aqui a prioridade é não deixar recurso órfão queimando crédito.

> ⚠️ **`tfplan` e `tfdestroy` nunca vão para o git.** Um plano salvo guarda os
> valores planejados — `DATABASE_URL`, `JWT_SECRET`, `PASSWORD_SALT` e
> `WEBHOOK_SECRET` em **texto claro**; o de destroy carrega o estado atual
> inteiro. O `.gitignore` cobre os nomes padrão, então use esses nomes.

> Se o `destroy` travar na VPC, quase sempre é um ALB órfão: remova o Ingress da
> aplicação (no repositório 4) **antes** do destroy, senão o Load Balancer
> Controller deixa o LB para trás e a subnet não some.

## Custo estimado

| Recurso | ~US$/dia |
|---|---|
| EKS control plane | 2,40 |
| 2× c7i-flex.large | 2,00 |
| NAT Gateway | 1,10 |
| ALB | 0,60 |
| **Total** | **~6,10** |

(Fora do RDS, que pertence ao repositório de banco.) Um fim de semana esquecido
custa ~US$ 18. `terraform destroy` ao fim de cada sessão de trabalho.

## Decisões

| Decisão | Motivo |
|---|---|
| Backend S3 com `use_lockfile` | Três pessoas trabalham no repo: state local significaria que só quem aplicou consegue aplicar de novo, e o arquivo com os quatro segredos ficaria num laptop. O bucket é criado uma vez à mão — o chicken-and-egg do backend não tem solução elegante |
| State por ambiente | `develop` grava em `homolog/terraform.tfstate` e `main` em `prod/terraform.tfstate`; um ambiente não sobrescreve o outro |
| Versões de módulo **exatas** | O `.terraform.lock.hcl` trava providers, **não módulos**. Com `~>`, um `init` numa máquina nova traria versão diferente da validada. Bump vira PR explícito |
| NAT único | ~US$ 32/mês contra ~US$ 96. Se a AZ do NAT cair, os nós das outras perdem saída — aceitável aqui, não em produção real |
| Endpoint público do cluster | Sem ele seria preciso bastion/VPN para `kubectl`. Continua autenticado por IAM e autorizado por RBAC |
| Access entries, não `aws-auth` | O ConfigMap está em depreciação |
| `enableNetworkPolicy` no VPC CNI | Sem esta flag as NetworkPolicies são **aceitas e não aplicadas** — a mesma armadilha do Docker Desktop |
| `metrics-server` como addon | Não vem por padrão no EKS; sem ele o HPA fica `<unknown>` e a escalabilidade não funciona |
| Container Insights em vez de EFK | Um addon contra ~200 linhas de YAML de Elasticsearch/Fluentd/Kibana. Mesma pergunta respondida (métricas e logs), muito menos peça móvel |
| Senhas da aplicação via `random_password` | Nenhum segredo em `.tfvars` nem no git |
| Secret do K8s pelo Terraform, sem External Secrets | Para UM Secret de QUATRO chaves, o ESO custaria um operator, um CRD, uma role IRSA e um `kubectl apply` manual. As chaves são geradas aqui (exceto o banco, lido do repo 3) |
| Namespace criado aqui, não pelo Kustomize | O Secret precisa do namespace antes, e o Terraform roda antes do `kubectl apply -k` do repositório 4 |
| `c7i-flex.large` nos nós | Contas no AWS Free Tier **bloqueiam** tipos fora da faixa gratuita; `t3.medium` falha na criação do node group. Mesmos 2 vCPU / 4 GiB |
| Role do CI restrita ao repo | A condição `sub = repo:owner/repo:*` impede que outro repositório assuma a role |

### Dívidas conscientes

- **A role de deploy é admin na AWS e no EKS.** O `terraform apply` cria VPC,
  IAM, EKS e escreve no state; restringir exigiria enumerar cada recurso. Em
  conta real, troque `github_deploy_policy_arns` por uma policy sob medida.
- **`PASSWORD_SALT` é gerado pelo Terraform.** Ele é estável no state, mas um
  `destroy`/`apply` gera outro e **invalida todas as senhas já gravadas**. Se
  o banco tiver dados reais, mova o valor para fora do ciclo de vida do
  Terraform antes.
- **Sem TLS por padrão.** O ALB sobe em HTTP; HTTPS exige domínio + certificado
  ACM no Ingress do repositório 4.
- **`terraform destroy` não apaga o bucket de state.** Ele é criado fora do
  Terraform de propósito — apagá-lo junto destruiria o histórico de versões que
  serve justamente para recuperar de um destroy indevido.

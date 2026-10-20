#!/usr/bin/env bash
# Atualiza os secrets AWS_LAB_* dos repositórios com as credenciais da sessão
# atual do AWS Academy.
#
# Por que existe: no lab não há OIDC, e as credenciais temporárias expiram a
# cada sessão (~4h). Sem isto, cada deploy começa com o mesmo copiar-e-colar em
# três repositórios, e um secret esquecido faz o apply falhar no meio.
#
# Uso:
#   1. No Academy: Start Lab → AWS Details → AWS CLI: Show; cole o bloco no
#      ~/.aws/credentials, na seção [academy].
#   2. ./scripts/atualizar-credenciais-lab.sh [owner/repo ...]
#      Sem argumentos, atualiza os 3 repositórios com Terraform.
#
# Os valores vão para o `gh secret set` pela entrada padrão: não aparecem na
# tela, no histórico do shell nem na lista de processos. Repositório em que você
# não é admin é pulado com aviso (criar secret exige admin).
set -euo pipefail

perfil=${AWS_PROFILE:-academy}

if [ "$#" -gt 0 ]; then
  repos=("$@")
else
  repos=(
    thiagoalmeida88/TechChallenge---Infraestrutura-Kubernetes-com-Terraform
    DevKaue/tech-challenge-database-infra
    DevKaue/TechChallange---Function-Serverless
  )
fi

# Exporta só para este processo; nada é escrito em disco.
eval "$(aws configure export-credentials --profile "$perfil" --format env-no-export)"

if [ -z "${AWS_SESSION_TOKEN:-}" ]; then
  echo "erro: o perfil '$perfil' não tem session token. As credenciais do Academy são temporárias e sempre trazem um." >&2
  exit 1
fi

# Confere antes de gravar: credencial vencida nos secrets só falharia no deploy.
conta=$(aws sts get-caller-identity --query Account --output text)
echo "Credenciais válidas da conta $conta (perfil $perfil)."

for repo in "${repos[@]}"; do
  if [ "$(gh api "repos/$repo" --jq '.permissions.admin')" != "true" ]; then
    echo "⚠ $repo: sem admin, pulado. Peça a um admin para rodar este script."
    continue
  fi
  printf '%s' "$AWS_ACCESS_KEY_ID" | gh secret set AWS_LAB_ACCESS_KEY_ID -R "$repo"
  printf '%s' "$AWS_SECRET_ACCESS_KEY" | gh secret set AWS_LAB_SECRET_ACCESS_KEY -R "$repo"
  printf '%s' "$AWS_SESSION_TOKEN" | gh secret set AWS_LAB_SESSION_TOKEN -R "$repo"
  echo "✓ $repo"
done

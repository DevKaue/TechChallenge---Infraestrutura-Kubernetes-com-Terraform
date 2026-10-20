#!/usr/bin/env bash
# Confere um tfplan e grava o resumo das mudanças.
#
# Uso: conferir-plan.sh <tfplan> <arquivo-de-resumo>
#
# O deploy de rotina nunca deve destruir (nem recriar) o que custa caro refazer
# ou carrega estado: o cluster, a VPC, o repositório de imagens e o segredo JWT.
# Um replace do segredo JWT rotaciona a chave e invalida os tokens da Lambda, do
# app e do Kong de uma vez, com o apply "dando certo". Derrubar o ambiente é
# trabalho do destroy.yml, com confirmação; aqui o pipeline para antes do apply.
#
# O resumo tem só endereço e ações de cada recurso, nunca valores: é ele que o
# job de apply compara com o próprio plan, e por isso pode virar artifact num
# repositório público. O tfplan não pode: carrega o segredo JWT em claro.
set -euo pipefail

plano=$1
resumo=$2

# O plan.json carrega os valores do plano (o segredo JWT inclusive): sai em
# qualquer caminho, inclusive quando o show ou o jq falham no meio.
trap 'rm -f plan.json' EXIT

terraform show -json "$plano" > plan.json

protegidos=$(jq -r '(.resource_changes // [])[]
  | select(.type == "aws_eks_cluster"
        or .type == "aws_vpc"
        or .type == "aws_ecr_repository"
        or (.type == "random_password" and .name == "jwt_secret"))
  | select(.change.actions | index("delete"))
  | .address' plan.json)
if [ -n "$protegidos" ]; then
  echo "::error::O plan destrói ou recria recurso protegido: $protegidos. Para derrubar o ambiente, use o workflow destroy."
  exit 1
fi

jq -S '[(.resource_changes // [])[]
  | select(.change.actions != ["no-op"] and .change.actions != ["read"])
  | {address, actions: .change.actions}]
  | sort_by(.address)' plan.json > "$resumo"

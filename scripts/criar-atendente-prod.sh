#!/usr/bin/env bash
# Cria (ou redefine a senha de) um ATENDENTE no banco de PRODUÇÃO do App.
#
# Por que existe: o banco de prod nasce vazio e o único jeito de criar usuário é
# o seed do App, que grava atendente e mecânicos com a senha `Tech@123`, escrita
# no seed.ts de um repositório público. Com o App atrás de um NLB público, rodar
# o seed em prod entregaria o login de atendente a qualquer pessoa. Este script
# cria só o usuário que você pedir, com a senha que você digitar.
#
# Como funciona: o hash é gerado DENTRO do pod da API, com o mesmo algoritmo e o
# PASSWORD_SALT que o App usa para verificar (scrypt, chave de 64 bytes, formato
# `scrypt:<base64>`). A senha viaja só pela entrada padrão do kubectl: não vai
# para argumento de comando, histórico do shell nem log.
#
# Uso (em um terminal SEU, porque pede a senha de forma interativa):
#   ./scripts/criar-atendente-prod.sh email@exemplo.com "Nome Completo"
#
# Pré-requisitos: perfil `academy` do AWS CLI com a sessão do lab ativa
# (conta do cluster), kubectl e o cluster techchallenge-prod de pé.
# Rodar de novo com o mesmo e-mail REDEFINE a senha (útil se você a esqueceu).
set -euo pipefail

email=${1:?uso: $0 <email> "<Nome Completo>"}
nome=${2:?uso: $0 <email> "<Nome Completo>"}
cluster=${EKS_CLUSTER_NAME:-techchallenge-prod}
namespace=${NAMESPACE:-techchallenge}
perfil=${AWS_PROFILE:-academy}

# O login do App normaliza o e-mail para minúsculas: gravar diferente é um
# usuário que nunca consegue entrar.
email=$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')
case "$email" in
  *@*.*) ;;
  *) echo "erro: e-mail inválido: $email" >&2; exit 1 ;;
esac

read -r -s -p "Senha (mínimo 8 caracteres): " senha; echo
read -r -s -p "Repita a senha: " confirmacao; echo
if [ "$senha" != "$confirmacao" ]; then echo "erro: as senhas não conferem." >&2; exit 1; fi
# O LoginDto do App exige MinLength(8): uma senha menor cria um usuário que o
# login recusa antes de comparar o hash.
if [ "${#senha}" -lt 8 ]; then echo "erro: a senha precisa ter pelo menos 8 caracteres." >&2; exit 1; fi

# kubeconfig descartável: não mexe no ~/.kube/config de ninguém.
export KUBECONFIG
KUBECONFIG=$(mktemp)
trap 'rm -f "$KUBECONFIG"' EXIT
AWS_PROFILE=$perfil aws eks update-kubeconfig --name "$cluster" --region us-east-1 >/dev/null

# E-mail e nome não são segredo e vão como variável de ambiente do processo; a
# senha só pela entrada padrão.
# O programa Node vai entre aspas simples de propósito: o $1..$4 dele são
# placeholders do SQL, e o shell não pode expandi-los.
# shellcheck disable=SC2016
printf '%s' "$senha" | kubectl -n "$namespace" exec -i deploy/techchallenge-api -c api -- \
  env USER_EMAIL="$email" USER_NAME="$nome" node -e '
const { scryptSync } = require("crypto");
const { Client } = require("pg");
let senha = "";
process.stdin.on("data", (d) => (senha += d)).on("end", async () => {
  const c = new Client({ connectionString: process.env.DATABASE_URL });
  try {
    await c.connect();
    const hash = "scrypt:" + scryptSync(senha, process.env.PASSWORD_SALT, 64).toString("base64");
    const r = await c.query(
      "INSERT INTO users (id, name, role, email, password_hash, updated_at) " +
      "VALUES (gen_random_uuid()::text, $1, $2, $3, $4, now()) " +
      "ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, updated_at = now() " +
      "RETURNING (xmax = 0) AS criado, role",
      [process.env.USER_NAME, "ATTENDANT", process.env.USER_EMAIL, hash]
    );
    const { criado, role } = r.rows[0];
    console.log((criado ? "atendente criado" : "senha redefinida") + ": " + process.env.USER_EMAIL + " (" + role + ")");
  } catch (e) {
    console.error("erro:", e.name, String(e.message).replace(/postgresql:\/\/\S+/g, "<oculto>").slice(0, 200));
    process.exitCode = 1;
  } finally {
    await c.end().catch(() => {});
  }
});
'

#!/usr/bin/env bash
# Recicla os nós do EKS que subiram mas não entraram no cluster.
#
# Por que existe: no AWS Academy (Learner Lab), quando a sessão termina as
# instâncias são paradas e o ASG as substitui NA JANELA em que uma SCP da
# organização nega ec2:DescribeInstances à LabRole. O `nodeadm` do nó novo
# precisa dessa chamada para se registrar: leva 403, desiste depois de ~10 min e
# nunca tenta de novo. O resultado é uma instância `running` e "saudável" para o
# ASG, mas fora do cluster: todo pod fica Pending e o NLB do Kong fica sem
# destino (timeout). Terminar a instância com o lab já ativo faz o ASG lançar
# outra, que registra em ~30 s.
#
# Quando rodar: depois de cada Start Lab, com as credenciais do perfil `academy`
# renovadas (./scripts/atualizar-credenciais-lab.sh cuida dos secrets do GitHub;
# o ~/.aws/credentials você cola à mão).
#
# Uso:
#   ./scripts/reciclar-nos.sh             # detecta, pede confirmação e recicla
#   ./scripts/reciclar-nos.sh --dry-run   # só mostra o que reciclaria
#   ./scripts/reciclar-nos.sh --yes       # recicla sem perguntar
#
# Variáveis (todas opcionais): AWS_PROFILE (academy), EKS_CLUSTER_NAME
# (techchallenge-prod), AWS_REGION (us-east-1), GRACE_MIN (12), WAIT_MIN (10).
set -euo pipefail

cluster=${EKS_CLUSTER_NAME:-techchallenge-prod}
export AWS_PROFILE=${AWS_PROFILE:-academy}
export AWS_REGION=${AWS_REGION:-us-east-1}
export AWS_DEFAULT_REGION=$AWS_REGION
# Instância mais nova que isto ainda pode estar subindo normalmente: o nodeadm só
# desiste depois de ~10 min, então reciclar antes mata um nó que ia registrar.
grace_min=${GRACE_MIN:-12}
wait_min=${WAIT_MIN:-10}
# Permite trocar o binário nos testes do próprio script (KUBECTL=false).
kubectl_bin=${KUBECTL:-kubectl}

dry_run=false
assume_yes=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --yes | -y) assume_yes=true ;;
    -h | --help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "argumento desconhecido: $arg (use --dry-run, --yes ou --help)" >&2; exit 2 ;;
  esac
done

erro() { echo "erro: $*" >&2; exit 1; }

# Epoch de um LaunchTime ISO 8601. python3 em vez de `date -d`, que muda entre o
# GNU (Linux) e o BSD (macOS).
epoch() {
  python3 -I -c 'import sys; from datetime import datetime; print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))' "$1"
}

conta=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || erro "credenciais do perfil '$AWS_PROFILE' inválidas ou vencidas. Faça Start Lab no Academy e atualize o ~/.aws/credentials."
echo "Conta $conta, cluster $cluster."

asg=$(aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?Tags[?Key=='eks:cluster-name' && Value=='$cluster']].AutoScalingGroupName | [0]" \
  --output text)
if [ -z "$asg" ] || [ "$asg" = "None" ]; then erro "não achei o Auto Scaling Group do cluster $cluster."; fi

desired=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
# As crases são o literal do JMESPath e não podem ser expandidas pelo shell.
# shellcheck disable=SC2016
instances=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)

# kubeconfig descartável: não mexe no ~/.kube/config de ninguém.
export KUBECONFIG
KUBECONFIG=$(mktemp)
trap 'rm -f "$KUBECONFIG"' EXIT
aws eks update-kubeconfig --name "$cluster" >/dev/null

# TRAVA: se o kubectl falhar, "nenhum nó registrado" seria indistinguível de "não
# consegui perguntar", e o script terminaria nós saudáveis. Sem a lista, não faz nada.
if ! nos=$("$kubectl_bin" get nodes -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' 2>/dev/null); then
  erro "não consegui listar os nós do cluster; não vou reciclar nada sem saber quais estão registrados."
fi
registrados=$(printf '%s\n' "$nos" | sed 's#.*/##' | grep -E '^i-' || true)

agora=$(date -u +%s)
zumbis=""
echo "Instâncias do ASG ($asg), desejadas: $desired"
for id in $instances; do
  if printf '%s\n' "$registrados" | grep -qx "$id"; then
    echo "  $id  registrada no cluster (ok)"
    continue
  fi
  lancada=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].LaunchTime' --output text)
  idade_min=$(( (agora - $(epoch "$lancada")) / 60 ))
  if [ "$idade_min" -lt "$grace_min" ]; then
    echo "  $id  fora do cluster há ${idade_min} min: ainda dentro da tolerância de ${grace_min} min, deixando subir"
  else
    echo "  $id  FORA do cluster há ${idade_min} min: candidata a reciclar"
    zumbis="$zumbis $id"
  fi
done

if [ -z "${zumbis// /}" ]; then
  echo "Nenhum nó para reciclar."
  "$kubectl_bin" get nodes --no-headers 2>/dev/null | awk '{print "  nó " $1 " " $2}'
  exit 0
fi

if $dry_run; then
  echo "[--dry-run] reciclaria:$zumbis"
  exit 0
fi

if ! $assume_yes; then
  read -r -p "Reciclar:$zumbis ? O ASG lança substitutas. [s/N] " resposta
  case "$resposta" in s | S | sim | SIM) ;; *) echo "Cancelado."; exit 0 ;; esac
fi

for id in $zumbis; do
  # --no-should-decrement: o ASG mantém a capacidade desejada e lança outra.
  aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$id" \
    --no-should-decrement-desired-capacity --query 'Activity.Description' --output text
done

echo "Aguardando $desired nó(s) Ready (até ${wait_min} min)..."
limite=$(( $(date +%s) + wait_min * 60 ))
while :; do
  prontos=$("$kubectl_bin" get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  if [ "$prontos" -ge "$desired" ]; then break; fi
  if [ "$(date +%s)" -ge "$limite" ]; then
    erro "só $prontos de $desired nó(s) Ready depois de ${wait_min} min. Veja o boot da instância: aws ec2 get-console-output --instance-id <id> --latest"
  fi
  sleep 15
done

echo "Nós Ready: $prontos"
"$kubectl_bin" get nodes --no-headers | awk '{print "  nó " $1 " " $2}'
echo "Pods que ainda não estão Running (os de sistema levam ~1 min para subir):"
"$kubectl_bin" get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"{print "  " $1 " " $2 " " $4}' | head -15

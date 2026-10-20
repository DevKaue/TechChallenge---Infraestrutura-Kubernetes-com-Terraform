# HCP Terraform Agent com o AWS CLI.
#
# Por que existe: o provider Helm autentica no EKS com `aws eks get-token`
# (terraform/providers.tf), e nem o runner padrão do HCP Terraform nem a imagem
# oficial do agent trazem o AWS CLI. Sem ele, o plan falha ao configurar o
# provider com "executable aws not found".
#
# Versão do agent fixada: com `latest`, um rebuild troca o agent sem ninguém
# ter decidido isso. Multi-arquitetura: roda nativo em Mac com Apple Silicon
# (arm64) e em máquina x86 (amd64).
FROM hashicorp/tfc-agent:1.33.1

ARG TARGETARCH

USER root

# AWS CLI v2 pelo instalador oficial, no binário da arquitetura da imagem.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) aws_arch="x86_64" ;; \
      arm64) aws_arch="aarch64" ;; \
      *) echo "arquitetura sem AWS CLI v2: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    aws --version

# De volta ao usuário sem privilégio da imagem oficial.
USER tfc-agent

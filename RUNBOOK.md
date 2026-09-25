# Runbook — Padronização do Scalar e publicação do OpenAPI

## Objetivo

Padronizar o Scalar usado em produção e dev na versão `1.72.1`, corrigir o formato gerado pelo backend e deixar os pipelines responsáveis por atualizar a documentação no momento correto.

Este procedimento não altera o endpoint privado de OpenAPI do backend e não usa digest de imagem ou SHA256 como parte da publicação.

## Arquitetura atual

### Produção

- Site: `https://docs.diversifi.ai`
- HTML e `openapi.json`: bucket `docs-api-diversifi-ai`
- Distribuição: CloudFront com origem S3 privada
- Publisher: `scripts/publish-scalar-prod.sh`
- Workflow: `.github/workflows/publish-prod.yml`

O Terraform cria o bucket, CloudFront e DNS. A publicação dos objetos é feita pelo pipeline.

### Dev

- Site: `https://dev-docs.diversifi.ai`
- Serviço: Deployment `scalar-dev` no namespace Kubernetes `scalar`
- Manifesto: `devops-misc/scalar/10-deployment.yaml`
- OpenAPI público: `https://dev-docs-openapi.diversifi.ai/openapi.json`
- Bucket do OpenAPI: `docs-api-dev-diversifi-ai`
- Proxy do Scalar: `https://proxy.scalar.com`

O site Scalar continua no Kubernetes. O bucket e o CloudFront servem somente o arquivo OpenAPI.

## Versões fixadas

| Ambiente | Configuração | Versão |
|---|---|---|
| Produção | CDN `@scalar/api-reference` | `1.72.1` |
| Dev | `scalarapi/api-reference` | `0.6.8`, que contém Scalar `1.72.1` |
| Publisher | `@scalar/cli` | `2.1.0` |

Não usar `latest` no Deployment de dev nem no CDN da produção.

## Alterações necessárias

### 1. Backend

Arquivo: `diversifi-be/src/main.py`

Alterar `x-scalar-environments.<environment>.variables` de objeto para lista. Cada item deve possuir `name` e `value`, mantendo as descrições e valores atuais.

Formato esperado:

```json
"variables": [
  {
    "name": "apiUrl",
    "value": {
      "description": "API Base URL",
      "default": "..."
    }
  },
  {
    "name": "apiKey",
    "value": {
      "description": "Your API Key (X-API-Key header)",
      "default": ""
    }
  }
]
```

Arquivo: `diversifi-be/scripts/export_openapi.py`

Manter o exportador como fonte do arquivo estático e adicionar a validação necessária para falhar quando a estrutura Scalar estiver fora do formato esperado.

### 2. Produção

Arquivo: `scripts/publish-scalar-prod.sh`

- Fixar o CDN em `@scalar/api-reference@1.72.1`.
- Fixar a versão do `@scalar/cli` usada pelo workflow.
- Manter `SPEC_URL` como `https://docs.diversifi.ai/openapi.json`.
- Publicar o `openapi.json` antes de publicar ou atualizar o `index.html`.
- Invalidar `/index.html` depois da atualização.

Arquivo: `.github/workflows/publish-prod.yml`

- Manter o acionamento pelo pipeline do backend.
- Executar o publisher somente depois de o backend gerar e publicar o `openapi.json`.
- Fazer o workflow falhar se a validação ou a publicação do arquivo falhar.

### 3. Dev

Arquivo: `devops-misc/scalar/10-deployment.yaml`

Trocar:

```yaml
image: scalarapi/api-reference:latest
```

por:

```yaml
image: scalarapi/api-reference:0.6.8
```

Usar `https://dev-docs-openapi.diversifi.ai/openapi.json` como fonte do OpenAPI e manter o `proxyUrl` existente.

Arquivo: `diversifi-be/.github/workflows/deploy-npd.yml`

- Depois do rollout, gerar e validar o OpenAPI a partir da imagem implantada do backend.
- Publicar `openapi.json` em `s3://docs-api-dev-diversifi-ai/openapi.json`.
- Invalidar `/openapi.json` na distribuição de `dev-docs-openapi.diversifi.ai`.
- Não disparar um publisher Scalar para o site dev.

O Deployment Kubernetes continua sendo responsável somente pela interface do Scalar.

### 4. Infraestrutura do OpenAPI dev

Arquivo: `devops-misc/production/api-docs.tf`

Adicionar o site `dev` com o bucket `docs-api-dev-diversifi-ai` e o domínio `dev-docs-openapi.diversifi.ai`. O bucket permanece privado e o acesso ocorre pela CloudFront com OAC.

## Ordem de execução

1. Corrigir o formato de `variables` no backend.
2. Gerar os OpenAPI de dev e produção localmente ou dentro da imagem do backend.
3. Validar JSON, referências e estrutura Scalar.
4. Fixar `@scalar/api-reference@1.72.1` no publisher de produção.
5. Fixar `@scalar/cli` em uma versão testada.
6. Fixar o Deployment dev em `scalarapi/api-reference:0.6.8`.
7. Aplicar a infraestrutura do bucket e do domínio OpenAPI dev.
8. Ajustar o pipeline dev para publicar e invalidar o arquivo.
9. Executar o pipeline do backend em dev.
10. Confirmar `https://dev-docs-openapi.diversifi.ai/openapi.json`.
11. Aplicar o Deployment Scalar com a versão fixada.
12. Abrir `https://dev-docs.diversifi.ai` e confirmar que as operações aparecem.
13. Executar o fluxo de produção e atualizar o bucket da documentação.
14. Abrir `https://docs.diversifi.ai` e confirmar que as operações aparecem.

## Validação

### OpenAPI gerado

Confirmar:

- JSON válido;
- versão OpenAPI esperada;
- `x-scalar-environments` presente quando habilitado;
- `variables` como lista;
- `apiUrl` e `apiKey` presentes;
- nenhum token ou chave real no documento;
- referências internas resolvidas.

### Dev

Confirmar:

- Deployment usando `scalarapi/api-reference:0.6.8`;
- pod pronto e sem reinícios;
- `dev-docs.diversifi.ai` respondendo;
- `dev-docs-openapi.diversifi.ai/openapi.json` retornando JSON;
- tela do Scalar preenchida;
- nenhuma ocorrência de `n.variables is not iterable` no navegador;
- OpenAPI carregado a partir do domínio estático.

### Produção

Confirmar:

- `docs.diversifi.ai/openapi.json` retornando JSON;
- `index.html` carregando `@scalar/api-reference@1.72.1`;
- tela do Scalar preenchida;
- CloudFront atualizado depois da invalidação;
- endpoint interno `platform.diversifi.ai/api_v1/openapi.json` permanecendo protegido.

## Rollback

### Dev

1. Restaurar o manifesto anterior do Deployment.
2. Aplicar o manifesto no namespace `scalar`.
3. Aguardar o pod ficar pronto.
4. Confirmar o acesso a `dev-docs.diversifi.ai`.

### Produção

1. Restaurar o `index.html` anterior no bucket.
2. Restaurar o `openapi.json` anterior, se ele tiver sido alterado.
3. Criar invalidação para `/index.html`.
4. Confirmar o carregamento de `docs.diversifi.ai`.

Não alterar o bloqueio do OpenAPI no backend durante o rollback.

## Arquivos envolvidos

- `diversifiai-api-docs/scripts/publish-scalar-prod.sh`
- `diversifiai-api-docs/.github/workflows/publish-prod.yml`
- `diversifi-be/src/main.py`
- `diversifi-be/scripts/export_openapi.py`
- `diversifi-be/.github/workflows/deploy-prod.yml`
- `diversifi-be/.github/workflows/deploy-npd.yml`
- `devops-misc/production/api-docs.tf`
- `devops-misc/scalar/10-deployment.yaml`

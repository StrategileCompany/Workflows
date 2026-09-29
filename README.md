# Workflows

Workflows reutilizáveis do GitHub Actions (`workflow_call`) e a infraestrutura Terraform usada pelos projetos .NET/Azure da Strategile.

A ideia é que cada repositório de aplicação não tenha pipeline própria: ele apenas **chama** um dos workflows daqui, passando os `inputs` e `secrets`. Assim, a correção ou melhoria de um passo de build/deploy vale para todos os projetos de uma vez.

## Conteúdo

| Arquivo | O que faz |
| --- | --- |
| [`.github/workflows/azure-terraform-iac.yml`](.github/workflows/azure-terraform-iac.yml) | Provisiona a infraestrutura no Azure (`infra/main.tf`) com Terraform: init/validate/plan/apply, state remoto em Storage Account e um workspace por `Projeto-Ambiente`. |
| [`.github/workflows/azure-function-web-api.yml`](.github/workflows/azure-function-web-api.yml) | Build, publish e deploy de uma Web API em Azure Functions (Flex Consumption), via `az functionapp deployment source config-zip`. |
| [`.github/workflows/azure-static-web-app.yml`](.github/workflows/azure-static-web-app.yml) | Build e deploy de um Azure Static Web App (Blazor/landing page), substituindo tokens de configuração antes da publicação. |
| [`.github/workflows/windows-console-app.yml`](.github/workflows/windows-console-app.yml) | Build de um app console .NET no Windows, empacotamento em `.zip` e envio para um servidor SFTP. |
| [`infra/main.tf`](infra/main.tf) | Definição Terraform de todos os recursos Azure do projeto. |

## Convenção de nomes

Quase tudo é derivado de `Project` + `AppEnv`:

- Resource Group: `RG-<Project>-<AppEnv>`
- Function App, Static Web App, App Insights, Log Analytics, Service Plan, ACS: `<Project>-<AppEnv>`
- Landing page: `<Project>-<AppEnv>-landing`
- Storage Account: `<project>4<appenv>` (minúsculo, `-` vira `4`)
- Workspace do Terraform: `<Project>-<AppEnv>`

## Como usar

No repositório da aplicação, crie um workflow que chame os daqui. Exemplo típico — infra primeiro, depois API e front:

```yaml
name: Deploy

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  infra:
    uses: StrategileCompany/Workflows/.github/workflows/azure-terraform-iac.yml@main
    with:
      Project: MeuProjeto
      AppEnv: HMG
    secrets:
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
      ConnectionStringValue: ${{ secrets.ConnectionStringValue }}

  api:
    needs: infra
    uses: StrategileCompany/Workflows/.github/workflows/azure-function-web-api.yml@main
    with:
      Project: MeuProjeto
      AppEnv: HMG
      RootPath: src/WebApi/
      OutPath: ./output
    secrets:
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}

  webapp:
    needs: api
    uses: StrategileCompany/Workflows/.github/workflows/azure-static-web-app.yml@main
    with:
      Project: MeuProjeto
      AppEnv: HMG
      AppType: webapp
      RootPath: src/BlazorApp
      OutPath: wwwroot
      ApiUrl: https://meuprojeto-hmg.azurewebsites.net
      IncludeFileToReplace: wwwroot/appsettings.json
    secrets:
      AZURE_CREDENTIALS: ${{ secrets.AZURE_CREDENTIALS }}
```

Quando só a aplicação mudou e a infra está estável, passe `Enabled: false` no job de infra: os passos do Terraform são pulados e o job continua verde, para os jobs que dependem dele seguirem normalmente.

## Referência dos workflows

### Azure Terraform IaC

| Input | Obrigatório | Default | Descrição |
| --- | --- | --- | --- |
| `Project` | sim | — | Nome base do projeto. |
| `AppEnv` | sim | — | Ambiente (`DEV`, `HMG`, `STG`, `PRD`…). |
| `Enabled` | não | `true` | `false` pula init/plan/apply mantendo o job verde. |
| `ConnectionStringType` | não | `SQLServer` | Tipo da connection string criada na Function. |
| `ConnectionStringName` | não | `Default` | Nome da chave da connection string. |
| `DotNetVersion` | não | `10.0` | Runtime .NET da Function (`8.0` ou `10.0`). |
| `CreateResourceACS` | não | `false` | Cria os recursos de e-mail (Azure Communication Services). |
| `CustomDomain` | não | `""` | Domínio próprio de envio. Vazio ou com menos de 4 caracteres = só o domínio gerenciado do Azure. |
| `CustomDomainVerified` | não | `false` | Só `true` depois de verificar o domínio no Azure; cria o vínculo domínio↔ACS. |
| `StaticWebAppSku` | não | `Free` | Plano dos Static Web Apps: `Free` (limitado a 10 por assinatura) ou `Standard` (pago). |
| `TF_ResourceGroupName` | não | `RG-Terraform-State` | RG do Storage Account do state. |
| `TF_StorageAccountName` | não | `tf2gha4suaempresa` | Storage Account do state. |
| `TF_ContainerName` | não | `terraform-state` | Container do state. |

Secrets: `AZURE_CREDENTIALS`, `ConnectionStringValue`.

### Azure Function Web Api

| Input | Obrigatório | Default | Descrição |
| --- | --- | --- | --- |
| `Project` | sim | — | Nome do projeto. |
| `AppEnv` | sim | — | Ambiente. |
| `RootPath` | sim | — | Pasta raiz do projeto de Function (ex.: `src/AzureFunction/`). |
| `OutPath` | sim | — | Pasta de saída do build. |
| `DotNetVersion` | não | `10.0.x` | Versão do .NET do build. |
| `Configuration` | não | `Release` | `Debug` ou `Release`. |
| `FunctionSlot` | não | `Production` | Slot de publicação. |
| `FunctionSku` | não | `flexconsumption` | SKU da Function. |

Secret: `AZURE_CREDENTIALS`.

### Azure Static Web App

| Input | Obrigatório | Descrição |
| --- | --- | --- |
| `Project` | sim | Nome do projeto. |
| `AppEnv` | sim | Ambiente. Sufixa o nome no `manifest.webmanifest` quando diferente de `PRD`. |
| `AppType` | sim | `landing` ou `webapp` — compõe o nome do recurso. |
| `RootPath` | sim | Pasta raiz do projeto (ex.: `src/BlazorApp`). |
| `OutPath` | sim | Pasta de saída dos artefatos. |
| `ApiUrl` | sim | URL completa da API, que substitui `#{BaseAddressUrl}`. |
| `IncludeFileToReplace` | sim | Arquivos onde o token `#{BaseAddressUrl}` será substituído. |

Secret: `AZURE_CREDENTIALS`. O token de publicação do Static Web App é obtido em tempo de execução via `az staticwebapp secrets list`, então não precisa ser guardado no repositório.

O projeto deve conter os tokens `#{BaseAddressUrl}` (no arquivo indicado por `IncludeFileToReplace`) e `#{APPENV}` (em `wwwroot/manifest.webmanifest`).

### Windows Console App

| Input | Obrigatório | Default | Descrição |
| --- | --- | --- | --- |
| `Project` | sim | — | Nome do projeto. |
| `AppEnv` | sim | — | Ambiente. |
| `RootPath` | sim | — | Pasta raiz do projeto console. |
| `OutPath` | sim | — | Pasta de saída do build. |
| `FtpPath` | sim | — | Caminho de destino no SFTP. |
| `DotNetVersion` | não | `10.0.x` | Versão do .NET. |
| `Configuration` | não | `Release` | `Debug` ou `Release`. |

Secret: `FTP_CREDENTIALS`.

Este workflow espera a estrutura do app de sincronização: `src/SyncDataApp/Properties/Config/` com os scripts `upload*.ps1`, `Atualizar.bat`, `Executar.bat`, `RunSetup.bat`, `RunUpdate.bat`, `<Project>*.xml` e `template*.json`.

## Infraestrutura (`infra/main.tf`)

Recursos criados por ambiente:

- Resource Group (East US)
- Storage Account + container privado (usados pela Function Flex Consumption)
- Log Analytics Workspace (30 dias, cota diária de 0,025 GB) e Application Insights
- Service Plan `FC1` (Linux) e Function App Flex Consumption `dotnet-isolated`, com CORS liberado, a connection string informada e `APPLICATIONINSIGHTS_CONNECTION_STRING`
- Static Web App do webapp e, em `PRD` — ou quando `CreateResourceLP` for `true` —, o Static Web App da landing page; ambos no plano definido por `StaticWebAppSku` (`Free` por padrão)
- Opcionalmente (`CreateResourceACS = true`): Communication Service, Email Communication Service, domínio gerenciado do Azure e respectiva associação; quando `CustomDomain` tem ao menos 4 caracteres, também o domínio próprio e o remetente `noreply`

Outputs:

- `acs_managed_sender_domain` — domínio gerenciado; o remetente de teste é `DoNotReply@<valor>`.
- `acs_custom_domain_dns_records` — registros TXT/SPF/DKIM a publicar no DNS para verificar o domínio próprio.

### Domínio próprio de e-mail, em duas etapas

1. Rode com `CreateResourceACS: true` e `CustomDomain: seudominio.com.br`. O domínio é criado, mas ainda não vinculado.
2. Publique no DNS os registros do output `acs_custom_domain_dns_records` e verifique o domínio no portal do Azure.
3. Rode de novo com `CustomDomainVerified: true` para criar o vínculo domínio↔ACS. Fazer isso antes da verificação faz o apply falhar.

### State do Terraform

O state fica em um container de Storage Account, configurado no `terraform init -backend-config` (os valores no bloco `backend` do `main.tf` são apenas placeholders). Para criar a estrutura uma única vez:

```bash
az group             create --name RG-Terraform-State                                    --location eastus
az storage account   create --name tf2gha4strategile --resource-group RG-Terraform-State --location eastus --sku Standard_LRS
az storage container create --name terraform-state   --account-name   tf2gha4strategile
```

Depois passe `TF_ResourceGroupName`, `TF_StorageAccountName` e `TF_ContainerName` na chamada do workflow, caso os nomes sejam diferentes dos defaults.

## Secrets

### `AZURE_CREDENTIALS`

JSON com as credenciais do service principal. Gere com:

```bash
az ad sp create-for-rbac --name "github-actions" --role contributor --scopes /subscriptions/<subscriptionId>
```

O Azure devolve `appId`, `password` e `tenant`; converta para o formato esperado pela action `azure/login`:

```json
{
  "clientId": "<appId>",
  "clientSecret": "<password>",
  "subscriptionId": "<subscriptionId>",
  "tenantId": "<tenant>"
}
```

### `ConnectionStringValue`

Connection string do banco, gravada na Function App com o nome e o tipo informados nos inputs.

### `FTP_CREDENTIALS`

Senha do SFTP usada pelo workflow do app console.

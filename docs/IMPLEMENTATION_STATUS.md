---
post_title: Home Scatolo implementation status
author1: Marco Dodaro
post_slug: home-scatolo-implementation-status
microsoft_alias: not-applicable
featured_image: ''
categories:
  - documentation
tags:
  - flutter
  - azure
  - github-actions
ai_note: Assisted documentation based on verified repository and Azure state.
summary: Technical handoff for the Home Scatolo implementation, deployments, and Azure AI Foundry migration.
post_date: 2026-08-25
---

<!-- markdownlint-disable MD041 -->

## Purpose

This document records the verified implementation state, decisions, deployment
history, and remaining work for Home Scatolo. It is an operational handoff, not
a product roadmap.

## Product And Application State

Home Scatolo is a Flutter PWA for creating a local-first household inventory
from photos of objects and containers. The client uses SQLite-compatible local
storage on supported platforms; photos are used for recognition but are not
persisted by the application.

Implemented user flows include:

- Hierarchy: house, room, container, item.
- Direct scan without setup. The app creates or reuses `La mia casa`,
  `Ingresso`, and `Da ordinare`.
- Camera capture and mobile gallery selection through `image_picker`.
- A 5 MB image size limit and JPEG, PNG, or WebP validation.
- AI candidate review before saving.
- Item quantity persistence and SQLite migration to schema version 2.
- Container-local duplicate decisions: add, merge quantity, review, or ignore.
- Inventory search and category filtering based on stored items.
- A recognition readiness state in the scan screen: preparing, ready, or
  unavailable with retry.

The readiness check calls `GET /health` once when the scan screen opens. It is
designed for a scale-to-zero backend and does not send periodic keep-alive
traffic.

## Verified Quality Checks

The following checks have passed during this work:

```text
flutter analyze
flutter test
npm run build
npm test
az bicep build --file infra/main.bicep
docker build and GET /health for the backend image
```

The Flutter suite most recently passed 25 tests. The backend most recently
passed 6 tests, including Azure Foundry request construction.

## Current Public Frontend

The PWA is published from the `gh-pages` branch through GitHub Actions:

- Public URL: <https://raythekool.github.io/home-scatolo/>
- Workflow: [deploy-pwa.yml](../.github/workflows/deploy-pwa.yml)
- Required build base href: `/home-scatolo/`
- Backend URL is compiled into Flutter with `--dart-define=API_BASE_URL=...`.

`API_BASE_URL` must be defined as a GitHub Actions variable before deploying
the production PWA. The workflow intentionally fails if it is missing instead
of publishing a build that points to `localhost`.

## Backend And Security Decisions

The PWA must not call a hosted AI provider directly with a secret key. Its
compiled JavaScript is publicly downloadable from GitHub Pages, so any token
embedded in it would be recoverable.

The backend remains a stateless Node.js and Express proxy with these routes:

- `GET /health`
- `POST /recognize`

The backend validates input and returns generic `502` responses for inference
failures. It must not log Base64 image contents, authorization headers, or
credentials.

GitHub Models was used during local development. The active migration target is
Azure AI Foundry backed by Azure OpenAI. The backend now uses
`DefaultAzureCredential`, which resolves to Azure Managed Identity in Container
Apps and can use Azure CLI credentials during local development.

Relevant implementation files:

- [server.ts](../backend/src/server.ts)
- [foundry_client.ts](../backend/src/foundry_client.ts)
- [recognition.ts](../backend/src/recognition.ts)
- [api_client.dart](../app/lib/services/api_client.dart)

## Hosting Evaluation

The following options were evaluated:

| Option                                     | Decision                                                                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Direct AI calls from PWA                   | Rejected. It exposes the provider credential.                                                                                        |
| Render Free                                | Prepared as a temporary option, but not selected as the long-term target because it sleeps after idle time.                          |
| Cloudflare Workers Free                    | Not selected for image Base64 inference proxy because its 10 ms CPU limit is too narrow for reliable multi-megabyte request parsing. |
| Azure Container Apps plus Azure AI Foundry | Selected. It preserves the Express API, supports Managed Identity, and can scale to zero.                                            |
| Azure Static Web Apps                      | Deferred. GitHub Pages remains the frontend host during the first Azure migration phase.                                             |

The Render blueprint remains in [render.yaml](../render.yaml) as fallback until
the Azure end-to-end flow is confirmed. Do not remove it before that point.

## Azure Authentication

Azure CLI and Bicep were installed locally in the user profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
az login
az account set --subscription 86f540da-a00e-4607-add0-523cd0750da0
```

The selected target is:

```text
Subscription: Visual Studio Enterprise Subscription
Subscription ID: 86f540da-a00e-4607-add0-523cd0750da0
Tenant: Avanade
Primary region: Italy North
Fallback region: West Europe
```

Do not commit Azure access tokens, Foundry API keys, GitHub Models tokens, or
service-principal secrets. The target CI/CD model is GitHub Actions OIDC with a
federated Microsoft Entra application, not a long-lived Azure secret.

## Azure Resources Created

Resource group created successfully:

```text
rg-home-scatolo-prod
Italy North
```

The Azure foundation deployment succeeded on 2026-08-25. It created:

| Resource                   | Name                     | Purpose                                  |
| -------------------------- | ------------------------ | ---------------------------------------- |
| Container Registry         | `acrhomescatoloprod`     | Stores immutable backend images.         |
| Container Apps Environment | `cae-homescatoloprod`    | Hosts the public Express API.            |
| Managed Identity           | `id-homescatoloprod-api` | Authenticates the API to Azure services. |
| Log Analytics              | `log-homescatoloprod`    | API platform logs, 30-day retention.     |
| Azure OpenAI account       | `oai-homescatoloprod`    | Azure AI Foundry model endpoint.         |

The infrastructure template assigns the API identity:

- `AcrPull` on the container registry.
- `Cognitive Services OpenAI User` on the Azure OpenAI account.

The Azure OpenAI endpoint is:

```text
https://oai-homescatoloprod.openai.azure.com
```

The baseline infrastructure is defined in [main.bicep](../infra/main.bicep).
It deploys the model only when `deployModel=true`; this separates stable
infrastructure creation from region- and quota-dependent model provisioning.

## Azure Deployment Automation

[deploy-backend.yml](../.github/workflows/deploy-backend.yml) is prepared to:

1. Build and test the Node 22 backend.
2. Sign into Azure using GitHub OIDC.
3. Build and push an image tagged with the immutable Git commit SHA.
4. Create or update the Azure Container App.
5. Verify the deployed `/health` endpoint.

The workflow needs a protected GitHub environment named `production` and these
GitHub Actions variables:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_RESOURCE_GROUP=rg-home-scatolo-prod
AZURE_CONTAINER_REGISTRY=acrhomescatoloprod
AZURE_CONTAINER_APP_NAME=home-scatolo-api
AZURE_CONTAINER_APPS_ENVIRONMENT_ID=<Bicep output>
AZURE_CONTAINER_APP_IDENTITY_ID=<Bicep output>
AZURE_OPENAI_ENDPOINT=https://oai-homescatoloprod.openai.azure.com
AZURE_OPENAI_DEPLOYMENT=home-scatolo-vision
```

`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are not
secrets. They identify the OIDC workload identity. Azure credentials and model
access are granted through Entra federation and Managed Identity.

## Current Azure Blocker

No model deployment exists yet. The Italy North catalog query did not return a
usable GPT-4o version for this subscription, and a later catalog request was
interrupted by an Azure network connection reset.

Do not invent a model version. Before setting `deployModel=true`, verify in
Azure AI Foundry that a vision-capable model, exact version, quota, and SKU are
available. If Italy North does not offer a suitable deployment, create a
separate Azure OpenAI or Foundry resource in West Europe and update the backend
endpoint variable accordingly.

## Remaining Steps

1. Confirm a vision-capable model deployment in Azure AI Foundry, including
   exact name, version, region, capacity, and deployment name.
2. Deploy that model using [main.bicep](../infra/main.bicep) with
   `deployModel=true`, or create it through Foundry and keep the deployment
   name `home-scatolo-vision`.
3. Create the Microsoft Entra application and GitHub OIDC federated credential
   constrained to `repo:raythekool/home-scatolo:environment:production`.
4. Assign the OIDC application enough deployment permissions, normally
   Contributor on `rg-home-scatolo-prod` and AcrPush on
   `acrhomescatoloprod`.
5. Configure the GitHub Actions variables listed above.
6. Run `Deploy Backend`, then verify:

   ```bash
   curl https://<container-app-fqdn>/health
   ```

7. Set GitHub Actions variable `API_BASE_URL` to the Container App HTTPS URL.
8. Run `Deploy PWA` and exercise a real recognition request from GitHub Pages.
9. Retire Render only after the Azure API, CORS, Foundry response parsing, and
   PWA readiness states are verified end-to-end.

## Recent Implementation Commits

| Commit    | Summary                                                                                                        |
| --------- | -------------------------------------------------------------------------------------------------------------- |
| `cb3c6e6` | AI-assisted inventory scanning, duplicate handling, gallery support, quick scan defaults, and UI improvements. |
| `2d542af` | PWA build requires a configured production API URL.                                                            |
| `14a9a2e` | Recognition backend readiness state in the Flutter scan flow.                                                  |
| `f31ccf4` | Azure Foundry backend, Docker image, Bicep template, and OIDC workflow foundation.                             |
| `76939db` | Defers model deployment until model quota/version is verified.                                                 |
| `ff6b673` | Uses supported 30-day Log Analytics retention.                                                                 |

## Scope Not Yet Implemented

- Azure Static Web Apps migration.
- User authentication and multi-user synchronization.
- Cloud database and persistent server-side inventory.
- Blob Storage for source photos.
- Custom domain, WAF, rate limiting, and comprehensive telemetry.
- Automated model evaluation, prompt versioning workflow, and usage budgets.

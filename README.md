# Receipt Scanner on Azure Container Apps

Upload a photo of a receipt and get back structured data: merchant, date, line items, and total.

This is an event-driven app on **Azure Container Apps**, with infrastructure in **Terraform** and CI/CD in **GitHub Actions**. Uploads are queued on Service Bus, and a KEDA-scaled **Container Apps Job** processes them with **Azure AI Document Intelligence**. The project runs across **dev, staging, and prod**, uses **managed identity** for all app traffic, and **OIDC** for every pipeline login, with no stored secrets.

---

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full diagrams, the request flow, the identity model, and the design decisions.

```
Client ──► API (Container App) ──► Blob Storage   (receipt image)
                │            └───► Cosmos DB      (status: pending)
                ▼
         Service Bus queue ──► Worker (Container Apps Job, scaled 0 → N by KEDA)
                                  ├─► Document Intelligence (prebuilt-receipt)
                                  └─► Cosmos DB (status: completed + extracted data)
```

---

## Features

| Area                   | What it shows                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Event-driven scaling   | Worker runs as a Container Apps Job, scaled from zero by KEDA on queue length                                                  |
| Async API              | Upload returns `202 Accepted` immediately; client polls for the result                                                         |
| Identity               | User-assigned managed identities with least-privilege RBAC; key auth disabled on Storage, Cosmos DB, and Document Intelligence |
| Multi-environment      | dev, staging, and prod with separate resource groups, state, and pipeline identities                                           |
| Infrastructure as Code | Terraform with remote state in Entra-only storage, plan posted on every PR                                                     |
| CI/CD                  | Build once, promote the same image dev → staging → prod, with approval gates                                                   |
| Pipeline security      | GitHub Actions OIDC (no secrets), SHA-pinned actions, per-environment identities                                               |
| Supply chain           | Dependabot, CodeQL, Gitleaks, ESLint, tflint, hadolint                                                                         |
| Resilience             | Retries for transient errors, immediate dead-lettering for permanent ones, rate-limited uploads                                |
| Local dev              | Full stack in Docker Compose against Azure emulators; no Azure account needed                                                  |

---

## Tech Stack

| Layer                  | Technology                                                            |
| ---------------------- | --------------------------------------------------------------------- |
| Compute                | Azure Container Apps (API) + Container Apps Jobs (worker)             |
| Scaling                | KEDA (Service Bus queue scaler, HTTP concurrency)                     |
| Messaging              | Azure Service Bus (Basic)                                             |
| Database               | Azure Cosmos DB for NoSQL (free tier in dev, serverless elsewhere)    |
| Object storage         | Azure Blob Storage                                                    |
| AI                     | Azure AI Document Intelligence, `prebuilt-receipt` model              |
| Container registry     | Azure Container Registry (shared, build once)                         |
| Observability          | Log Analytics workspace (per environment, with daily cap)             |
| Identity               | User-assigned managed identities, Entra ID RBAC                       |
| App                    | Node.js 22, TypeScript, Express 5                                     |
| Infrastructure as Code | Terraform >= 1.9, `azurerm` ~> 4.40                                   |
| CI/CD                  | GitHub Actions (OIDC, reusable workflows, environment approvals)      |
| Security scanning      | CodeQL, Gitleaks, Dependabot, GitHub secret scanning                  |
| Linting                | ESLint (typescript-eslint), tflint (azurerm ruleset), hadolint        |
| Local dev              | Docker Compose with Azurite, Cosmos DB emulator, Service Bus emulator |

---

## Environments

|                       | dev                | staging               | prod               |
| --------------------- | ------------------ | --------------------- | ------------------ |
| Resource group        | `rg-rcptscan-dev`  | `rg-rcptscan-staging` | `rg-rcptscan-prod` |
| Cosmos DB             | Free tier          | Serverless            | Serverless         |
| Document Intelligence | F0 (free)          | S0 (pay per page)     | S0 (pay per page)  |
| API min replicas      | 0 (scale to zero)  | 0                     | 1 (no cold starts) |
| Deploys               | Automatic on merge | Manual approval       | Manual approval    |
| Terraform state       | `tfstate-dev`      | `tfstate-staging`     | `tfstate-prod`     |

Shared across environments: `rg-rcptscan-shared` (container registry) and `rg-rcptscan-tfstate` (state storage).

---

## Repository Structure

```
azure-container-app-receipt-scanner/
├── app/
│   ├── api/                        # Upload + status API (Express)
│   │   ├── src/
│   │   │   ├── index.ts            # Routes, rate limiting, local init
│   │   │   ├── clients.ts          # Azure clients: emulator conn strings locally, managed identity in Azure
│   │   │   ├── config.ts
│   │   │   └── types.ts
│   │   ├── Dockerfile
│   │   ├── eslint.config.mjs
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── worker/                     # Queue consumer (Container Apps Job)
│       ├── src/
│       │   ├── index.ts            # Receive → extract → update; retry vs dead-letter
│       │   ├── extractor.ts        # Document Intelligence + mock extractor
│       │   ├── clients.ts
│       │   ├── config.ts
│       │   └── types.ts
│       ├── Dockerfile
│       ├── eslint.config.mjs
│       ├── package.json
│       └── tsconfig.json
├── infra/
│   ├── .tflint.hcl
│   ├── bootstrap/                  # Run once, locally: state storage, ACR, RGs, OIDC identities
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── app/                        # One root module for every environment
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf                 # Naming, lookups, Log Analytics, identities
│       ├── data.tf                 # Storage, Service Bus, Cosmos DB
│       ├── ai.tf                   # Document Intelligence
│       ├── rbac.tf                 # Role assignments
│       ├── containerapps.tf        # Environment, API app, worker job
│       ├── outputs.tf
│       └── envs/
│           ├── dev.tfvars          dev.backend.hcl
│           ├── staging.tfvars      staging.backend.hcl
│           └── prod.tfvars         prod.backend.hcl
├── servicebus/
│   └── config.json                 # Service Bus emulator queue definition
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── app-ci.yml              # PR: lint, build, docker build
│       ├── terraform-plan.yml      # PR: plan against dev, posted as a comment
│       ├── lint.yml                # PR: terraform fmt, tflint, hadolint
│       ├── gitleaks.yml            # PR + main: secret scanning (full history)
│       ├── codeql.yml              # PR + main + weekly: code scanning
│       ├── deploy.yml              # main: build once → dev → staging → prod
│       ├── _deploy-env.yml         # Reusable: plan/apply + deploy images + smoke test
│       └── promote.yml             # Manual: promote a build to an environment
├── docker-compose.yml
├── .env.example
├── .gitleaks.toml
├── ARCHITECTURE.md
└── README.md
```

---

## Prerequisites

- Docker Desktop
- Node.js 22+
- Azure CLI
- Terraform >= 1.9
- GitHub CLI (`gh`)
- An Azure subscription where you are **Owner** (needed once, for the bootstrap)
- Git Bash (Windows) or any bash shell

---

## Step-by-Step Setup Guide

### Phase 1: Run locally with Docker Compose

The whole stack runs on your machine against Azure emulators. No Azure account is needed for this phase.

1. Copy the env template and fill it in:

   ```bash
   cp .env.example .env
   ```

   `.env` holds the emulator connection strings and keys. These are public, well-known values from Microsoft's docs, but they're kept out of the repo so no key-shaped strings get committed. Links to the values are in `.env.example`.

2. Generate the lockfiles (the Dockerfiles use `npm ci`):

   ```bash
   (cd app/api && npm install)
   (cd app/worker && npm install)
   ```

3. Start everything:

   ```bash
   docker compose up --build
   ```

   The first start takes a minute or two while the emulators boot. Wait for `API listening on :3000`.

4. Test it from a second terminal:
   ```bash
   curl http://localhost:3000/healthz
   curl -F "file=@receipt.jpg;type=image/jpeg" http://localhost:3000/receipts
   curl -s http://localhost:3000/receipts/<id> | python -m json.tool
   ```
   Locally, the worker uses a **mock extractor** that always returns the same fake receipt. Set `EXTRACTOR=azure` plus the Document Intelligence endpoint and key in `.env` to use the real service.

> **Windows PowerShell:** use `curl.exe`, not `curl`. In PowerShell, plain `curl` is an alias for `Invoke-WebRequest`.

### Phase 2: Prepare Azure

```bash
az login
az account show --query "{name:name, id:id}" -o table

# Register the resource providers the project uses (one-time)
for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry \
          Microsoft.DocumentDB Microsoft.ServiceBus Microsoft.CognitiveServices Microsoft.Storage; do
  az provider register --namespace $ns
done
```

The pipeline identities only have access to their own resource groups, so they can't register providers. That's why this is done once here, and why `infra/app` sets `resource_provider_registrations = "none"`.

### Phase 3: Terraform bootstrap (run once, locally)

The bootstrap creates what everything else depends on:

- State storage account (Entra ID auth only, versioning on) with one container per environment
- Shared container registry (`rg-rcptscan-shared`)
- One resource group per environment
- One Entra app registration per environment, with OIDC federated credentials for GitHub
- Role assignments scoped to each environment

1. Set `infra/bootstrap/terraform.tfvars`:

   ```hcl
   subscription_id = "<your-subscription-id>"
   github_repo     = "<github-user>/azure-container-app-receipt-scanner"   # must match exactly, case included
   ```

2. Apply:

   ```bash
   cd infra/bootstrap
   terraform init
   terraform plan -out tfplan
   terraform apply tfplan
   ```

3. Grab the values GitHub needs (they're IDs, not secrets):
   ```bash
   terraform output github_repo_variables
   terraform output -json github_environment_variables | python -m json.tool
   ```

> The bootstrap keeps its state **locally** on purpose, because it creates the remote state storage. It's gitignored. If it's ever lost, nothing in Azure breaks; you'd re-import the resources with `terraform import`.

### Phase 4: GitHub setup

1. **Create the environments:**

   ```bash
   for env in dev staging prod; do
     gh api -X PUT "repos/{owner}/{repo}/environments/$env"
   done
   ```

2. **Add approval gates.** In **Settings → Environments**, open **staging** and **prod** and add yourself under **Required reviewers**. Untick **Prevent self-review**.

3. **Repository variables** (from `github_repo_variables`):

   ```bash
   gh variable set AZURE_TENANT_ID         --body "<value>"
   gh variable set AZURE_SUBSCRIPTION_ID   --body "<value>"
   gh variable set TFSTATE_RESOURCE_GROUP  --body "<value>"
   gh variable set TFSTATE_STORAGE_ACCOUNT --body "<value>"
   gh variable set ACR_NAME                --body "<value>"
   gh variable set ACR_LOGIN_SERVER        --body "<value>"

   # The PR plan job runs without an environment, so it needs dev's client ID at repo level
   gh variable set AZURE_CLIENT_ID_DEV     --body "<dev AZURE_CLIENT_ID>"
   ```

4. **Environment variables** (from `github_environment_variables`, repeated for each environment):

   ```bash
   gh variable set AZURE_CLIENT_ID   --env dev --body "<dev client id>"
   gh variable set TFSTATE_CONTAINER --env dev --body "tfstate-dev"
   gh variable set RESOURCE_GROUP    --env dev --body "rg-rcptscan-dev"
   ```

5. **Security settings.** In **Settings → Advanced Security**, turn on Dependabot alerts, Dependabot security updates, secret scanning, and push protection. Keep CodeQL **Default setup off**, because the repo uses its own `codeql.yml`.

6. **Branch protection on `main`:** require a pull request. `lint`, `gitleaks`, and `codeql` run on every PR, so they're safe to make **required checks**. `app-ci` and `terraform-plan` only run when their paths change, so leave them optional.

### Phase 5: Push the first images

Terraform creates the Container App and Job pointing at a `bootstrap` image tag, so that tag has to exist first:

```bash
ACR=<ACR_NAME>
az acr login --name $ACR

docker build -t $ACR.azurecr.io/receipt-api:bootstrap app/api
docker build -t $ACR.azurecr.io/receipt-worker:bootstrap app/worker
docker push $ACR.azurecr.io/receipt-api:bootstrap
docker push $ACR.azurecr.io/receipt-worker:bootstrap
```

> Use `docker build`, not `az acr build`. ACR Tasks are often blocked on free-credit subscriptions.

### Phase 6: Deploy the dev infrastructure

1. Fill in `infra/app/envs/dev.tfvars` and `dev.backend.hcl` (subscription ID, ACR name, state storage account). Do the same for staging and prod now, so the pipeline can create them later.

2. Apply dev:
   ```bash
   cd infra/app
   terraform init -backend-config=envs/dev.backend.hcl
   terraform plan -var-file=envs/dev.tfvars -out tfplan
   terraform apply tfplan
   terraform output api_url
   ```
   The first apply takes about 5–10 minutes, mostly Cosmos DB and the Container Apps environment.

> **Switching environments locally:** always use `terraform init -reconfigure -backend-config=envs/<env>.backend.hcl`. If Terraform asks to _copy existing state to the new backend_, answer **no**. Saying yes copies one environment's state into another's.

Only dev is applied by hand. Staging and prod are created by the pipeline on its first run, which also proves the pipeline can build an environment from nothing.

### Phase 7: Test in Azure

```bash
API=$(terraform output -raw api_url)

curl $API/healthz
curl -F "file=@real-receipt.jpg;type=image/jpeg" $API/receipts
curl -s $API/receipts/<id> | python -m json.tool
```

- Expect about **30–60 seconds** from upload to `completed`. Dev scales to zero, KEDA polls the queue every 30 seconds, and the job container starts cold.
- A photo that isn't a receipt ends as `failed` after a **single** Document Intelligence call, dead-lettered with reason `NotAReceipt`.
- Watch job runs: open the job in the portal, then **Execution history**.

### Phase 8: CI/CD

From here on, every change goes through a pull request:

```bash
git checkout -b feat/my-change
# ...make changes...
git push -u origin feat/my-change
gh pr create --base main
```

**On the PR:** the checks run, and `terraform-plan` posts the dev plan as a comment. Read the plan, then merge.

**On merge:** `deploy.yml` builds the images once, tagged with the commit SHA, and then:

1. **Dev** deploys automatically: Terraform plan/apply, image update, smoke test.
2. **Staging** waits for approval: **Actions → the run → Review deployments → Approve**.
3. **Prod** waits for approval the same way.

The first staging and prod deploys create those environments from scratch, which takes about 10–15 minutes each.

### Phase 9: Security and quality tooling

| Tool                     | Config                         | Runs                                               |
| ------------------------ | ------------------------------ | -------------------------------------------------- |
| Dependabot               | `.github/dependabot.yml`       | Weekly PRs for npm, Docker, Terraform, and Actions |
| ESLint                   | `app/*/eslint.config.mjs`      | `app-ci` on PRs; locally with `npm run lint`       |
| tflint + `terraform fmt` | `infra/.tflint.hcl`            | `lint` on every PR                                 |
| hadolint                 | (defaults)                     | `lint` on every PR                                 |
| Gitleaks                 | `.gitleaks.toml`               | Every PR and push to `main`, full history          |
| CodeQL                   | `.github/workflows/codeql.yml` | Every PR, push to `main`, and weekly               |

All third-party actions are **pinned to commit SHAs**. To pin a newly added action:

```bash
gh api repos/<owner>/<action-repo>/commits/<tag> -q .sha
# then: uses: owner/action@<sha> # <tag>
```

Currently pinned third-party actions. Open the release page and click the short commit hash next to the tag to see the full SHA:

| Action                           | Version | Release page                                                                       | Pinned commit                                                                                                          |
| -------------------------------- | ------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `gitleaks/gitleaks-action`       | v2.3.9  | [release](https://github.com/gitleaks/gitleaks-action/releases/tag/v2.3.9)         | [`ff98106`](https://github.com/gitleaks/gitleaks-action/commit/ff98106e4c7b2bc287b24eaf42907196329070c7)               |
| `hashicorp/setup-terraform`      | v3.1.2  | [release](https://github.com/hashicorp/setup-terraform/releases/tag/v3.1.2)        | [`b9cd54a`](https://github.com/hashicorp/setup-terraform/commit/b9cd54a3c349d3f38e8881555d616ced269862dd)              |
| `azure/login`                    | v2.3.1  | [release](https://github.com/Azure/login/releases/tag/v2.3.1)                      | [`7184910`](https://github.com/Azure/login/commit/7184910d9eb2b1c5e48f7073824a90609bb9b6d6)                            |
| `terraform-linters/setup-tflint` | v4.1.1  | [release](https://github.com/terraform-linters/setup-tflint/releases/tag/v4.1.1)   | [`90f302c`](https://github.com/terraform-linters/setup-tflint/commit/90f302c255ef959cbfb4bd10581afecdb7ece3e6)         |
| `hadolint/hadolint-action`       | v3.5.0  | [release](https://github.com/hadolint/hadolint-action/releases/tag/v3.5.0)         | [`06be81b`](https://github.com/hadolint/hadolint-action/commit/06be81baf89a55ffd0e24b8f04a4185738dd3387)               |

Dependabot bumps these pins (SHA and `# vX.Y.Z` comment) through its weekly `github-actions` PR. When it does, update this table to match.

> **Gitleaks allowlist:** the emulator keys now live in `.env`, but they still exist in early commits. Gitleaks scans the full history, so `.gitleaks.toml` allowlists those exact public values, and only those.

---

## API Endpoints

| Method | Path            | Description                                                                                                                                                    |
| ------ | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET`  | `/healthz`      | Health check (liveness/readiness probes, smoke test)                                                                                                           |
| `POST` | `/receipts`     | Upload a receipt (`multipart/form-data`, field `file`; jpeg, png, bmp, tiff, heif, or pdf; max 10 MB). Returns `202` with the new record. Rate limited per IP. |
| `GET`  | `/receipts/:id` | Get one receipt's status and extracted data                                                                                                                    |
| `GET`  | `/receipts`     | List the 50 most recent receipts                                                                                                                               |

Receipt status values: `pending` → `processing` → `completed` or `failed`.

Example result:

```json
{
  "id": "41bc4eb1-b986-4f1b-ae7e-4710bd8d2ef5",
  "status": "completed",
  "result": {
    "merchantName": "SHOP NAME",
    "total": 16.5,
    "currency": "USD",
    "items": [
      { "description": "Lorem", "totalPrice": 1.1 },
      { "description": "Ipsum", "totalPrice": 2.2 }
    ],
    "confidence": 0.954
  }
}
```

---

## CI/CD Pipeline

All Azure logins use **OIDC**: GitHub proves "this repo, in this environment," and Entra ID returns a short-lived token. No client secrets exist anywhere.

```
Pull request
  ├─ app-ci          lint + build + docker build (api, worker)
  ├─ terraform-plan  plan vs dev → PR comment          (skipped for Dependabot: no OIDC)
  ├─ lint            terraform fmt + tflint + hadolint
  ├─ gitleaks        secrets in full git history
  └─ codeql          TypeScript + workflow files

Merge to main
  └─ build           docker build once, tag = commit SHA, push to ACR (dev identity)
       └─ dev        terraform plan/apply → az containerapp update → smoke test
            └─ staging   ⏸ approval → same steps (staging identity)
                 └─ prod  ⏸ approval → same steps (prod identity)
```

Each environment job takes a **per-environment concurrency lock**, so a run waiting at staging approval doesn't block new merges from reaching dev.

**Rollback:** redeploy an earlier image by its commit SHA, either by re-running an older successful run or directly:

```bash
az containerapp update -n <api-app> -g rg-rcptscan-<env> --image <acr>.azurecr.io/receipt-api:<old-sha>
az containerapp job update -n <worker-job> -g rg-rcptscan-<env> --image <acr>.azurecr.io/receipt-worker:<old-sha>
```

---

## Troubleshooting

### `bash: syntax error near unexpected token 'newline'`

You pasted a placeholder like `<id>` literally. Bash reads `<` and `>` as redirects. Replace it with the real value.

### `npm ci` fails during `docker build`

A `package-lock.json` is missing. Run `npm install` in that app folder and commit the lockfile.

### Receipt stuck on `processing`

The worker crashed partway through. Check the job runs and logs:

```bash
az containerapp job execution list -n <worker-job> -g rg-rcptscan-<env> -o table
```

```kusto
ContainerAppConsoleLogs_CL
| where ContainerJobName_s == "<worker-job>"
| where TimeGenerated > ago(30m)
| project TimeGenerated, Log_s
| order by TimeGenerated asc
```

### Receipt `failed` with "No receipt detected"

Expected for images that aren't receipts. It's dead-lettered immediately with reason `NotAReceipt`. Check the dead-letter count:

```bash
az servicebus queue show -g rg-rcptscan-<env> --namespace-name <sb-name> -n receipts --query countDetails
```

### Image pull or `unauthorized` errors on the first apply

New role assignments (AcrPull) can take a few minutes to take effect. Wait, then run `terraform plan` and `apply` again.

### `No matching federated identity record found` (OIDC)

The workflow's OIDC subject doesn't match a federated credential:

- `github_repo` in the bootstrap must match the repo name **exactly**, case included.
- Deploy jobs must declare `environment: <env>` with an environment name that matches.
- The PR plan job must use **dev's** client ID (`AZURE_CLIENT_ID_DEV`); only the dev identity accepts `pull_request`.

### CI fails registering resource providers

`infra/app/versions.tf` must set `resource_provider_registrations = "none"`. CI identities are scoped to resource groups and can't register providers at the subscription level.

### Terraform state lock stuck

A run was interrupted mid-apply. Make sure no other run is active, then:

```bash
terraform force-unlock <lock-id>
```

### Deploy run sitting at staging or prod

It's waiting for approval: **Actions → run → Review deployments**. Reject stale runs if a newer one supersedes them.

### `terraform-plan` didn't run on a Dependabot PR

Expected. Dependabot runs get a read-only token, so OIDC isn't possible and the job is skipped. Provider bumps are planned and applied in dev after merge.

### `429 Too Many Uploads`

The per-IP upload rate limit was hit. Wait a minute, or raise `UPLOAD_RATE_LIMIT_PER_MIN`.

---

## Cost Estimate

Approximate monthly cost at **demo-level traffic**, in USD. Check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for current rates.

| Service                            | dev                                    | staging + prod                         |
| ---------------------------------- | -------------------------------------- | -------------------------------------- |
| Container Apps (API + Job)         | ~$0 (scale to zero, within free grant) | ~$0–15 (prod keeps 1 warm API replica) |
| Cosmos DB                          | $0 (free tier)                         | Cents (serverless)                     |
| Document Intelligence              | $0 (F0)                                | Per page (S0)                          |
| Service Bus (Basic)                | Cents                                  | Cents                                  |
| Blob Storage                       | Cents                                  | Cents                                  |
| Log Analytics                      | Small (0.5 GB/day cap)                 | Small (0.5 GB/day cap)                 |
| Container Registry (Basic, shared) | ~$5                                    | —                                      |
| **Total**                          |                                        | **roughly $5–25/month**                |

> **Tips:** set prod's `api_min_replicas = 0` to stop paying for the warm replica when you're not demoing. The daily Log Analytics cap stops a noisy bug from running up a logging bill.

---

## Future Improvements

- Azure Monitor alerts (DLQ growth, API 5xx, failed job runs) and a runbook
- Ops workflows: rollback, DLQ resubmit, break state lock
- Managed-identity auth for the KEDA scale rule
- Read-only plan identity so prod's plan is reviewed before approval
- Private networking (VNet integration + private endpoints)
- Upload frontend, behind authentication

---

## References

- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/overview)
- [Container Apps Jobs (event-driven)](https://learn.microsoft.com/azure/container-apps/jobs)
- [KEDA Azure Service Bus scaler](https://keda.sh/docs/latest/scalers/azure-service-bus/)
- [Document Intelligence receipt model](https://learn.microsoft.com/azure/ai-services/document-intelligence/prebuilt/receipt)
- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
- [Terraform azurerm backend](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Using environments for deployment (GitHub)](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Security hardening for GitHub Actions](https://docs.github.com/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)

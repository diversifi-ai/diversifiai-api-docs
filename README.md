# Diversifi API Docs

This repository contains configuration and automation to publish the **Dev API documentation** to [Scalar](https://scalar.com).

## Requirements

- Node.js (>= 20)
- Scalar CLI  
  Install globally:
  ```bash
  npm install -g @scalar/cli
  ```
- `jq` and `curl` available in your system
- A valid **Scalar API token**

## Setup

1. Save your Scalar API token as an environment variable:

   ```bash
   export SCALAR_TOKEN="your_api_key_here"
   ```

2. Make sure the script is executable:

   ```bash
   chmod +x scripts/publish-scalar-dev.sh
   ```

## Usage

Run the script to validate the OpenAPI spec and publish a new version:

```bash
./scripts/publish-scalar-dev.sh
```

The script will:

1. Validate the OpenAPI document from  
   [`https://dev.diversifi.ai/api_v1/openapi.json`](https://dev.diversifi.ai/api_v1/openapi.json)  
2. Generate a valid semver version (either from the spec or time-based)  
3. Automatically increment the version if the current one already exists  
4. Publish to Scalar under the namespace/slug:  
   ```
   diversifi-0qxwn/dev
   ```

## Output

After a successful run, you’ll see:

```
Published version: vX.Y.Z
URL: https://scalar.com/registry/diversifi-0qxwn/dev
```

## GitHub Actions

Publishing is also automated for the `dev-api-docs` branch using  
[`.github/workflows/publish-scalar.yml`](.github/workflows/publish-scalar.yml).  
The workflow installs dependencies and executes the same script automatically on every push.

Make sure you set the **secret** `SCALAR_TOKEN` in your repository settings:

```
Settings → Secrets and variables → Actions → New repository secret
```

Name: `SCALAR_TOKEN`  
Value: your Scalar API key


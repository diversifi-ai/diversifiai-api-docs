# API Docs Runbook

## Dev

1. The backend pipeline creates `openapi.json`.
2. The pipeline uploads it to `docs-api-dev-diversifi-ai`.
3. CloudFront serves it at `https://dev-docs-openapi.diversifi.ai/openapi.json`.
4. Scalar runs in Kubernetes at `https://dev-docs.diversifi.ai`.
5. Scalar uses version `1.72.1`.

Check the dev site:

```bash
curl -I https://dev-docs.diversifi.ai
curl https://dev-docs-openapi.diversifi.ai/openapi.json
```

Do not change the backend pods for a docs update.

## Production

1. Create a compatible OpenAPI file.
2. Upload it to `docs-api-diversifi-ai/openapi.json`.
3. Use Scalar version `1.72.1` in `index.html`.
4. Invalidate `/index.html` and `/openapi.json` in CloudFront.

Check the production site:

```bash
curl -I https://docs.diversifi.ai
curl https://docs.diversifi.ai/openapi.json
```

## Rollback

1. Copy the backup OpenAPI file back to `openapi.json`.
2. Copy the backup `index.html` back to `index.html`.
3. Invalidate both CloudFront paths.

# backend/ — Proxy AI

Funzione serverless che fa da proxy sicuro verso GitHub Models, così il token non viene mai esposto al client Flutter.

## Variabili d'ambiente

- `GITHUB_MODELS_TOKEN` — Personal Access Token con scope `models: read`
- `MODEL_NAME` — es. `gpt-4o` (default consigliato per riconoscimento vision)

## Endpoint previsto

`POST /recognize` — riceve `{ "image_base64": "..." }`, restituisce `{ "items": [{ "nome", "categoria", "descrizione_breve" }] }`

# Project Guidelines

## Implementation Status

Keep [docs/IMPLEMENTATION_STATUS.md](../docs/IMPLEMENTATION_STATUS.md) current
whenever work changes the verified implementation state. Update it in the same
change when any of the following changes:

- Architecture, hosting, AI provider, deployment, or CI/CD decisions.
- Azure resources, identity roles, GitHub Actions variables, endpoints, or
  deployment status.
- User-visible capabilities, API contracts, security controls, test results,
  operational blockers, or resolved blockers.

Record only verified facts. Include commands and URLs only when they have been
validated, and never record credentials, tokens, authorization headers, image
payloads, or secret values. Keep the remaining steps and current blockers
accurate; remove entries once they are completed or no longer relevant.

## Documentation Quality

Use Italian for user-facing copy and Italian or clear technical English for
engineering documentation. Preserve the Markdown front matter and the
front-matter title convention used by `docs/IMPLEMENTATION_STATUS.md`.
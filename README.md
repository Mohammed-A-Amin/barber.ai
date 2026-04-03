# barber-ai

This repository is a fresh rebuild of the `barber-ai` project. The previous codebase has been preserved under `archive/`, and the active repository now starts from a clean monorepo foundation.

## Structure

```text
apps/
  api/       Fastify + TypeScript backend API
  worker/    TypeScript worker placeholder
ios/
  BarberAI/  SwiftUI iOS app skeleton
docs/
  DESIGN.md  Product and system design notes
archive/     Previous project code and assets
```

## Current Scope

- No product features yet
- API scaffold with `/health`
- Worker placeholder
- SwiftUI tab-based iOS shell

## Running

Install workspace dependencies from the repository root:

```bash
npm install
```

Run the API:

```bash
npm run dev:api
```

Run the worker:

```bash
npm run dev:worker
```

# Sotie Backend

Node.js backend for the Sotie iOS app. It handles anonymous sessions, AI requests, quota tracking, and StoreKit entitlement verification.

## Requirements

```text
Node.js 22+
npm
Redis
Docker, optional
```

## Setup

Install dependencies:

```bash
npm install
cp .env.example .env
```

Generate `SESSION_JWT_SECRET`:

```bash
openssl rand -base64 32
```

Edit `.env`:

```text
NODE_ENV=development
HOST=0.0.0.0
PORT=8080
REDIS_URL=redis://localhost:6379
SESSION_JWT_SECRET=<generated value>
OPENROUTER_API_KEY=<your OpenRouter API key>
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_SITE_URL=https://sotie.app
OPENROUTER_APP_NAME=Sotie
OPENROUTER_MODEL=google/gemini-3-flash-preview
OPENROUTER_FALLBACK_MODEL=moonshotai/kimi-k2-0905
APPLE_BUNDLE_ID=com.pvlppv.sotie.journal
APPLE_ENVIRONMENT=Sandbox
```

## Redis

Run with Docker:

```bash
docker compose up --build
```

Or run Redis locally and keep:

```text
REDIS_URL=redis://localhost:6379
```

## Development server

```bash
npm run dev
```

Default URL:

```text
http://127.0.0.1:8080
```

Health check:

```bash
curl http://127.0.0.1:8080/health
```

## API

```text
GET  /health
POST /v1/session
GET  /v1/me
POST /v1/entitlements/verify-transaction
POST /v1/ai/go-deeper/stream
POST /v1/ai/summarize
POST /v1/ai/insights
POST /v1/ai/repair-language
```

## StoreKit

For local development:

```text
APPLE_ENVIRONMENT=Sandbox
APPLE_BUNDLE_ID=<same bundle id as the iOS app>
```

If Apple root certificates are not configured, transaction verification fails closed with `storekit_unconfigured`.

## Commands

Tests:

```bash
npm test
```

Type check:

```bash
npm run typecheck
```

Build:

```bash
npm run build
```

Start compiled server:

```bash
npm start
```

# Sotie Coursework 2026

This repository is a coursework submission snapshot of the iOS app and backend source.

Sotie is an iOS journaling app with a Node.js backend. The iOS app stores journal data locally and uses the backend for AI-assisted reflection, anonymous sessions, quota tracking, and StoreKit entitlement verification.

## Requirements

iOS:

```text
Xcode 16+
iOS 18+ simulator
Apple ID for code signing
```

Backend:

```text
Node.js 22+
npm
Redis
Docker, optional
```

## iOS setup

Open the project:

```bash
open Sotie.xcodeproj
```

Use this scheme:

```text
Sotie (Debug)
```

The project contains the original bundle identifiers and signing settings. If Xcode builds on your machine without changes, no extra setup is required.

For a separate local setup, create a local Xcode config file:

```bash
cp Local.xcconfig.example Local.xcconfig
```

Edit `Local.xcconfig`:

```text
PRODUCT_BUNDLE_IDENTIFIER = com.example.sotie.journal
DEVELOPMENT_TEAM = YOUR_TEAM_ID
SOTIE_BACKEND_BASE_URL = http://127.0.0.1:8080
```

`Local.xcconfig` is ignored by git. It is only for local machine overrides.

If the app target bundle ID is changed, the Live Activity extension bundle ID may also need to be changed in Xcode signing settings.

## Running the iOS app

1. Start the backend or use the configured remote backend URL.
2. Open `Sotie.xcodeproj`.
3. Select `Sotie (Debug)`.
4. Select an iOS simulator.
5. Run from Xcode.

The local StoreKit configuration is `Sotie.storekit`.

## Backend setup

Install dependencies:

```bash
cd backend
npm install
cp .env.example .env
```

Generate a session secret:

```bash
openssl rand -base64 32
```

Edit `backend/.env`:

```text
NODE_ENV=development
HOST=0.0.0.0
PORT=8080
REDIS_URL=redis://localhost:6379
SESSION_JWT_SECRET=<generated value>
OPENROUTER_API_KEY=<your OpenRouter API key>
APPLE_BUNDLE_ID=com.pvlppv.sotie.journal
APPLE_ENVIRONMENT=Sandbox
```

For a fully local reviewer setup, set `APPLE_BUNDLE_ID` to the same bundle ID used by the iOS app.

## Running Redis

With Docker:

```bash
cd backend
docker compose up --build
```

This starts Redis and the backend service from `backend/docker-compose.yml`.

If Redis is already installed locally, run Redis separately and keep:

```text
REDIS_URL=redis://localhost:6379
```

## Running the backend directly

In another terminal:

```bash
cd backend
npm run dev
```

Backend URL:

```text
http://127.0.0.1:8080
```

Health check:

```bash
curl http://127.0.0.1:8080/health
```

## Backend API

```text
GET  /health
POST /v1/session
GET  /v1/me
POST /v1/entitlements/verify-transaction
POST /v1/ai/go-deeper/stream
```

The iOS app reads `SOTIE_BACKEND_BASE_URL` from build settings.

## Checks

Backend tests:

```bash
cd backend
npm test
```

Backend type check:

```bash
cd backend
npm run typecheck
```

Backend build:

```bash
cd backend
npm run build
```

iOS tests:

```text
Run tests from Xcode with the Sotie (Debug) scheme.
```

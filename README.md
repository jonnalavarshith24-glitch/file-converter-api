# File Converter API

An asynchronous file conversion service built with **Node.js, Express and BullMQ**. Upload a file, get a job ID back immediately, and download the result when a background worker finishes. Large or slow conversions never block the HTTP server.

## Features

- **Image conversion** between PNG, JPEG, WebP, AVIF and TIFF (`sharp`), with optional resize and quality settings
- **Markdown to PDF / HTML** rendered in sandboxed headless Chromium (JavaScript and network disabled)
- **CSV to JSON** and **JSON to CSV**
- **Redis-backed job queue** (BullMQ) with retries, exponential backoff and configurable concurrency
- **Separate API and worker processes** that scale independently
- Input validation (`zod`), security headers (`helmet`), rate limiting, upload size limits
- Random on-disk filenames, extension allow-list, automatic expiry and cleanup of files
- Docker and Docker Compose setup, unit tests (Vitest) and GitHub Actions CI

## Architecture

```
                 POST /conversions                      
  Client ───────────────────────────▶  API (Express)  ──▶ Redis (BullMQ queue)
     ▲   ◀──── 202 { id, links } ────      │                    │
     │                                     │ saves upload       ▼
     │ GET /conversions/:id                ▼             Worker(s) pick up jobs
     │ GET /conversions/:id/download   storage/uploads ─▶ convert ─▶ storage/outputs
     └─────────────────────────────────────────────────────────────┘
```

## Quick start

### With Docker (recommended)

```bash
docker compose up --build
```

The API is available at `http://localhost:3000`.

### Local development

Requires Node.js 20+ and a running Redis (`docker run -p 6379:6379 redis:7-alpine`).

```bash
cp .env.example .env
npm install
npm run dev          # terminal 1: API
npm run dev:worker   # terminal 2: worker
npm test
```

## API

Base path: `/api/v1`

| Method | Endpoint                    | Description                                   |
| ------ | --------------------------- | --------------------------------------------- |
| GET    | `/formats`                  | List supported conversions                    |
| POST   | `/conversions`              | Upload a file and enqueue a conversion        |
| GET    | `/conversions/:id`          | Check job status and progress                 |
| GET    | `/conversions/:id/download` | Download the converted file                   |
| GET    | `/health`, `/ready`         | Liveness and readiness (Redis) probes         |

### Create a conversion

```bash
curl -X POST http://localhost:3000/api/v1/conversions \
  -F "file=@photo.png" \
  -F "to=webp" \
  -F 'options={"quality":80,"width":1200}'
```

```json
{
  "id": "3f6c1e2a-8d44-4b7e-9a51-0c2b6f1d7e90",
  "status": "queued",
  "from": "png",
  "to": "webp",
  "links": {
    "status": "/api/v1/conversions/3f6c1e2a-...",
    "download": "/api/v1/conversions/3f6c1e2a-.../download"
  }
}
```

### Poll status, then download

```bash
curl http://localhost:3000/api/v1/conversions/<id>
# { "status": "completed", "progress": 100, "result": { "sizeBytes": 48211, ... } }

curl -OJ http://localhost:3000/api/v1/conversions/<id>/download
```

Statuses: `queued`, `processing`, `completed`, `failed`.

### Options (images)

| Option    | Type       | Description                                  |
| --------- | ---------- | -------------------------------------------- |
| `quality` | 1 to 100   | Output quality (JPEG, WebP, AVIF, TIFF)      |
| `width`   | 1 to 10000 | Max width in px (aspect ratio preserved)     |
| `height`  | 1 to 10000 | Max height in px (aspect ratio preserved)    |

### Supported conversions

| From                         | To                              |
| ---------------------------- | ------------------------------- |
| png, jpg, webp, avif, tiff   | any other image format in list  |
| md                           | pdf, html                       |
| csv                          | json                            |
| json (array of objects)      | csv                             |

## Configuration

All settings are environment variables (see `.env.example`).

| Variable              | Default                  | Description                                  |
| --------------------- | ------------------------ | -------------------------------------------- |
| `PORT`                | `3000`                   | API port                                     |
| `REDIS_URL`           | `redis://localhost:6379` | Redis connection string                      |
| `STORAGE_DIR`         | `./storage`              | Where uploads and outputs are stored         |
| `MAX_FILE_SIZE_MB`    | `25`                     | Upload size limit                            |
| `FILE_TTL_MINUTES`    | `60`                     | Lifetime of files and job records            |
| `WORKER_CONCURRENCY`  | `4`                      | Parallel jobs per worker process             |
| `RATE_LIMIT_PER_MIN`  | `30`                     | Requests per IP per minute                   |
| `CHROMIUM_PATH`       | (bundled)                | Custom Chromium binary for PDF rendering     |
| `CHROMIUM_NO_SANDBOX` | `false`                  | Set `true` inside containers                 |

## Project structure

```
src/
  app.js              Express app (middleware + routes)
  server.js           API entry point
  worker.js           Queue worker entry point
  queue.js            BullMQ queue and Redis connection
  config.js           Validated environment config
  converters/         One module per conversion family + registry
  routes/             HTTP endpoints
  middleware/         Upload handling, error handling
  utils/cleanup.js    Expired file sweeper
tests/                Vitest unit tests
```

## Adding a new converter

1. Create a function `async (inputPath, outputPath, options)` in `src/converters/`.
2. Register it in `src/converters/index.js`: `register('docx', 'pdf', convertDocxToPdf)`.
3. Add a MIME type to `MIME_TYPES` if the output format is new.

The API, validation and `/formats` endpoint pick it up automatically.

## Security notes

- Uploaded filenames are never used on disk; extensions are checked against an allow-list.
- Markdown is rendered with raw HTML disabled, and Chromium runs with JavaScript off and all network requests blocked.
- This project has **no authentication**. Put it behind an API gateway or add API-key middleware before exposing it publicly.

## Roadmap

- [ ] API-key authentication
- [ ] S3-compatible storage backend
- [ ] Webhook callbacks when a job completes
- [ ] DOCX to PDF via LibreOffice
- [ ] Prometheus metrics and a Bull Board dashboard

## License

MIT

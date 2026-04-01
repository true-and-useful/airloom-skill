# airloom API Reference

Base URL: `https://airloom.fm`

All API endpoints return JSON. All errors follow the shape `{ "error": "<code>", ... }`.

Authenticated requests use `Authorization: Bearer <API_KEY>`. Invalid keys return `401`.

The `X-Airloom-Client` header is optional on all requests — agent attribution for analytics (e.g. `claude-code/upload-sh`).

---

## Auth

### Request sign-in code

```
POST /api/auth/request-code
Content-Type: application/json

{ "email": "user@example.com" }
```

**Response** (`200`):

```json
{ "success": true, "requiresCodeEntry": true }
```

Sends a 9-character code (format: `XXXX-XXXX`, alphanumeric, case-insensitive) to the email. Code expires in 15 minutes.

**Errors**:

| Status | Error | When |
|---|---|---|
| `429` | `rate_limited` | Too many requests (5/hour per email) |

### Verify code

```
POST /api/auth/verify-code
Content-Type: application/json

{ "email": "user@example.com", "code": "GSPW-48F5" }
```

**Response** (`200`):

```json
{
  "success": true,
  "email": "user@example.com",
  "apiKey": "4a78471890eea83c197d4bc2a1cad0d42dbb381d65db7c8325bed08a545c2dd6"
}
```

`apiKey` is a 64-character hex token. Shown once — save immediately to `~/.airloom/credentials` (chmod 600). Existing users get their existing key.

**Errors**:

| Status | Error | When |
|---|---|---|
| `400` | `invalid_code` | Wrong code |
| `400` | `code_expired` | Code older than 15 minutes |
| `429` | `rate_limited` | Too many attempts |

---

## Upload

### Upload audio

```
POST /api/v1/upload
Authorization: Bearer <API_KEY>       (omit for anonymous)
X-Airloom-Client: claude-code         (optional)
Content-Type: multipart/form-data

Fields:
  file           required  audio file (MP3, M4A, OGG — max 100 MB)
  title          optional  string (max 200 chars, default: filename)
  description    optional  string (max 5000 chars, plain text)
  podcast        optional  podcast slug — assigns to a podcast (requires auth)
```

**Response** (`201 Created`):

```json
{
  "slug": "wild-river-9x2k",
  "showUrl": "https://airloom.fm/p/calm-dawn-bk01",
  "feedUrl": "https://airloom.fm/p/calm-dawn-bk01/feed.xml",
  "episodeUrl": "https://airloom.fm/wild-river-9x2k",
  "audioUrl": "https://cdn.airloom.fm/wild-river-9x2k/audio.mp3",
  "qr": "█████████████████████████████\n...",
  "fileSizeBytes": 4832000,
  "title": "My Recording",
  "description": "Notes here",
  "createdAt": "2026-03-18T12:00:00Z",
  "expiresAt": "2026-03-19T12:00:00Z",
  "apiKey": "4a78471890eea83c..."
}
```

`showUrl` always points to the effective podcast's show page. `qr` encodes the show page URL.

`apiKey` is only returned on first upload (when a provisional user is created). The agent must store it immediately. Subsequent uploads do not return `apiKey`.

`expiresAt` is null for verified users (permanent). For provisional users, episodes expire after 24h.

**Errors**:

| Status | Error | When |
|---|---|---|
| `400` | `missing_field` | Required field missing |
| `413` | `file_too_large` | File exceeds 100 MB |
| `415` | `unsupported_format` | Not MP3/M4A/OGG or MIME mismatch |
| `429` | `rate_limited` | Too many uploads |

---

## Episodes

### Get episode metadata

```
GET /api/v1/episodes/:slug
```

**Response** (`200`):

```json
{
  "slug": "wild-river-9x2k",
  "episodeUrl": "https://airloom.fm/wild-river-9x2k",
  "audioUrl": "https://cdn.airloom.fm/wild-river-9x2k/audio.mp3",
  "title": "My Recording",
  "description": "Notes here",
  "fileSizeBytes": 4832000,
  "createdAt": "2026-03-18T12:00:00Z",
  "expiresAt": null
}
```

Public access — no auth required.

**Errors**:

| Status | Error | When |
|---|---|---|
| `404` | `not_found` | Audio doesn't exist |
| `410` | `gone` | Audio was deleted |

### Delete episode

```
DELETE /api/v1/episodes/:slug
Authorization: Bearer <API_KEY>
```

**Response**: `204 No Content`

Only the owner can delete. Audio file purged from R2 immediately. Anonymous uploads cannot be manually deleted — they expire after 24 hours.

**Errors**:

| Status | Error | When |
|---|---|---|
| `401` | `unauthorized` | Missing or invalid API key |
| `403` | `forbidden` | Not the owner |
| `404` | `not_found` | Audio doesn't exist |

### Make content permanent (verify email)

Provisional users have expiring content. To make everything permanent, attach an email via the verify-code flow. Send `POST /api/auth/verify-code` with `{ "email": "...", "code": "..." }` and the `Authorization: Bearer <API_KEY>` header. This attaches the email, clears expiry on all episodes, and rotates the API key.

**Legacy claim endpoint** (`POST /api/v1/episodes/:slug/claim`) is retained for backward compatibility with pre-existing uploads that have claim tokens. New uploads do not generate claim tokens.

**Errors**:

| Status | Error | When |
|---|---|---|
| `401` | `unauthorized` | Missing or invalid API key |
| `403` | `invalid_claim_token` | Wrong token |
| `404` | `not_found` | Audio doesn't exist or expired |
| `409` | `already_claimed` | Audio already belongs to a user |

---

## Podcasts

### Create podcast

```
POST /api/v1/podcasts
Authorization: Bearer <API_KEY>
Content-Type: application/json

{ "title": "My Podcast", "description": "Optional description" }
```

**Response** (`201 Created`):

```json
{
  "id": "uuid",
  "slug": "bright-creek-4x2m",
  "title": "My Podcast",
  "description": "Optional description",
  "feedUrl": "https://airloom.fm/p/bright-creek-4x2m/feed.xml",
  "createdAt": "2026-03-18T18:00:00Z"
}
```

**Errors**:

| Status | Error | When |
|---|---|---|
| `400` | `missing_field` | Title missing |
| `401` | `unauthorized` | Missing or invalid API key |

### Get podcast

```
GET /api/v1/podcasts/:slug
```

**Response** (`200`):

```json
{
  "slug": "bright-creek-4x2m",
  "title": "My Podcast",
  "description": "Optional description",
  "feedUrl": "https://airloom.fm/p/bright-creek-4x2m/feed.xml",
  "episodeCount": 5,
  "createdAt": "2026-03-18T18:00:00Z"
}
```

Public access. 404 if not found, 410 if deleted.

### Show page

```
GET /p/:slug
```

Returns an HTML page for the podcast — title, description, episode list, and a platform-aware subscribe button. Public access. This is the URL to share or encode in a QR code.

### RSS feed

```
GET /p/:slug/feed.xml
```

Returns RSS 2.0 XML with `<enclosure>` tags for each episode. Public access. Episodes ordered by `created_at` descending.

### List my podcasts

```
GET /api/v1/me/podcasts
Authorization: Bearer <API_KEY>
```

**Response** (`200`):

```json
{
  "podcasts": [
    {
      "slug": "bright-creek-4x2m",
      "title": "My Podcast",
      "feedUrl": "https://airloom.fm/p/bright-creek-4x2m/feed.xml",
      "episodeCount": 5,
      "createdAt": "2026-03-18T18:00:00Z"
    }
  ]
}
```

---

## User

### Get current user

```
GET /api/v1/me
Authorization: Bearer <API_KEY>
```

**Response** (`200`):

```json
{
  "email": "user@example.com",
  "createdAt": "2026-03-18T12:00:00Z",
  "episodeCount": 3
}
```

### List my episodes

```
GET /api/v1/me/episodes
Authorization: Bearer <API_KEY>
```

**Response** (`200`):

```json
{
  "episodes": [
    {
      "slug": "wild-river-9x2k",
      "episodeUrl": "https://airloom.fm/wild-river-9x2k",
      "title": "My Recording",
      "fileSizeBytes": 4832000,
      "createdAt": "2026-03-18T12:00:00Z",
      "expiresAt": null
    }
  ]
}
```

Ordered by `createdAt` descending. No pagination (max 500 uploads per user).

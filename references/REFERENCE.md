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
```

**Response** (`201 Created`):

```json
{
  "slug": "wild-river-9x2k",
  "url": "https://airloom.fm/wild-river-9x2k",
  "audioUrl": "https://cdn.airloom.fm/wild-river-9x2k/audio.mp3",
  "qr": "█████████████████████████████\n...",
  "fileSizeBytes": 4832000,
  "title": "My Recording",
  "description": "Notes here",
  "createdAt": "2026-03-18T12:00:00Z",
  "claimToken": "a1b2c3d4e5...",
  "claimUrl": "https://airloom.fm/claim?slug=wild-river-9x2k&token=a1b2c3d4e5",
  "expiresAt": "2026-03-19T12:00:00Z"
}
```

`claimToken`, `claimUrl`, `expiresAt` omitted for authenticated uploads (permanent).

**Errors**:

| Status | Error | When |
|---|---|---|
| `400` | `missing_field` | Required field missing |
| `413` | `file_too_large` | File exceeds 100 MB |
| `415` | `unsupported_format` | Not MP3/M4A/OGG or MIME mismatch |
| `429` | `rate_limited` | Too many uploads |

---

## Audio

### Get metadata

```
GET /api/v1/audio/:slug
```

**Response** (`200`):

```json
{
  "slug": "wild-river-9x2k",
  "url": "https://airloom.fm/wild-river-9x2k",
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

### Delete

```
DELETE /api/v1/audio/:slug
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

### Claim anonymous upload

```
POST /api/v1/audio/:slug/claim
Authorization: Bearer <API_KEY>
Content-Type: application/json

{ "token": "a1b2c3d4e5..." }
```

**Response** (`200`):

```json
{
  "success": true,
  "slug": "wild-river-9x2k",
  "url": "https://airloom.fm/wild-river-9x2k",
  "expiresAt": null
}
```

`expiresAt: null` confirms the audio is now permanent.

**Rules**: Requires valid API key. Token must match the `claimToken` from upload. Single-use. Must claim before `expiresAt`.

**Errors**:

| Status | Error | When |
|---|---|---|
| `401` | `unauthorized` | Missing or invalid API key |
| `403` | `invalid_claim_token` | Wrong token |
| `404` | `not_found` | Audio doesn't exist or expired |
| `409` | `already_claimed` | Audio already belongs to a user |

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
  "audioCount": 3
}
```

### List my uploads

```
GET /api/v1/me/audio
Authorization: Bearer <API_KEY>
```

**Response** (`200`):

```json
{
  "audio": [
    {
      "slug": "wild-river-9x2k",
      "url": "https://airloom.fm/wild-river-9x2k",
      "title": "My Recording",
      "fileSizeBytes": 4832000,
      "createdAt": "2026-03-18T12:00:00Z",
      "expiresAt": null
    }
  ]
}
```

Ordered by `createdAt` descending. No pagination (max 500 uploads per user).

# woochat_mobile

Flutter mobile client for the WooChat WhatsApp Business CRM.

It is a **read/write consumer of an existing self-hosted Supabase backend**
(`https://spx.aurotec.in`). This project creates no tables, RPCs, edge functions
or RLS policies — it only calls what the backend already exposes.

---

## Phase 1 scope

| Area | Status |
| --- | --- |
| Supabase auth (email + password) | Implemented |
| Tenant + role resolution | Implemented |
| Chats list (realtime) | Implemented |
| Single chat + send (realtime) | Implemented |
| Chats bottom-nav tab | Implemented |
| Leads / Bulk / Automation / Settings tabs | Disabled placeholders |

---

## Configuration

Credentials are never committed. [`lib/src/config/env.dart`](lib/src/config/env.dart)
resolves them from two sources, in priority order:

1. **`--dart-define` / `--dart-define-from-file`** (compile-time) — use for CI
   and release builds.
2. **`assets/env/env.json`** (runtime) — so a plain `flutter run` works with no
   flags to remember.

### Setup (once)

```bash
cp assets/env/env.example.json assets/env/env.json
```

Then fill it in:

```json
{
  "SUPABASE_URL": "https://spx.aurotec.in",
  "SUPABASE_ANON_KEY": "<the project anon key>"
}
```

`assets/env/env.json` is git-ignored; `env.example.json` is the committed
template and also keeps the directory non-empty so a fresh clone still builds.

### Running

```bash
flutter run                              # any device, reads assets/env/env.json
flutter run -d chrome --web-port 8099    # browser — see the note below
```

> **Chrome: always pass a fixed `--web-port`.** Without it every `flutter run`
> picks a random port, and to the browser `localhost:50171` and
> `localhost:51234` are two different sites with separate storage — so the
> saved sign-in from the last run is simply not there, and the app opens on
> the login screen. That is not the app signing you out; it is a fresh origin.
> A fixed port keeps the same origin, and the session, across restarts.
> (A hot restart inside a running session never changes the port.)

To override at build time (CI, release):

```bash
flutter run --dart-define-from-file=assets/env/env.json
flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

If neither source supplies a value the app boots into a "Configuration missing"
screen rather than crashing.

> **Changing `env.json` needs a full restart, not a hot reload** — assets are
> read once at startup.

> **On secrecy:** the anon key is a *public* client key guarded by RLS, and it
> ends up in the shipped bundle either way — a `--dart-define` compiles it into
> `main.dart.js` just as visibly. Never put a `service_role` key in this file.

---

## Backend contract

Everything the app touches on the existing schema:

### `tenant_admin_id(p_user uuid) -> uuid`
Called once after sign-in with the authenticated user's id. The returned uuid is
the **tenant owner id**, and it is what every data query is scoped by.

### `user_roles`
`select role where user_id = <auth uid>`. The `app_role` enum
(`super_admin` / `admin` / `moderator` / `user`) is mapped in
[`lib/src/core/constants.dart`](lib/src/core/constants.dart). A user holding
several rows resolves to the highest-ranked role. Role is **presentational only**
in Phase 1 — authorisation stays with the backend's RLS.

### `chats`
`chats` has no tenant column; rows belong to a tenant through `chats.user_id`,
which equals the `tenant_admin_id()` result. Columns read:

```
id, user_id, contact_name, contact_phone, profile_photo_url,
is_archived, is_pinned, is_unread, unread_count,
last_message, last_message_at, last_message_direction, last_message_status
```

Last message and unread count come straight from these denormalized columns —
no aggregation over `messages`. Archived chats are hidden; pinned chats sort
first, then by `last_message_at` descending.

### `messages`
Subscribed per chat via `stream(primaryKey: ['id']).eq('chat_id', ...)`.
Columns read: `id, chat_id, user_id, direction, content, status, template_name,
whatsapp_message_id, reply_to_message_id, reaction, send_error_message,
created_at`.

### Sending
1. Insert into `messages`:
   `chat_id`, `user_id` (= tenant admin id), `direction: 'outbound'`,
   `content`, `status: 'pending'`.
2. Invoke the existing `whatsapp-send` edge function with the new message id.
3. If the invoke fails, the row is updated to `status: 'failed'` with
   `send_error_message`, so a failed send is visible instead of silently lost.

---

## Verify before first run

Two details were implemented from reasonable defaults rather than confirmed
schema — check them against the backend and adjust in one place if they differ:

1. **`whatsapp-send` request body.** Currently sent as
   `{ messageId, chatId, to, content }` from
   [`lib/src/data/messages_repository.dart`](lib/src/data/messages_repository.dart).
   Change the map there if the edge function expects different keys.
2. **String literals for `direction` and `status`** (`inbound`/`outbound`,
   `pending`/`sent`/`delivered`/`read`/`failed`), declared in
   [`lib/src/core/constants.dart`](lib/src/core/constants.dart).

Also confirm **realtime replication is enabled** for `chats` and `messages` in
the Supabase project. If it is not, the app still loads correctly — the streams
emit their initial snapshot — but the lists will not update live. The Chats
screen has a manual refresh action as a fallback.

---

## Known Phase 1 limitations

- Opening a chat does **not** clear `unread_count` / `is_unread`. Clearing them
  would write to `chats`, which the backend may already manage via triggers, so
  it is deliberately left out pending confirmation.
- Text messages only — no media, templates, replies or reactions in the
  composer. Inbound templates are labelled in the bubble.
- Message history is capped at the most recent 200 rows per chat; no pagination.

---

## Project layout

```
lib/
  main.dart                     Supabase.initialize + runApp
  src/
    app.dart                    MaterialApp, theme, missing-config screen
    config/env.dart             dart-define + assets/env/env.json reader
    core/constants.dart         Table / RPC / enum literals from the backend
    core/formatting.dart        Timestamp formatting
    theme/app_theme.dart        Material 3 theme
    models/                     Chat, Message, TenantContext
    data/                       Auth, tenant, chats and messages repositories
    features/
      auth/                     Login screen + AuthGate
      shell/                    Bottom navigation shell
      chats/                    Chats list + row widgets
      chat/                     Conversation, bubbles, composer
```

State is held in `StatefulWidget`s and Supabase streams — no state-management
package, keeping the dependency surface to `supabase_flutter` and `intl`.

---

## Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run                 # reads assets/env/env.json
```

# Library API contract · v1

Proposed contract for the server to implement later. It is not a claim that the
current server supports these endpoints. `library.openapi.yaml` defines routes;
the JSON Schema files define request and response bodies and examples.

The Mac client currently sends the update requests below. Story
editing, versions, media attachments and deletion are persisted locally until
the remaining server routes are implemented. Library AI uses the server; LocalAgent is independent.

| Operation | Input | Successful output |
| --- | --- | --- |
| List stories | `GET /stories` | `{ "stories": [Story] }` |
| Add story | `POST /stories`, full Story | persisted Story, HTTP 201 |
| Save edited script | `POST /stories`, copied Story with a new UUID, timestamp and subtitle number | new Story with the same title; original retained |
| Save enrichment / active version | `PATCH /stories/{id}`, full Story | persisted snapshot, same UUID and creation time |
| Delete story | `DELETE /stories/{id}` | HTTP 204 |
| Delete all | `DELETE /stories`, `{ "ids": [uuid] }` | `{ "deletedIds": [uuid] }`; all-or-nothing |
| Update hashtags | `POST /stories/{id}/updates/hashtags`, LibraryRequest | `{ "hashtags": [string] }` |
| Update images | `POST /stories/{id}/updates/images`, LibraryRequest | `{ "images": [URL] }` |
| Update news | `POST /stories/{id}/updates/news`, LibraryRequest | `{ "news": [{title,url,source}] }` |
| Upload media (future) | `POST /stories/{id}/media`, multipart `kind` and `file` | `{ "url": "https://...", "kind": "image|video", "filename": "...", "byteCount": 123 }` |

All bodies use JSON, UTF-8 and camelCase Story properties. The request's `story`
is the current saved snapshot, including the active/default `scriptText`. Its
UUID must equal the route ID. `engine` is one of the labels in the request
schema; `None` disables AI. Hashtag/image/news retrieval must still work without
AI. Script refinement is available through the local agent catalog instead.

Updates return replacement data for exactly the requested kind. Missing a
required result field is an error; an empty array is a valid result with no
items. Only the relevant field is persisted; title, UUID, creation time and
script stay unchanged. Manual edit/save creates a
new Story with the same title, a new UUID, fresh creation time and next subtitle
number. `sourceStoryID` points to the original/root story. The original stays
unchanged. The edited copy retains script history and adds the changed script
as a new version. Stale pipeline outputs are not copied. Choosing an earlier
version changes only the copy's active `scriptText`; history remains available.

HTTP 400 means invalid input; 404 means missing story or unavailable route;
409 means conflicting revision; 422 means unusable engine/instruction; 500
means execution failed; 501 means the route is not implemented. Errors use
`{ "error": { "code": "...", "message": "..." } }`. Failed requests must not
partially overwrite story data. The native client presents the failure and
retains the existing story.

Local JSON reads `Sources/ScriptMakerMac/Resources/Samples/library_updates.json`, applies the configured
simulation delay, and labels its results as sample data. It does not invoke an
LLM, fetch remote media, or interpret the instruction. `sample://` image values
exist only in fixtures; real responses must use HTTP(S) media URLs. Server mode
uses the configured server URL and never applies the simulation delay.

Media imported with the native file picker is copied into the app's Application
Support directory. It is a local attachment, not a server upload. The future
multipart upload route accepts one image (up to 50 MiB) or video (up to 500 MiB).
Reject unsupported MIME types with HTTP 415 and oversized input with HTTP 413.
Server storage must return a persistent HTTP(S) URL; do not return temporary
signed URLs as permanent Story fields. The client then saves the attachment URL
in the Story snapshot. Removing a URL from a Story does not purge shared media
storage; backend storage cleanup is a separate operation. Secrets and external
publishing are outside this Library API contract.

## Shared AI selection

Settings owns one AI selection for Studio and Library. The editor has Provider,
Model and Reasoning controls. Only explicitly applying a selection adds it to
recent history; keep five unique selections, newest first. Cancel changes nothing.
Existing saved Studio AI configuration migrates once when no shared selection exists.

`model_identifier` is `provider/model/reasoning`. Percent-encode UTF-8 components
using RFC 3986 unreserved characters before joining; split on `/` before decoding.
Provider and model IDs are case-sensitive; reasoning IDs are lowercase. Example:
`Codex/gpt-5.4/high`; a model ID containing slash becomes `vendor%2Fmodel`.
The selected one-line identifier is displayed identically throughout the app.

Pipeline inputs send `model_identifier` and `ai_model` with this identifier, plus
`ai: {source, model, power, identifier}` for compatibility and tracing. Library
requests send `model_identifier` and the identical `engine` compatibility alias.
Servers must validate IDs against their catalog, resolve defaults themselves,
reject unsupported combinations with 422, and echo the effective identifier in
result metadata/logs. Never infer a provider from a model ID.

The proposed `GET /ai/models` response is defined in `ai-models.schema.json`.
It is served by the configured pipeline server, without simulation delay.
Local JSON uses the bundled Studio model catalog and configured simulation delay.
Labels are for display; requests use IDs. The catalog endpoint and backend model
routing are future server work. An unavailable catalog preserves the saved model
and surfaces an error; the client does not substitute local options in Server mode.

## Native sharing

Library Share exposes Google Drive, Telegram and standard macOS share destinations.
AI selection remains in Settings only; Library requests use that shared selection.

Google Drive exports UTF-8 story text using the macOS save dialog. Choose a folder
managed by Drive for desktop to sync it, or save locally for manual upload. This
client does not create a Drive account, perform OAuth, upload via the Drive API,
or change sharing permissions. The exported text includes title, screenplay,
hashtags, media URLs and source URLs. Cancelling writes nothing.
[Drive for desktop documentation](https://support.google.com/drive/answer/10838124).

Telegram opens its native `tg://msg_url` composer when installed, otherwise its
`https://t.me/share/url` page. The `url` parameter is the first valid story source
URL (empty for a manual story), and `text` is the same full story text. Encode both
query values independently, including plus signs, ampersands, Unicode and newlines.
The user chooses the recipient and sends the message in Telegram; opening the
composer does not count as a successful send. Failures are visible in Library.
[Telegram sharing contract](https://core.telegram.org/widgets/share).

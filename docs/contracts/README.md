# Library API contract · v1

Proposed contract for the server to implement later. It is not a claim that the
current server supports these endpoints. `library.openapi.yaml` defines routes;
the JSON Schema files define request and response bodies and examples.

The Mac client currently sends the update and refinement requests below. Story
editing, versions, media attachments and deletion are persisted locally until
the remaining server routes are implemented. No AI runs in the Mac app.

| Operation | Input | Successful output |
| --- | --- | --- |
| List stories | `GET /stories` | `{ "stories": [Story] }` |
| Add story | `POST /stories`, full Story | persisted Story, HTTP 201 |
| Edit story | `PATCH /stories/{id}`, full Story | persisted Story, same UUID and creation time |
| Delete story | `DELETE /stories/{id}` | HTTP 204 |
| Delete all | `DELETE /stories`, `{ "ids": [uuid] }` | `{ "deletedIds": [uuid] }`; all-or-nothing |
| Update hashtags | `POST /stories/{id}/updates/hashtags`, LibraryRequest | `{ "hashtags": [string] }` |
| Update images | `POST /stories/{id}/updates/images`, LibraryRequest | `{ "images": [URL] }` |
| Update news | `POST /stories/{id}/updates/news`, LibraryRequest | `{ "news": [{title,url,source}] }` |
| Fine tune | `POST /stories/{id}/refinements`, LibraryRequest | `{ "script": "refined script" }` |

All bodies use JSON, UTF-8 and camelCase Story properties. The request's `story`
is the current saved snapshot, including the active/default `scriptText`. Its
UUID must equal the route ID. `engine` is one of the labels in the request
schema; `None` disables AI. Hashtag/image/news retrieval must still work without
AI. Fine tuning requires an enabled engine and a nonblank `instruction`.

Updates return replacement data for exactly the requested kind. Missing a
required result field is an error; an empty array is a valid result with no
items. Only the relevant field is persisted; title, UUID, creation time and
script stay unchanged. Refinements return a preview and must never overwrite
the script automatically. Explicit acceptance appends a script version and
sets `scriptText` to that version. Choosing an earlier version changes only
`scriptText`; history remains available.

HTTP 400 means invalid input; 404 means missing story or unavailable route;
409 means conflicting revision; 422 means unusable engine/instruction; 500
means execution failed; 501 means the route is not implemented. Errors use
`{ "error": { "code": "...", "message": "..." } }`. Failed requests must not
partially overwrite story data. The native client presents the failure and
retains the existing story.

Local JSON reads `Resources/Samples/library_updates.json`, applies the configured
simulation delay, and labels its results as sample data. It does not invoke an
LLM, fetch remote media, or interpret the instruction. `sample://` image values
exist only in fixtures; real responses must use HTTP(S) media URLs. Server mode
uses the configured server URL and never applies the simulation delay.

Media imported with the native file picker is copied into the app's Application
Support directory. It is a local attachment, not a server upload. Before remote
uploads are enabled, define the storage, size limits, multipart body and URL
lifetime in a separate upload contract. Secrets and external publishing are
outside this Library API contract.

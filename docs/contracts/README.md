# Saved Library compatibility

`library-story.schema.json` documents historical saved-story fields. Keep existing IDs,
media references, script versions, chat histories and upload receipts readable. The Mac
also accepts legacy arrays of raw story dictionaries. Corrupt data must surface an error
and remain intact; an empty Library is valid only when storage is absent or truly empty.

There is no server Library update or model-catalog API. LibraryUpdating takes an update
kind and Story and returns typed enrichment results from local discovery clients.
Uploads and explicit sharing retain their existing external destination contracts.

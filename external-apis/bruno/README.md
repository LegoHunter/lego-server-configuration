# LegoHunter Bruno Workspace

Open the `LegoHunter Workspace` folder as a Bruno workspace, or open the named API collection folders individually.

Workspace path:

```text
external-apis/bruno/LegoHunter Workspace
```

The workspace folder contains `workspace.yml`, a `collections/` directory, and workspace-scoped global environments in `environments/*.yml`.

Individual native Bruno collection paths, if you prefer opening one collection at a time:

```text
external-apis/bruno/LegoHunter Service Requests
external-apis/bruno/Bricklink AJAX Requests
external-apis/bruno/Bricklink API Requests
external-apis/bruno/Bitly API Requests
external-apis/bruno/Flickr API Requests
external-apis/bruno/eBay API Requests
```

## Layout

- `LegoHunter Service Requests/lego-data-service Requests`: examples for every controller mapping found in `lego-data-service`.
- `LegoHunter Service Requests/lego-data-ingress Requests`: examples for every controller mapping found in `lego-data-ingress`.
- `Bricklink AJAX Requests`: examples for the BrickLink AJAX endpoints wrapped by the local `bricklink-ajax` client.
- `Bricklink API Requests`: examples for the BrickLink REST endpoints wrapped by the local `bricklink-rest` client.
- `Bitly API Requests`: examples for link shortening and group bitlink lookup used by image-hosting short URL workflows.
- `Flickr API Requests`: examples for Flickr album/photo read, metadata, upload, and replace workflows used by image hosting.
- `eBay API Requests`: examples for OAuth, Browse API search/read, and starter Sell Inventory item calls for future marketplace work.

## Environments

The workspace includes these environments:

- `local`
- `sandbox`
- `dev`
- `prod`
- `Bitly`
- `Bricklink API`
- `Flickr API`
- `eBay API`

Each environment is present in two formats:

- `.bru` files are the native collection environment files that Bruno discovers by name in the `environments/` folder.
- `.json` files are import/export-friendly environment files that can be selected with the CLI `--env-file` option or imported manually through Bruno's environment UI.
- `.yml` files are present under `LegoHunter Workspace/environments/` for Bruno workspace-scoped global environments.

Secret placeholders are declared as `vars:secret` entries in `.bru` files and with `"secret": true` in `.json` files. Bruno stores filled-in secret values locally and does not write them into the collection files.

Each individual collection also has its own populated `environments/` folder with the same environment names, so importing a single collection does not depend on the all-in-one workspace folder.

## Notes

- BrickLink REST and Flickr write requests require OAuth 1.0 signatures. The workspace includes placeholder variables for timestamp, nonce, and signature values.
- BrickLink `Inventory - Create Inventory` is intentionally stockroom-only in its sample body. Do not send it against the live account without deliberately reviewing the target environment and payload.
- The external API folders are representative of the APIs used or planned by LegoHunter, not exhaustive vendor API mirrors.

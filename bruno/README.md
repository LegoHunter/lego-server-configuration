# Bruno collection

The one official Bruno collection for LegoHunter's API requests. Open **this folder**
(`lego-server-configuration/bruno`) in Bruno with **Open Collection**. Do not open the old
duplicate copies: they were removed.

## Layout

- `bruno.json`, `collection.bru`: the collection and its shared base-URL variables.
- `environments/`: `sandbox`, `dev`, `prod`, `local`, and the API-specific environments (`Bitly`,
  `Bricklink API`, `Flickr API`, `eBay API`). Secret values are not stored in these files; mark
  them as secrets in Bruno's secret store.
- `external-apis/`: one folder per external API (Bitly, Bricklink AJAX, Bricklink API, Flickr,
  eBay) and the LegoHunter services (`LegoHunter Service Requests`). The Bricklink API folder's
  `folder.bru` carries the OAuth 1.0a signing script for its requests only.
- `lcms/`: LCMS requests: `kubernetes` (per-environment requests), `local`, `Bricklink WEB`, and
  `photo-upload-admin` (token issue and revoke for the Lightroom publisher; see the runbook in
  lego-data-ingress).

## Adding a request

Put it in the folder for its API or service. Use the collection's variables (for example
`{{lego_data_service_base_url}}`) rather than a hard-coded host, so the environment decides where
it goes.

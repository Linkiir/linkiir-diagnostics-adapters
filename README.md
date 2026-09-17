# Linkiir Diagnostics Adapters

Adapters for results and signals arriving from an instrument: reference labs and LIS, imaging and PACS, and bedside or wearable devices.

A **catalog** is a package of adapter content that one Linkiir Grid publishes and other grids subscribe to. Subscribing adds these adapters to your grid without a product upgrade.

| | |
|---|---|
| **Catalog id** | `lkdx` |
| **Publisher** | Linkiir Inc |
| **Adapters** | 2 |
| **Libraries** | 1 |
| **Documentation** | [https://help.linkiir.com/docs/catalogs/](https://help.linkiir.com/docs/catalogs/) |

---

## Subscribe

In Grid, open **Settings → Catalogs → Subscribe** and paste this URL:

```
https://github.com/Linkiir/linkiir-diagnostics-adapters
```

| Field | Value |
|---|---|
| **URL** | the address above |
| **Ref** | `main` |
| **SSH private key** | leave blank — this is a public repository, cloned anonymously |
| **Install name** | `linkiir-diagnostics-adapters` |

Use the install name exactly as given. Grid records it on every node built from this catalog, so a consistent name keeps a node's origin readable when you contact support.

Subscribing requires the **Manage catalogs** permission (Administration tier). Full instructions, including how to review an update before applying it, are in [the Catalogs documentation](https://help.linkiir.com/docs/catalogs/).

## Adapters

| Adapter | Type | Trigger | Version | Node type id |
|---|---|---|---|---|
| **Dexcom Authorize** | source | inbound request | 1.0.0 | `LKDX_DEXCOM_AUTHORIZE` |
| **Dexcom Read EGV** | source | interval | 1.0.0 | `LKDX_DEXCOM_READ_EGV` |

### Dexcom Authorize

Web page that runs Dexcom's user authorization and stores the resulting token pair. Dexcom offers no unattended grant, so this is the one step a person has to perform. Also shows token status and can disconnect.

`LKDX_DEXCOM_AUTHORIZE` · source node · version 1.0.0 · 11 configuration fields · library `dexcom_cgm` 1.0.0

Credentials required: **Client Secret**. These ship empty — see [Credentials](#credentials).

### Dexcom Read EGV

Reads estimated glucose values on a timer and pushes them downstream exactly as Dexcom returns them. Refreshes the access token when it ages out and persists the new pair. Holds no cursor: it reads a trailing window, because where to resume depends on what the consumer does with the data.

`LKDX_DEXCOM_READ_EGV` · source node · version 1.0.0 · 11 configuration fields · library `dexcom_cgm` 1.0.0

Credentials required: **Client Secret**. These ship empty — see [Credentials](#credentials).

## Libraries

Shared Lua modules the adapters above depend on. A node pins the exact version it uses, and published versions are immutable, so several can sit side by side.

| Library | Version | Used by |
|---|---|---|
| `dexcom_cgm` | 1.0.0 | Dexcom Authorize, Dexcom Read EGV |

### `dexcom_cgm` 1.0.0

Dexcom CGM connectivity for the native Linkiir scripting API. Handles the three-legged OAuth authorization Dexcom requires, refreshes the rotating token pair, and reads dataRange and estimated glucose values over linkiir.link.web. Includes a single-row SQLite token store, because a user-authorized grant has to outlive the request that obtained it. Every call returns result or nil plus a classified error, and nothing raises. Connectivity only: readings are returned exactly as Dexcom sends them, with no cursor policy and no mapping into another system's model.

Modules: `dexcom_cgm.lua`, `dexcom_cgm_config.lua`, `dexcom_cgm_http.lua`

## Credentials

Every adapter here ships with its credential fields **empty**, by design. Password fields are encrypted with your own grid's key, so a value shipped from this repository could not be decrypted on your machine. Enter yours on the node after you build it.

Two fields appear on most adapters:

| Field | What it does |
|---|---|
| **Live Mode** | When off, requests are prepared and logged but never sent. Use it to confirm configuration and authentication before touching a live system. |
| **Verify TLS** | Verifies the server's certificate. Leave on. Turn it off only against a local service with a self-signed certificate. |

## Versions and updates

| | |
|---|---|
| **Adapters** | Versioned by the `version` field on each adapter. A change that does not move the version forward is rejected, so one version always means one specific set of files. |
| **Libraries** | Immutable. A published version is never edited; a fix ships as a new version. Nodes pinned to an older version are undisturbed by an update. |

Grid shows you the incoming commit and diff before applying an update. See [CHANGELOG.md](CHANGELOG.md) for what changed in each release.

## Repository layout

```
catalog.json                              catalog manifest
nodes/<slug>/node_config.json             an adapter definition
nodes/<slug>/*.lua                        its scripts
nodes/<slug>/samples/                     de-identified test messages
libraries/<name>/<version>/library.json   a published library version
libraries/<name>/<version>/<name>/*.lua   its modules
```

The layout matches Grid's own on-disk layout, so a pull applies no transform.

## Other Linkiir catalogs

| Catalog | Covers |
|---|---|
| [linkiir-fhir-adapters](https://github.com/Linkiir/linkiir-fhir-adapters) | FHIR adapters and FHIR tooling |
| [linkiir-ehr-adapters](https://github.com/Linkiir/linkiir-ehr-adapters) | EHR and practice management over proprietary APIs, openEHR |
| [linkiir-interop-adapters](https://github.com/Linkiir/linkiir-interop-adapters) | HL7 v2, C-CDA, IHE, HIE, public health, engine migration |
| [linkiir-payer-adapters](https://github.com/Linkiir/linkiir-payer-adapters) | X12 EDI, clearinghouses, payer APIs, pharmacy |
| **linkiir-diagnostics-adapters** _(this one)_ | labs and LIS, imaging and PACS, devices |
| [linkiir-data-adapters](https://github.com/Linkiir/linkiir-data-adapters) | relational and NoSQL databases, warehouses, BI |
| [linkiir-transport-adapters](https://github.com/Linkiir/linkiir-transport-adapters) | object storage, file transport, message brokers |
| [linkiir-ai-adapters](https://github.com/Linkiir/linkiir-ai-adapters) | AI and LLM services |
| [linkiir-notification-adapters](https://github.com/Linkiir/linkiir-notification-adapters) | chat, SMS, voice, email, paging |
| [linkiir-business-adapters](https://github.com/Linkiir/linkiir-business-adapters) | CRM, ERP, ITSM, HR, identity, scheduling |

## Documentation and support

Product documentation lives at **[help.linkiir.com](https://help.linkiir.com/docs/catalogs/)** — how catalogs work, subscribing and reviewing updates, building nodes from catalog adapters, and offline delivery. This repository holds the adapter content itself; it is not the documentation site.

For a question about a specific adapter, quote its node type id.

## License

Copyright © Linkiir Inc. All rights reserved.

This source is published so Linkiir Grid customers can read, audit and run it. It is **not** open source. See [LICENSE](LICENSE) for the terms that apply.


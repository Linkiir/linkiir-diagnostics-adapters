# Linkiir Diagnostics Adapters

Results and signals arriving from an instrument: reference labs and LIS, imaging and PACS, and bedside or wearable devices.

**Catalog id:** `lkdx` — every node template in this catalog carries a `LKDX_` node type id.
**Published adapters:** 2 &nbsp;•&nbsp; **Published libraries:** 1

---

## Subscribe

In Grid, go to **Settings → Catalogs → Subscribe** and paste:

```
https://github.com/Linkiir/linkiir-diagnostics-adapters
```

This is a public repository, so Grid clones it anonymously and no SSH key is needed. Leave **Ref** at `main` to track the latest published content.

Install it under the name **`linkiir-diagnostics-adapters`**. The install name is recorded on every node built from this catalog, so keeping it consistent makes a node's origin readable in support.

Subscribing needs the **Manage catalogs** permission (Administration tier).

## Published adapters

| Adapter | Slug | Node type | Node type id | Version | Libraries |
|---|---|---|---|---|---|
| Dexcom Authorize | `dexcom_authorize` | source | `LKDX_DEXCOM_AUTHORIZE` | 1.0.0 | dexcom_cgm 1.0.0 |
| Dexcom Read EGV | `dexcom_read_egv` | source | `LKDX_DEXCOM_READ_EGV` | 1.0.0 | dexcom_cgm 1.0.0 |

## Published libraries

| Library | Version | Purpose |
|---|---|---|
| `dexcom_cgm` | 1.0.0 | Dexcom CGM connectivity for the native Linkiir scripting API. Handles the three-legged OAuth authorization Dexcom requires, refreshes the rotating token pair, and reads dataRange and estimated glucose values over linkiir.link.web. Includes a single-row SQLite token store, because a user-authorized grant has to outlive the request that obtained it. Every call returns result or nil plus a classified error, and nothing raises. Connectivity only: readings are returned exactly as Dexcom sends them, with no cursor policy and no mapping into another system's model. |

## Roadmap

| Adapter | Node type | Connects to | Status |
|---|---|---|---|
| ORU Result Handler | transform | HL7 v2 ORU^R01 result path | Next |
| LabCorp / Quest / ARUP / BioReference / Mayo Labs | source | reference labs | Planned |
| Sunquest / Orchard / Roche cobas / Siemens Atellica / Beckman | source | laboratory information systems | Planned |
| DICOM C-STORE / C-FIND and DICOMweb | source, destination | imaging protocol layer | Planned |
| Agfa / Sectra / Philips Vue / Fujifilm / Intelerad / Ambra | source | PACS and reporting | Planned |
| Capsule / Philips IntelliVue / GE CARESCAPE / Draeger / Masimo | source | bedside monitoring | Planned |
| Remote patient monitoring (generic) | source | RPM feeds | Planned |

Status meanings: **Next** is in active development, **Planned** is scoped but not started. See [the Integration Network](https://linkiir.com/network/) for the full adapter list and where each one stands.

## Configuration and credentials

Every adapter ships with its credential fields **empty**, and that is deliberate. Password fields are encrypted with each grid's own key, so a value shipped from here could not decrypt on your machine — it would fail with an error blaming your key. Fill them in on the node after you build it.

Two fields appear on most adapters and are worth knowing:

- **Live Mode** — when off, requests are prepared and logged but never sent. Use it to prove configuration before touching a real system.
- **Verify TLS** — leave on. Turn it off only against a local service with a self-signed certificate.

## Support and status

Adapters here are **Beta** unless the roadmap table says otherwise: they work and run somewhere, but the template is still being finished, so expect a Linkiir engineer alongside you on a first deployment. **GA** means the template is hardened and running across multiple customers.

Every adapter has a named owner at Linkiir who maintains it. For a problem with a specific adapter, quote its node type id.

## Versioning

- **Adapters** are versioned by the `version` field in `node_config.json`. A change that does not move the version forward is refused by the validator.
- **Library versions are immutable.** A published `libraries/<name>/<version>/` directory is never edited; a fix ships as a new version directory. Several versions sit side by side and each node pins the one it uses, so updating this catalog cannot disturb a node pinned to an older library.

Before applying an update, Grid shows you the incoming commit and diff. Read [CHANGELOG.md](CHANGELOG.md) for what changed and why.

## Repository layout

```
catalog.json                              the manifest Grid validates
nodes/<slug>/node_config.json             an adapter's definition
nodes/<slug>/*.lua                        its scripts
nodes/<slug>/samples/                     de-identified test messages
libraries/<name>/<version>/library.json   a published library version
libraries/<name>/<version>/<name>/*.lua   its modules
```

The layout is identical to Grid's own on-disk layout, so a pull needs no transform.

---

Published by Linkiir Inc. Part of the [Linkiir catalog set](https://github.com/Linkiir?q=adapters) — see [the Catalogs documentation](https://help.linkiir.com/docs/catalogs/) for how catalogs reach a grid.

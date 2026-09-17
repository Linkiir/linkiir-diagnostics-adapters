# `dexcom_cgm` 1.0.0

Dexcom CGM connectivity for the native Linkiir scripting API. Handles the three-legged OAuth authorization Dexcom requires, refreshes the rotating token pair, and reads dataRange and estimated glucose values over linkiir.link.web. Includes a single-row SQLite token store, because a user-authorized grant has to outlive the request that obtained it. Every call returns result or nil plus a classified error, and nothing raises. Connectivity only: readings are returned exactly as Dexcom sends them, with no cursor policy and no mapping into another system's model.

| | |
|---|---|
| **Library** | `dexcom_cgm` |
| **Version** | 1.0.0 |
| **Immutable** | yes — a fix ships as a new version directory |

## Modules

- `dexcom_cgm/dexcom_cgm.lua`
- `dexcom_cgm/dexcom_cgm_config.lua`
- `dexcom_cgm/dexcom_cgm_http.lua`

## Using it

A node that pins this library gets the `dexcom_cgm/` folder copied in beside its script. Add it to `package.path` and require the entry module:

```lua
local dexcom_cgm = require("dexcom_cgm.dexcom_cgm")
```

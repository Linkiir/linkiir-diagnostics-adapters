# Dexcom Read EGV

Reads estimated glucose values on a timer and pushes them downstream exactly as Dexcom returns them. Refreshes the access token when it ages out and persists the new pair. Holds no cursor: it reads a trailing window, because where to resume depends on what the consumer does with the data.

| | |
|---|---|
| **Slug** | `dexcom_read_egv` |
| **Node type id** | `LKDX_DEXCOM_READ_EGV` |
| **Node type** | source |
| **Version** | 1.0.0 |
| **Interval driven** | yes |
| **Libraries** | dexcom_cgm 1.0.0 |

## Configuration

| Field | Type | Default | Notes |
|---|---|---|---|
| Interval | number | `300000` | How often, in milliseconds, to read. 300000 is five minutes, which matches how often a CGM produces a value. |
| Lookback Minutes | number | `60` | How far back each read reaches. Overlapping windows are expected: de-duplicating is the consumer's job, since only it knows what has already been handled. |
| Environment | list | `sandbox` | Which Dexcom environment to talk to: sandbox or production. They are separate hosts with separate credentials, so a production key against sandbox fails in a way that looks like a bad secret. |
| Client ID | string | _(empty)_ | The Client ID from your Dexcom application registration. Left blank on purpose: fill it in after import. |
| Client Secret | password | _(empty — set on the node)_ | The Client Secret from your Dexcom application registration. Stored encrypted and decrypted only when the script reads it. |
| Redirect URI | string | _(empty)_ | Where Dexcom sends the browser after sign-in. Must match the Dexcom registration exactly, character for character, and must be https. |
| Base URL Override | string | _(empty)_ | Leave blank to use the host implied by Environment. Set a full base URL only to point at a mock or a proxy. |
| Token Store Path | string | _(empty)_ | SQLite file holding the authorized token pair, relative to the Linkiir working directory. Dexcom only offers a user-authorized grant, so the tokens have to outlive the request that obtained them. |
| Request Timeout | number | `20` | Seconds to wait for a Dexcom response. |
| Verify TLS | bool | `true` | Verify Dexcom's certificate. Leave on; turn off only against a local mock. |
| Live Mode | bool | `false` | When off, requests are prepared but never sent, and calls report themselves as simulated. Lets an imported adapter be inspected before it touches a real account. |

# Dexcom Authorize

Web page that runs Dexcom's user authorization and stores the resulting token pair. Dexcom offers no unattended grant, so this is the one step a person has to perform. Also shows token status and can disconnect.

| | |
|---|---|
| **Slug** | `dexcom_authorize` |
| **Node type id** | `LKDX_DEXCOM_AUTHORIZE` |
| **Node type** | source |
| **Version** | 1.0.0 |
| **Interval driven** | no |
| **Libraries** | dexcom_cgm 1.0.0 |

## Configuration

| Field | Type | Default | Notes |
|---|---|---|---|
| Route Path | string | `dexcom/authorize` | URL path this endpoint listens on, unique within the project. The HTTP port comes from the project's HTTP Server settings. |
| Worker Count | number | `1` | Parallel Lua VMs handling concurrent requests. One is plenty for an authorization page. |
| Environment | list | `sandbox` | Which Dexcom environment to talk to: sandbox or production. They are separate hosts with separate credentials, so a production key against sandbox fails in a way that looks like a bad secret. |
| Client ID | string | _(empty)_ | The Client ID from your Dexcom application registration. Left blank on purpose: fill it in after import. |
| Client Secret | password | _(empty — set on the node)_ | The Client Secret from your Dexcom application registration. Stored encrypted and decrypted only when the script reads it. |
| Redirect URI | string | _(empty)_ | Where Dexcom sends the browser after sign-in. Must match the Dexcom registration exactly, character for character, and must be https. |
| Base URL Override | string | _(empty)_ | Leave blank to use the host implied by Environment. Set a full base URL only to point at a mock or a proxy. |
| Token Store Path | string | _(empty)_ | SQLite file holding the authorized token pair, relative to the Linkiir working directory. Dexcom only offers a user-authorized grant, so the tokens have to outlive the request that obtained them. |
| Request Timeout | number | `20` | Seconds to wait for a Dexcom response. |
| Verify TLS | bool | `true` | Verify Dexcom's certificate. Leave on; turn off only against a local mock. |
| Live Mode | bool | `false` | When off, requests are prepared but never sent, and calls report themselves as simulated. Lets an imported adapter be inspected before it touches a real account. |

-- dexcom_cgm_http.lua — one place where every Dexcom request is sent, so retry
-- policy and simulation behave the same for token exchanges and data reads.
--
-- Nothing raises. Functions return result or nil, err where err is
-- { kind, status, message } and `kind` is what a node branches on:
--
--   'transport'   no answer came back
--   'auth'        401 — the access token is stale; refresh and retry once
--   'ratelimit'   429 — Dexcom throttles hard; back off, do not hammer
--   'server'      5xx — Dexcom's problem, retry later
--   'client'      other 4xx — a bad request; retrying will not help
--   'decode'      a 2xx body that was not the JSON expected
local M = {}

M.RETRYABLE = { transport = true, ratelimit = true, server = true }

--- True when this failure is worth retrying on a later cycle.
function M.isRetryable(err)
   return err ~= nil and M.RETRYABLE[err.kind] == true
end

local function classify(status)
   if status == 401 then return 'auth' end
   if status == 429 then return 'ratelimit' end
   if status >= 500 then return 'server' end
   if status >= 400 then return 'client' end
   return nil
end

--- Send one request and classify the outcome.
-- opts: { method, url, headers, body, conn }
function M.send(opts)
   local conn = opts.conn or {}
   local method = string.upper(opts.method or 'GET')

   local args = {
      url       = opts.url,
      headers   = opts.headers or {},
      timeout   = tonumber(conn.timeout) or 20,
      verifyTls = conn.verifyTls ~= false,
      live      = conn.live ~= false,
   }
   if opts.body ~= nil then args.body = opts.body end

   local fn = (method == 'POST') and linkiir.link.web.post or linkiir.link.web.get
   local resp, err = fn(args)

   if not resp then
      return nil, { kind = 'transport', status = 0,
                    message = 'no response from Dexcom (' ..
                              tostring(err and err.code or 'unknown') .. ')' }
   end

   if resp.simulated then
      return { simulated = true, status = 0, body = '', json = nil }
   end

   local kind = classify(tonumber(resp.code) or 0)
   if kind then
      -- Deliberately never echo the body of a failed token call: Dexcom repeats
      -- the submitted code back, and that does not belong in a log.
      return nil, { kind = kind, status = resp.code,
                    message = 'Dexcom returned HTTP ' .. tostring(resp.code) }
   end

   return { status = resp.code, body = resp.body or '', headers = resp.headers }
end

--- Send a request and decode a JSON body.
function M.sendJson(opts)
   local res, err = M.send(opts)
   if not res then return nil, err end
   if res.simulated then return res end

   local ok, decoded = pcall(linkiir.json.parse, res.body)
   if not ok or type(decoded) ~= 'table' then
      return nil, { kind = 'decode', status = res.status,
                    message = 'response body was not JSON' }
   end
   res.json = decoded
   return res
end

return M

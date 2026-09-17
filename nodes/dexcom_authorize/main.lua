-- Dexcom Authorize — Source HTTP
--
-- The one part of a Dexcom connection that needs a human. Dexcom offers no
-- unattended grant: a person signs in and authorizes access to their own CGM
-- data, so this node exists to run that exchange once and store the result.
--
-- Three actions on one route, because a Linkiir HTTP source owns a single path:
--
--   GET  <route>                 status, and a button to start authorization
--   GET  <route>?start=1         redirect the browser to Dexcom
--   GET  <route>?code=..&state=. Dexcom's callback: code -> token pair
--   POST <route>  (disconnect=1) forget the stored tokens
--
-- The redirect is a meta refresh, not a 302: a Source HTTP response carries only
-- a status, a content type and a body, so there is no Location header to set.
--
-- The authorization code is single-use and expires in about a minute, so the
-- callback exchanges it inline rather than queueing the work.
local DX     = require 'dexcom_cgm'
local DXcfg  = require 'dexcom_cgm_config'

local ROUTE_HINT = 'dexcom/authorize'

-- --- rendering -------------------------------------------------------------
-- Deliberately plain HTML. This is an adapter: it should not drag a design
-- system along behind it.

local function esc(s)
   return (tostring(s or ''):gsub('[&<>"]', {
      ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }))
end

local STYLE = [[
body{font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;max-width:640px;
     margin:40px auto;padding:0 20px;color:#18181b}
h1{font-size:20px;margin:0 0 4px} .sub{color:#71717a;margin:0 0 20px}
.card{border:1px solid #e4e4e7;border-radius:10px;padding:18px 20px;margin:0 0 14px}
.k{color:#71717a;font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.v{font-weight:600;margin:2px 0 12px}
.btn{display:inline-block;background:#4f46e5;color:#fff;text-decoration:none;
     padding:9px 16px;border-radius:8px;font-weight:600;border:0;cursor:pointer}
.btn.ghost{background:#fff;color:#18181b;border:1px solid #e4e4e7}
.ok{color:#15803d} .warn{color:#b45309} .err{color:#b91c1c}
code{background:#f4f4f5;padding:1px 5px;border-radius:4px}
]]

local function respond(code, title, body)
   linkiir.link.web.respond{
      code = code,
      contentType = 'text/html; charset=utf-8',
      body = '<!DOCTYPE html><html><head><meta charset="utf-8">'
          .. '<title>' .. esc(title) .. '</title><style>' .. STYLE .. '</style></head>'
          .. '<body><h1>Dexcom Adapter</h1>'
          .. '<p class="sub">Authorization and token status</p>'
          .. body .. '</body></html>',
   }
end

local function note(cls, text)
   return '<p class="' .. cls .. '">' .. text .. '</p>'
end

-- --- actions ---------------------------------------------------------------

local function page_status(client, cfg, gaps, tok, extra)
   local body = extra or ''

   if gaps then
      body = body .. '<div class="card">'
          .. note('warn', '<strong>Not configured yet.</strong> Set these on this node, '
                       .. 'then reload: <code>' .. esc(gaps) .. '</code>')
          .. '</div>'
   end

   local state = 'Not authorized'
   local cls = 'warn'
   if tok and tok.refreshToken and tok.refreshToken ~= '' then
      local left = (tok.expiresAt or 0) - os.time()
      if left > 0 then
         state = 'Authorized · access token valid for ' .. tostring(math.floor(left / 60)) .. ' min'
         cls = 'ok'
      else
         state = 'Authorized · access token expired, will refresh on next read'
         cls = 'warn'
      end
   end

   body = body .. '<div class="card">'
       .. '<div class="k">Connection</div><div class="v">' .. esc(client:describe()) .. '</div>'
       .. '<div class="k">Status</div><div class="v ' .. cls .. '">' .. esc(state) .. '</div>'
       .. (tok and tok.dexcomUser and tok.dexcomUser ~= ''
            and ('<div class="k">Dexcom user id</div><div class="v"><code>'
                 .. esc(tok.dexcomUser) .. '</code></div>') or '')
       .. '</div>'

   local canStart = (gaps == nil)
   body = body .. '<div class="card">'
   if canStart then
      body = body .. '<a class="btn" href="?start=1">'
          .. ((tok and tok.refreshToken) and 'Re-authorize' or 'Authorize Dexcom') .. '</a>'
   else
      body = body .. note('warn', 'Fill in the configuration above before authorizing.')
   end
   if tok and tok.refreshToken then
      body = body .. ' <form method="POST" style="display:inline">'
          .. '<input type="hidden" name="disconnect" value="1">'
          .. '<button class="btn ghost" type="submit">Disconnect</button></form>'
   end
   body = body .. '</div>'

   respond(200, 'Dexcom Adapter', body)
end

--- Send the browser to Dexcom. Meta refresh plus a link, because this node
--- cannot emit a Location header.
local function action_start(client, cfg)
   local state = linkiir.sys.guid(128)
   local url = client:authorizeUrl(state)
   linkiir.link.web.respond{
      code = 200,
      contentType = 'text/html; charset=utf-8',
      body = '<!DOCTYPE html><html><head><meta charset="utf-8">'
          .. '<meta http-equiv="refresh" content="0;url=' .. esc(url) .. '">'
          .. '<title>Redirecting to Dexcom</title><style>' .. STYLE .. '</style></head>'
          .. '<body><h1>Dexcom Adapter</h1>'
          .. '<p class="sub">Sending you to Dexcom to sign in.</p>'
          .. '<p><a class="btn" href="' .. esc(url) .. '">Continue to Dexcom</a></p>'
          .. '</body></html>',
   }
end

--- Dexcom's callback. Exchange the code immediately and store the pair.
local function action_callback(client, cfg, code)
   local tok, err = client:exchangeCode(code)
   if not tok then
      return respond(502, 'Dexcom Adapter',
         '<div class="card">' ..
         note('err', '<strong>Authorization failed.</strong> ' .. esc(err.message)) ..
         '<p><a class="btn ghost" href="?">Back</a></p></div>')
   end
   if tok.simulated then
      return respond(200, 'Dexcom Adapter',
         '<div class="card">' ..
         note('warn', 'Live Mode is off, so no request was sent to Dexcom. ' ..
                      'Turn Live Mode on to complete a real authorization.') ..
         '<p><a class="btn ghost" href="?">Back</a></p></div>')
   end

   local store, serr = DXcfg.openStore(cfg)
   if not store then
      return respond(500, 'Dexcom Adapter',
         '<div class="card">' .. note('err', esc(serr)) .. '</div>')
   end

   -- dataRange also yields the stable per-client user id, which is the only
   -- durable handle on whose readings these are. Best effort: authorization has
   -- already succeeded and must not be discarded if this call fails.
   local userId
   local range = client:dataRange()
   if range and not range.simulated then userId = range.userId end

   local ok, werr = DXcfg.saveToken(store, {
      dexcomUser   = userId,
      accessToken  = tok.accessToken,
      refreshToken = tok.refreshToken,
      expiresAt    = tok.expiresAt,
   })
   if not ok then
      return respond(500, 'Dexcom Adapter',
         '<div class="card">' .. note('err', esc(werr)) .. '</div>')
   end

   linkiir.log.info('Dexcom authorized' .. (userId and (' for user ' .. userId) or ''))
   page_status(client, cfg, nil, DXcfg.loadToken(store),
      '<div class="card">' .. note('ok', '<strong>Authorized.</strong> ' ..
      'The read node will start picking up readings on its next cycle.') .. '</div>')
end

local function action_disconnect(client, cfg)
   local store = DXcfg.openStore(cfg)
   if store then DXcfg.clearToken(store) end
   linkiir.log.info('Dexcom authorization cleared')
   page_status(client, cfg, DXcfg.missing(cfg), nil,
      '<div class="card">' .. note('ok', 'Disconnected. The stored tokens have been removed.')
      .. '</div>')
end

-- --- entry point -----------------------------------------------------------

local function handle(Data)
   local req = linkiir.link.web.request{ data = Data }
   if not req then
      return respond(400, 'Dexcom Adapter',
         '<div class="card">' .. note('err', 'The request could not be parsed.') .. '</div>')
   end

   local client, cfg = DXcfg.fromNodeConfig()
   local params = req.params or {}
   local method = string.upper(req.method or 'GET')

   -- Disconnect is POST-only, so a bookmarked or crawled URL cannot drop a
   -- working authorization.
   if method == 'POST' and (params.disconnect or (req.form or {}).disconnect) then
      return action_disconnect(client, cfg)
   end

   local gaps = DXcfg.missing(cfg)

   -- The callback carries a code. Handle it before anything else, since it
   -- expires in about a minute.
   if params.code and params.code ~= '' then
      if gaps then
         return respond(500, 'Dexcom Adapter', '<div class="card">' ..
            note('err', 'Dexcom called back, but this node is not configured: <code>'
                        .. esc(gaps) .. '</code>') .. '</div>')
      end
      return action_callback(client, cfg, params.code)
   end
   if params.error and params.error ~= '' then
      return respond(400, 'Dexcom Adapter', '<div class="card">' ..
         note('err', 'Dexcom refused the authorization: <code>' .. esc(params.error)
                     .. '</code>') .. '</div>')
   end

   if params.start and params.start ~= '' and not gaps then
      return action_start(client, cfg)
   end

   local tok
   local store = DXcfg.openStore(cfg)
   if store then tok = DXcfg.loadToken(store) end
   page_status(client, cfg, gaps, tok)
end

function main(Data)
   local ok, err = pcall(handle, Data)
   if not ok then
      linkiir.log.error('Dexcom Authorize error: ' .. tostring(err))
      -- Always answer, so a browser never hangs on a script fault.
      pcall(respond, 500, 'Dexcom Adapter',
         '<div class="card">' .. note('err',
            'This node hit an unexpected error. It has been logged.') .. '</div>')
   end
end

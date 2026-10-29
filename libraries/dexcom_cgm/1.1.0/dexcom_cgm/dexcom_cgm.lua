-- dexcom_cgm.lua — public facade for the Dexcom CGM adapter.
--
--   local DX = require 'dexcom_cgm'
--   local client = DX.client{
--      environment = 'sandbox',          -- or 'production'
--      clientId = ..., clientSecret = ..., redirectUri = ...,
--   }
--
--   client:authorizeUrl(state)           -- send the user's browser here
--   client:exchangeCode(code)            -- callback: code -> token pair
--   client:refresh(refreshToken)         -- refresh -> NEW token pair
--   client:setToken(access, expiresAt, refresh)
--   client:dataRange()                   -- userId + the window Dexcom will serve
--   client:egvs{ startDate = , endDate = }
--   client:describe()
--
-- Every method returns result or nil, err. Nothing raises.
--
-- Dexcom is inherently three-legged: a person authorizes access to their own
-- CGM data, so there is no unattended grant available. That makes token
-- lifetime the adapter's main concern, and the reason refresh() returns a new
-- pair the caller must persist.
--
-- This adapter is about connectivity. It fetches readings as Dexcom returns
-- them and does not interpret, reshape or route them: no cursor policy, no
-- overlap window, no mapping into another system's model. Those belong to the
-- integration that uses this adapter.
local http = require 'dexcom_cgm_http'

local M = {}

local Client = {}
Client.__index = Client

local FORM = 'application/x-www-form-urlencoded'

-- Dexcom keeps sandbox and production on separate hosts with separate
-- credentials. Selecting by name avoids an importer pasting a production URL
-- next to sandbox keys, which fails in a way that looks like bad credentials.
M.ENVIRONMENTS = {
   sandbox    = 'https://sandbox-api.dexcom.com',
   production = 'https://api.dexcom.com',
}

-- Dexcom serves a query window of at most 30 days.
M.MAX_WINDOW_DAYS = 30

local function formEncode(pairsList)
   local out = {}
   for _, kv in ipairs(pairsList) do
      out[#out + 1] = kv[1] .. '=' .. linkiir.codec.uri.encode(tostring(kv[2] or ''))
   end
   return table.concat(out, '&')
end

--- Build a client. Nothing is contacted here.
function M.client(T)
   T = T or {}
   local envName = tostring(T.environment or 'sandbox'):lower()
   local base = T.baseUrl
   if base == nil or base == '' then
      base = M.ENVIRONMENTS[envName] or M.ENVIRONMENTS.sandbox
   end

   local conn = {
      environment  = envName,
      baseUrl      = (tostring(base)):gsub('/+$', ''),
      clientId     = T.clientId,
      clientSecret = T.clientSecret,
      redirectUri  = T.redirectUri,
      timeout      = tonumber(T.timeout) or 20,
      verifyTls    = T.verifyTls ~= false,
      live         = T.live == true,
   }
   return setmetatable({ conn = conn, token = nil }, Client)
end

--- One line for a log or a banner.
function Client:describe()
   local bits = { 'Dexcom ' .. self.conn.environment }
   bits[#bits + 1] = (self.conn.live and 'live' or 'Live Mode off')
   if self.token and self.token.expiresAt then
      local left = self.token.expiresAt - os.time()
      bits[#bits + 1] = (left > 0)
         and ('token valid ' .. tostring(math.floor(left / 60)) .. 'm')
         or 'token expired'
   else
      bits[#bits + 1] = 'not authorized'
   end
   return table.concat(bits, ' · ')
end

-- --- authorization ---------------------------------------------------------

--- The URL to send the user's browser to.
function Client:authorizeUrl(state)
   return self.conn.baseUrl .. '/v2/oauth2/login'
      .. '?client_id=' .. linkiir.codec.uri.encode(self.conn.clientId or '')
      .. '&redirect_uri=' .. linkiir.codec.uri.encode(self.conn.redirectUri or '')
      .. '&response_type=code&scope=offline_access'
      .. '&state=' .. linkiir.codec.uri.encode(state or '')
end

local function readTokenBody(json)
   if type(json) ~= 'table' or type(json.access_token) ~= 'string' then
      return nil, { kind = 'decode', status = 200,
                    message = 'token response carried no access_token' }
   end
   return {
      accessToken  = json.access_token,
      refreshToken = json.refresh_token,
      expiresAt    = os.time() + (tonumber(json.expires_in) or 7200),
   }
end

local function tokenRequest(self, body)
   local res, err = http.sendJson{
      method = 'POST',
      url    = self.conn.baseUrl .. '/v2/oauth2/token',
      conn   = self.conn,
      headers = { ['Content-Type'] = FORM, ['Accept'] = 'application/json' },
      body   = body,
   }
   if not res then return nil, err end
   if res.simulated then return { simulated = true } end
   return readTokenBody(res.json)
end

--- Exchange an authorization code for a token pair.
-- The code is single-use and short-lived, so a callback must do this inline.
function Client:exchangeCode(code)
   local tok, err = tokenRequest(self, formEncode{
      { 'client_id',     self.conn.clientId },
      { 'client_secret', self.conn.clientSecret },
      { 'code',          code },
      { 'grant_type',    'authorization_code' },
      { 'redirect_uri',  self.conn.redirectUri },
   })
   if not tok then return nil, err end
   if not tok.simulated then self.token = tok end
   return tok
end

--- Trade a refresh token for a new pair.
-- Persist the result: the pair that comes back replaces the one used.
function Client:refresh(refreshToken)
   local tok, err = tokenRequest(self, formEncode{
      { 'client_id',     self.conn.clientId },
      { 'client_secret', self.conn.clientSecret },
      { 'refresh_token', refreshToken },
      { 'grant_type',    'refresh_token' },
   })
   if not tok then return nil, err end
   if not tok.simulated then self.token = tok end
   return tok
end

--- Install a token pair held elsewhere.
function Client:setToken(accessToken, expiresAt, refreshToken)
   self.token = { accessToken = accessToken, expiresAt = expiresAt,
                  refreshToken = refreshToken }
   return self.token
end

--- Is the access token still usable? Margin so a token cannot expire between
-- the check and the request.
function Client:hasValidToken(marginSeconds)
   local margin = tonumber(marginSeconds) or 300
   return self.token ~= nil
      and type(self.token.accessToken) == 'string'
      and self.token.accessToken ~= ''
      and (self.token.expiresAt or 0) - margin > os.time()
end

-- --- reads -----------------------------------------------------------------

local function authedGet(self, path)
   if not self.token or not self.token.accessToken then
      return nil, { kind = 'auth', status = 0,
                    message = 'no access token: authorize first, or call setToken()' }
   end
   return http.sendJson{
      method = 'GET',
      url    = self.conn.baseUrl .. path,
      conn   = self.conn,
      headers = {
         ['Authorization'] = 'Bearer ' .. tostring(self.token.accessToken),
         ['Accept']        = 'application/json',
      },
   }
end

--- dataRange: the stable per-client user id, plus the window Dexcom actually
-- holds readings for. Worth calling before egvs: asking for a window outside
-- what Dexcom has is a common cause of an empty result that looks like a fault.
function Client:dataRange()
   local res, err = authedGet(self, '/v3/users/self/dataRange')
   if not res then return nil, err end
   if res.simulated then return { simulated = true } end
   local j = res.json or {}
   local egv = j.egvs or {}
   return {
      userId = j.userId,
      start  = (egv.start or {}).systemTime,
      ['end'] = (egv['end'] or {}).systemTime,
      raw    = j,
   }
end

--- egvs: estimated glucose values in [startDate, endDate).
--
-- Times are Dexcom systemTime strings ('YYYY-MM-DDTHH:MM:SS', UTC implied).
-- Returned as Dexcom sends them, newest-first, unmodified.
function Client:egvs(opts)
   opts = opts or {}
   if not opts.startDate or not opts.endDate then
      return nil, { kind = 'client', status = 0,
                    message = 'egvs requires startDate and endDate' }
   end
   local path = '/v3/users/self/egvs'
      .. '?startDate=' .. linkiir.codec.uri.encode(opts.startDate)
      .. '&endDate='   .. linkiir.codec.uri.encode(opts.endDate)
   local res, err = authedGet(self, path)
   if not res then return nil, err end
   if res.simulated then return { simulated = true, records = {} } end
   local j = res.json or {}
   return { records = j.records or j.egvs or {}, raw = j }
end

M.isRetryable = http.isRetryable

return M

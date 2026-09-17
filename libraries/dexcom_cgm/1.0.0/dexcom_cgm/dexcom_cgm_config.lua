-- dexcom_cgm_config.lua — bridge from a node's config to a Dexcom client, plus
-- the small token store the adapter needs.
--
--   local client, cfg = require('dexcom_cgm_config').fromNodeConfig()
--
-- Why a store at all: Dexcom only offers a three-legged grant, so the tokens a
-- person authorized have to outlive the request that obtained them. That is
-- connectivity state, not business state, so it belongs to the adapter. It is
-- one row in one table and nothing else.
local DX = require 'dexcom_cgm'

local M = {}

local function toBool(v, default)
   if v == nil then return default end
   if type(v) == 'boolean' then return v end
   if type(v) == 'string' then return v:lower() == 'true' end
   return default
end

local function blankToNil(v)
   if v == nil then return nil end
   v = tostring(v)
   if v == '' then return nil end
   return v
end

function M.fromNodeConfig()
   local cfg = linkiir.config.node()
   local client = DX.client{
      environment  = blankToNil(cfg['Environment']) or 'sandbox',
      baseUrl      = blankToNil(cfg['Base URL Override']),
      clientId     = cfg['Client ID'],
      clientSecret = cfg['Client Secret'],
      redirectUri  = blankToNil(cfg['Redirect URI']),
      timeout      = tonumber(cfg['Request Timeout']) or 20,
      verifyTls    = toBool(cfg['Verify TLS'], true),
      live         = toBool(cfg['Live Mode'], false),
   }
   return client, cfg
end

--- Report what is still missing, so a node can say so once rather than failing
-- every cycle with a transport error.
function M.missing(cfg)
   local gaps = {}
   if blankToNil(cfg['Client ID']) == nil then gaps[#gaps + 1] = 'Client ID' end
   if blankToNil(cfg['Client Secret']) == nil then gaps[#gaps + 1] = 'Client Secret' end
   if blankToNil(cfg['Redirect URI']) == nil then gaps[#gaps + 1] = 'Redirect URI' end
   if blankToNil(cfg['Token Store Path']) == nil then gaps[#gaps + 1] = 'Token Store Path' end
   if #gaps == 0 then return nil end
   return table.concat(gaps, ', ')
end

-- --- token store -----------------------------------------------------------
-- Single row, id = 1, enforced by a CHECK constraint. One authorization per
-- adapter instance: a second row would mean two sets of tokens for the same
-- connection, and nothing could say which is current.

local SCHEMA = [[
   CREATE TABLE IF NOT EXISTS dexcom_token (
      id            INTEGER PRIMARY KEY CHECK (id = 1),
      dexcom_user   TEXT,
      access_token  TEXT,
      refresh_token TEXT,
      expires_at    INTEGER,
      updated_at    TEXT NOT NULL
   )]]

--- Open the store and make sure the table exists.
function M.openStore(cfg)
   local path = blankToNil(cfg['Token Store Path'])
   if path == nil then
      return nil, 'Token Store Path is not set'
   end
   local conn, err = linkiir.store.open{ driver = linkiir.store.SQLITE, name = path }
   if not conn then
      return nil, 'token store unavailable: ' ..
                  tostring(err and err.message or 'unknown')
   end
   local ok, serr = pcall(function() conn:execute{ sql = SCHEMA } end)
   if not ok then
      return nil, 'could not create the token table: ' .. tostring(serr)
   end
   return conn
end

--- Read the stored tokens, or nil when nothing has been authorized yet.
function M.loadToken(conn)
   local ok, rows = pcall(function()
      return conn:query{ sql = 'SELECT dexcom_user, access_token, refresh_token,' ..
                               ' expires_at FROM dexcom_token WHERE id = 1' }
   end)
   if not ok or type(rows) ~= 'table' or #rows == 0 then return nil end
   local r = rows[1]
   local function col(name)
      local v = r[name]
      if type(v) == 'table' then return v.value end
      return v
   end
   return {
      dexcomUser   = col('dexcom_user'),
      accessToken  = col('access_token'),
      refreshToken = col('refresh_token'),
      expiresAt    = tonumber(col('expires_at')) or 0,
   }
end

--- Write the tokens back, replacing whatever was there.
--
-- Called after every refresh, because Dexcom's refresh returns a new pair and
-- the previous refresh token stops working. Losing this write means the next
-- cycle authenticates with a token Dexcom has already retired.
function M.saveToken(conn, tok)
   local ok, err = pcall(function()
      conn:execute{
         sql = 'INSERT INTO dexcom_token (id, dexcom_user, access_token,' ..
               ' refresh_token, expires_at, updated_at)' ..
               ' VALUES (1, ?, ?, ?, ?, ?)' ..
               ' ON CONFLICT(id) DO UPDATE SET dexcom_user = excluded.dexcom_user,' ..
               ' access_token = excluded.access_token,' ..
               ' refresh_token = excluded.refresh_token,' ..
               ' expires_at = excluded.expires_at,' ..
               ' updated_at = excluded.updated_at',
         params = { tok.dexcomUser, tok.accessToken, tok.refreshToken,
                    math.floor(tonumber(tok.expiresAt) or 0),
                    os.date('!%Y-%m-%dT%H:%M:%SZ') },
      }
   end)
   if not ok then return nil, 'could not save tokens: ' .. tostring(err) end
   return true
end

--- Forget the authorization, so the adapter can be re-connected cleanly.
function M.clearToken(conn)
   pcall(function() conn:execute{ sql = 'DELETE FROM dexcom_token WHERE id = 1' } end)
   return true
end

return M

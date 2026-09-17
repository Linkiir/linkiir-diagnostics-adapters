-- Dexcom Read EGV — Source Custom, on a timer
--
-- Reads estimated glucose values and pushes them downstream. Two jobs only:
-- keep the access token usable, and fetch a window of readings.
--
-- What this node deliberately does NOT do, because it is an adapter and not an
-- integration:
--
--   * no cursor. It reads a trailing window each cycle, sized by config. It does
--     not remember where it got to, because "where we got to" depends on what
--     the downstream does with the data, which an adapter cannot know.
--   * no reshaping. Records go out exactly as Dexcom returned them.
--   * no routing. One message per cycle carrying the window and the records.
--
-- If you need at-least-once delivery with a durable position, that belongs in
-- the workflow consuming this node, where the meaning of "delivered" is known.
local DX    = require 'dexcom_cgm'
local DXcfg = require 'dexcom_cgm_config'

-- Refresh this far ahead of expiry, so a token cannot lapse between the check
-- and the request.
local REFRESH_MARGIN_SECONDS = 300

--- Format an epoch as the Dexcom systemTime shape: no zone, UTC implied.
local function systemTime(epoch)
   return os.date('!%Y-%m-%dT%H:%M:%S', epoch)
end

--- Make sure the client holds a usable access token, refreshing if needed.
--
-- Dexcom's refresh returns a NEW pair and retires the one just used, so the
-- result is persisted before it is relied on. Failing to store it would leave
-- the next cycle authenticating with a token Dexcom has already discarded.
local function ensureToken(client, store)
   local tok = DXcfg.loadToken(store)
   if not tok or not tok.refreshToken or tok.refreshToken == '' then
      return nil, 'not authorized yet: open the Dexcom Authorize node and connect'
   end

   client:setToken(tok.accessToken, tok.expiresAt, tok.refreshToken)
   if client:hasValidToken(REFRESH_MARGIN_SECONDS) then
      return tok
   end

   local fresh, err = client:refresh(tok.refreshToken)
   if not fresh then
      -- A refresh token that Dexcom rejects cannot be recovered from here; the
      -- user has to authorize again. Say that plainly rather than retrying.
      if err.kind == 'auth' or err.kind == 'client' then
         return nil, 'Dexcom rejected the refresh token (' .. err.message ..
                     '). Re-authorize on the Dexcom Authorize node.'
      end
      return nil, 'could not refresh the access token: ' .. err.message
   end
   if fresh.simulated then
      return nil, 'Live Mode is off, so no token refresh was attempted'
   end

   local ok, werr = DXcfg.saveToken(store, {
      dexcomUser   = tok.dexcomUser,
      accessToken  = fresh.accessToken,
      refreshToken = fresh.refreshToken,
      expiresAt    = fresh.expiresAt,
   })
   if not ok then
      -- The new pair is live at Dexcom but unsaved. Surface it loudly: the old
      -- refresh token is already dead, so silence here means a broken adapter
      -- on the next cycle.
      return nil, 'refreshed the token but could not store it (' .. tostring(werr) ..
                  '). The next cycle will fail until this is fixed.'
   end

   linkiir.log.info('Dexcom access token refreshed')
   return DXcfg.loadToken(store)
end

--- Choose the window to ask for.
--
-- Clamped to what Dexcom says it holds, because asking outside that range
-- returns nothing and looks like a fault rather than a configuration choice.
local function chooseWindow(client, lookbackMinutes)
   local now = os.time()
   local startEpoch = now - (lookbackMinutes * 60)

   local range = client:dataRange()
   if range and not range.simulated and range.start and range['end'] then
      -- Dexcom's own bounds win where they are tighter than ours.
      local function toEpoch(s)
         local Y, Mo, D, H, Mi, S = tostring(s):match(
            '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
         if not Y then return nil end
         return os.time{ year = tonumber(Y), month = tonumber(Mo), day = tonumber(D),
                         hour = tonumber(H), min = tonumber(Mi), sec = tonumber(S),
                         isdst = false }
      end
      local availStart, availEnd = toEpoch(range.start), toEpoch(range['end'])
      if availStart and startEpoch < availStart then startEpoch = availStart end
      if availEnd and availEnd < now then now = availEnd end
   end

   if now <= startEpoch then return nil end
   return systemTime(startEpoch), systemTime(now)
end

function main()
   local client, cfg = DXcfg.fromNodeConfig()

   local gaps = DXcfg.missing(cfg)
   if gaps then
      -- Not an error: a freshly imported adapter has no credentials yet. Say so
      -- once per cycle at info level rather than raising and looking broken.
      linkiir.log.info('Dexcom Read: not configured yet (' .. gaps .. ')')
      return
   end

   local store, serr = DXcfg.openStore(cfg)
   if not store then
      error('Dexcom Read: ' .. tostring(serr))
   end

   local tok, terr = ensureToken(client, store)
   if not tok then
      linkiir.log.warn('Dexcom Read: ' .. tostring(terr))
      return
   end

   local lookback = tonumber(cfg['Lookback Minutes']) or 60
   local startDate, endDate = chooseWindow(client, lookback)
   if not startDate then
      linkiir.log.info('Dexcom Read: no window to query yet')
      return
   end

   local result, err = client:egvs{ startDate = startDate, endDate = endDate }
   if not result then
      if DX.isRetryable(err) then
         -- Raise so the runtime backs off and retries on its own schedule.
         error('Dexcom Read: ' .. err.message)
      end
      linkiir.log.warn('Dexcom Read: ' .. err.message)
      return
   end
   if result.simulated then
      linkiir.log.info('Dexcom Read: Live Mode is off, nothing requested')
      return
   end

   local records = result.records or {}
   if #records == 0 then
      linkiir.log.info('Dexcom Read: no readings in ' .. startDate .. ' .. ' .. endDate)
      return
   end

   -- One message per cycle. Chunking belongs downstream, where the queue's
   -- message-size limit and the delivery contract are known.
   linkiir.flow.push{
      data = linkiir.json.serialize{
         type          = 'DEXCOM_EGVS',
         correlationId = linkiir.sys.guid(128),
         createdAt     = os.date('!%Y-%m-%dT%H:%M:%SZ'),
         environment   = cfg['Environment'] or 'sandbox',
         dexcomUserId  = tok.dexcomUser,
         window        = { start = startDate, ['end'] = endDate },
         count         = #records,
         records       = records,
      },
   }
   linkiir.log.info(string.format('Dexcom Read: pushed %d reading(s) for %s .. %s',
      #records, startDate, endDate))
end

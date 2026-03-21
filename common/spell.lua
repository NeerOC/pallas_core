-- Spell cache and wrapper (mirrors Pallas common/spell.lua).
--
-- Usage in behaviors:
--   if Spell.MortalStrike:CastEx(target) then return end
--   if Spell.Bloodthirst:IsReady() then ... end
--
-- The global Spell table uses a metatable so that Spell.XXX automatically
-- resolves to a cached SpellWrapper by converting the key to a spell name
-- (e.g. "MortalStrike" → "Mortal Strike" lookup in known spells).
--
-- ── Casting methods ───────────────────────────────────────────────────
--
--   Cast(target)        Default cast.  Uses cast_spell_at_unit with the
--                        target's obj_ptr (GUID resolved in C++ to avoid Lua
--                        double-precision truncation) and ground=1.  The game
--                        ignores the ground flag for non-AoE spells, so this
--                        is safe for ALL spells and supports off-target
--                        casting (multi-dot, etc.).
--
--   CastEx(target)      Full-check wrapper: IsKnown → throttle → cooldown →
--                        Cast().  Tracks success/fail/throttled per-spell.
--                        This is the primary method behaviors should use.
--
--   CastAtPos(x, y, z)  Ground-targeted cast at an arbitrary world position.
--                        Uses cast_at_pos which hooks the cursor raycast.
--                        Only use for true ground AoE (Explosive Trap, Rain
--                        of Fire, etc.) where no entity target exists.
--
-- ── SpellWrapper ────────────────────────────────────────────────────
local FAIL_BACKOFF = 1.0 -- seconds to suppress a spell after a failed cast
local CAST_THROTTLE = 0.2 -- seconds before the same spell can be re-attempted

local CAST_OPTS_G1 = { ground = 1 }

local RESULT_SUCCESS = 0
local RESULT_THROTTLED = 9
local RESULT_NOT_READY = 10 -- spell system busy (GCD rolling, pending cast)
local RESULT_ON_CD = 11 -- GCD or spell cooldown still active
local RESULT_QUEUED = 12

local SpellWrapper = {}
SpellWrapper.__index = SpellWrapper

function SpellWrapper:new(id, name)
  return setmetatable({
    Id = id or 0,
    Name = name or "",
    IsKnown = id and id > 0 and (game.is_spell_known(id) or false) or false,
    _fail_until = 0,
    _cast_until = 0,
  }, SpellWrapper)
end

function SpellWrapper:IsReady()
  if self.Id == 0 or not self.IsKnown then
    return false
  end
  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then
    return false
  end
  local ok, cd = pcall(game.spell_cooldown, self.Id)
  if not ok or not cd then
    return false
  end
  return not cd.on_cooldown and cd.enabled
end

function SpellWrapper:IsUsable()
  if self.Id == 0 or not self.IsKnown then
    return false
  end
  if game.is_usable_spell then
    local ok, usable, nomana = pcall(game.is_usable_spell, self.Id)
    if ok and usable ~= nil then
      return usable
    end
  end
  return self:IsReady()
end

function SpellWrapper:NoMana()
  if self.Id == 0 then
    return false
  end
  if game.is_usable_spell then
    local ok, usable, nomana = pcall(game.is_usable_spell, self.Id)
    if ok and nomana ~= nil then
      return nomana
    end
  end
  return false
end

function SpellWrapper:GetCooldown()
  if self.Id == 0 then
    return nil
  end
  local ok, cd = pcall(game.spell_cooldown, self.Id)
  return ok and cd or nil
end

function SpellWrapper:InRange(target)
  if not target then
    return true
  end
  -- Prefer the native game function (exact server-side range logic)
  if game.is_spell_in_range and target.obj_ptr then
    local ok, val = pcall(game.is_spell_in_range, self.Id, target.obj_ptr)
    if ok and val ~= nil then
      return val == 1
    end
    -- nil = spell has no range component; fall through to melee/distance check
  end
  local ok, info = pcall(game.get_spell_info, self.Id)
  if not ok or not info then
    return true
  end
  local max_range = info.max_range or 0
  if max_range < 0.1 then
    return Me and Me:InMeleeRange(target) or false
  end
  local d = Me and Me:GetDistance(target) or -1
  if d < 0 then
    return true
  end
  return d <= max_range
end

function SpellWrapper:IsCurrentSpell()
  if self.Id == 0 then
    return false
  end
  local ok, val = pcall(game.is_current_spell, self.Id)
  return ok and val or false
end

function SpellWrapper:IsAutoRepeat()
  if self.Id == 0 then
    return false
  end
  if not game.is_auto_repeat_spell then
    return false
  end
  local ok, val = pcall(game.is_auto_repeat_spell, self.Id)
  return ok and val or false
end

--- Low-level cast.  Uses cast_spell_at_unit(id, obj_ptr, {ground=1}) which
--- resolves the 128-bit GUID from obj_ptr in C++, bypassing Lua double
--- precision issues with 64-bit GUID halves.  Returns the raw integer
--- result code and description string from the C++ layer.
function SpellWrapper:Cast(target)
  if self.Id == 0 then
    return -1, "no spell id"
  end

  if target and target.obj_ptr then
    local ok, c, desc = pcall(game.cast_spell_at_unit, self.Id, target.obj_ptr, CAST_OPTS_G1)
    if ok then
      return c, desc or ""
    end
    return -1, tostring(c)
  end

  -- Self-cast fallback
  if Me and Me.obj_ptr then
    local ok, c, desc = pcall(game.cast_spell_at_unit, self.Id, Me.obj_ptr, CAST_OPTS_G1)
    if ok then
      return c, desc or ""
    end
    return -1, tostring(c)
  end

  return -1, "no target obj_ptr"
end

--- Full-check cast: known → throttle → cooldown → Cast().
---
--- Result handling:
---   Success/Queued (0,12)  → record cast, per-spell throttle, return true
---   Throttled (9)          → pending cast exists, stop ALL casts this tick
---   NotReady/OnCD (10,11)  → GCD rolling or system busy, try again next tick
---   Other failure          → hard fail, per-spell 1s backoff
function SpellWrapper:CastEx(target, skipusable, skipfacing)
  skipusable = skipusable or false
  skipfacing = skipfacing or false
  if self.Id == 0 or not self.IsKnown then
    return false
  end
  if Pallas._tick_throttled then
    return false
  end

  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then
    return false
  end

  if not skipusable then
    local ok, usable = pcall(game.is_usable_spell, self.Id)
    if ok and not usable then
      return false
    end
  end

  -- Cooldown check: avoid calling Cast when the spell is clearly on CD.
  -- is_usable_spell doesn't check cooldowns (e.g. Horn of Winter has no
  -- resource cost → always "usable" even when on CD).
  -- Don't throttle the tick — other spells may still be castable.
  local cok, cd = pcall(game.spell_cooldown, self.Id)
  if cok and cd and cd.on_cooldown then
    return false
  end

  -- Range check: skip if target is out of spell range
  if target and target ~= Me and not self:InRange(target) then
    return false
  end

  -- Facing check: most spells require a 180° frontal cone
  if not skipfacing and target and target ~= Me and Me and Me.obj_ptr and target.obj_ptr then
    local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
    if fok and not facing then
      return false
    end
  end

  local code, desc = self:Cast(target)

  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast = self.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt = target and target.Name or "self"
    Pallas._last_cast_code = code
    Pallas._last_cast_desc = desc or ""
    self._fail_until = 0
    self._cast_until = now + CAST_THROTTLE
    return true
  elseif code == RESULT_THROTTLED then
    Pallas._tick_throttled = true
    return false
  elseif code == RESULT_NOT_READY or code == RESULT_ON_CD then
    -- GCD is rolling or spell system is busy — not a real failure.
    -- Stop trying more spells this tick (GCD applies to everything)
    -- but don't penalise this spell with a backoff.
    Pallas._tick_throttled = true
    return false
  else
    self._fail_until = now + FAIL_BACKOFF
    Pallas._last_fail = self.Name
    Pallas._last_fail_time = now
    Pallas._last_fail_code = code
    Pallas._last_fail_desc = desc or ""
    return false
  end
end

--- Cast at a world position (ground-targeted AoE).
--- Uses cast_at_pos which hooks the cursor raycast to inject coordinates.
---
--- Accepts either raw coordinates or an entity/Unit with a Position field:
---   Spell.ExplosiveTrap:CastAtPos(target)          -- entity
---   Spell.ExplosiveTrap:CastAtPos(10.0, 20.0, 5.0) -- raw x, y, z
function SpellWrapper:CastAtPos(x_or_entity, y, z)
  if self.Id == 0 or not self.IsKnown then
    return false
  end
  if Pallas._tick_throttled then
    return false
  end

  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then
    return false
  end

  -- Usability + cooldown: CastAtPos was missing these entirely, causing
  -- ground-targeted spells (DnD) to call game.cast_at_pos every tick
  -- even when on CD or not usable.
  local uok, usable = pcall(game.is_usable_spell, self.Id)
  if uok and not usable then
    return false
  end
  local cok, cd = pcall(game.spell_cooldown, self.Id)
  if cok and cd and cd.on_cooldown then
    return false
  end

  local x
  if type(x_or_entity) == "table" and x_or_entity.Position then
    local pos = x_or_entity.Position
    x, y, z = pos.x, pos.y, pos.z
  else
    x = x_or_entity
  end

  if not x or not y or not z then
    return false
  end

  local ok, c, d = pcall(game.cast_at_pos, self.Id, x, y, z)
  local code = ok and c or -1
  local desc = ok and (d or "") or tostring(c)

  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast = self.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt = "ground"
    Pallas._last_cast_code = code
    Pallas._last_cast_desc = desc
    self._fail_until = 0
    self._cast_until = now + CAST_THROTTLE
    return true
  elseif code == RESULT_THROTTLED then
    Pallas._tick_throttled = true
    return false
  elseif code == RESULT_NOT_READY or code == RESULT_ON_CD then
    Pallas._tick_throttled = true
    return false
  else
    self._fail_until = now + FAIL_BACKOFF
    Pallas._last_fail = self.Name
    Pallas._last_fail_time = now
    Pallas._last_fail_code = code
    Pallas._last_fail_desc = desc
    return false
  end
end

--- Enhanced interrupt function with advanced targeting and timing options.
--- Scans Combat.Targets for interruptible targets with proper range/facing checks.
--- Uses interrupts.lua data for filtering instead of GUI whitelist.
--- @param options Optional table: {playersOnly=false, customRange=nil, losCheck=true}
--- Returns true if interrupt was cast, false otherwise.
function SpellWrapper:Interrupt(options)
  options = options or {}
  local players_only = options.playersOnly or false
  local custom_range = options.customRange
  local los_check = options.losCheck ~= false -- default true

  -- Check global interrupt mode setting (0=All, 1=Whitelist, 2=None)
  local mode = PallasSettings.PallasInterruptMode or 0
  if mode == 2 then -- None mode
    return false
  end

  -- Check if spell is ready and known
  if not self:IsReady() then
    return false
  end

  -- Get spell range for distance checking
  local spell_range = custom_range
  if not spell_range then
    local ok, info = pcall(game.get_spell_info, self.Id)
    if ok and info and info.max_range and info.max_range > 0 then
      spell_range = info.max_range
    else
      spell_range = 5 -- Default to 5 yards for melee interrupts
    end
  end

  -- Get current target for priority checking
  local current_target = Me and Me.Target or nil
  local current_target_guid = current_target and not current_target.IsDead and current_target.Guid or nil

  -- Load interrupt data from file
  local ok, interrupts = pcall(require, "data.interrupts")
  if not ok then
    -- If interrupts.lua fails to load, fall back to interrupting everything
    interrupts = nil
  end

  -- Scan Combat.Targets for interruptible targets
  local targets = Combat and Combat.Targets or {}
  local best_target = nil
  local best_distance = math.huge

  for _, target in ipairs(targets) do
    if not target or target.IsDead then goto continue end
    
    -- Player-only filtering
    if players_only and not target.is_player then goto continue end
    
    -- Check if target is casting/channeling something interruptible
    local casting = false
    local spell_id = 0
    local confirmed_immune = false
    local cast_info = nil

    -- Check casting status using game functions for accurate data
    if target.obj_ptr then
      local ok_cast, cast = pcall(game.unit_casting_info, target.obj_ptr)
      if ok_cast and cast then
        casting = true
        spell_id = cast.spell_id or 0
        cast_info = cast
        if cast.not_interruptible then confirmed_immune = true end
      else
        local ok_chan, chan = pcall(game.unit_channel_info, target.obj_ptr)
        if ok_chan and chan then
          casting = true
          spell_id = chan.spell_id or 0
          cast_info = chan
          if chan.not_interruptible then confirmed_immune = true end
        end
      end
    end

    -- Fallback to OM data if game functions fail
    if not casting then
      if target.IsCasting then
        casting = true
        spell_id = target.CastingSpellId or 0
      elseif target.IsChanneling then
        casting = true
        spell_id = target.ChannelingSpellId or 0
      end
    end

    -- Skip if not casting or confirmed immune
    if not casting or confirmed_immune then goto continue end

    -- Check if spell is in interrupts.lua (for All and Whitelist modes)
    if interrupts then
      local found_in_interrupts = false
      for _, int_spell_id in pairs(interrupts) do
        if type(int_spell_id) == "number" and int_spell_id == spell_id then
          found_in_interrupts = true
          break
        end
      end
      
      -- For All mode: interrupt everything in interrupts.lua
      -- For Whitelist mode: only interrupt if in interrupts.lua
      if mode == 0 and not found_in_interrupts then goto continue end -- All mode but must be in data file
      if mode == 1 and not found_in_interrupts then goto continue end -- Whitelist mode
    end

    -- Range check: either in spell range OR in melee range (melee range always works)
    local in_range = false
    local distance = Me:GetDistance(target)
    
    -- Always allow interrupts in melee range
    if Me:InMeleeRange(target) then
      in_range = true
    -- Otherwise check spell range
    elseif distance <= spell_range then
      in_range = true
    end

    if not in_range then goto continue end

    -- Line of sight check
    if los_check and Me.obj_ptr and target.obj_ptr then
      local los_ok, los = pcall(game.is_visible, Me.obj_ptr, target.obj_ptr, 0x03)
      if los_ok and not los then goto continue end
    end

    -- Facing check for non-melee interrupts
    if not Me:InMeleeRange(target) and Me.obj_ptr and target.obj_ptr then
      local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
      if fok and not facing then goto continue end
    end

    -- Advanced timing logic (optional enhancement)
    local should_interrupt = true
    if cast_info and PallasSettings.PallasInterruptTiming then
      local now = os.clock() * 1000 -- Convert to milliseconds
      
      if cast_info.cast_start and cast_info.cast_end then
        -- For regular casts: check cast percentage
        local cast_duration = cast_info.cast_end - cast_info.cast_start
        local cast_remaining = cast_info.cast_end - now
        local cast_pct_remaining = (cast_remaining / cast_duration) * 100
        
        local interrupt_pct = PallasSettings.PallasInterruptPercentage or 80
        should_interrupt = cast_pct_remaining <= interrupt_pct
      elseif cast_info.channel_start then
        -- For channeled spells: use random delay (700ms ± 400ms)
        local channel_time = now - cast_info.channel_start
        local random_delay = 700 + (math.random() * 800 - 400) -- 300-1100ms range
        should_interrupt = channel_time > random_delay
      end
    end

    if not should_interrupt then goto continue end

    -- Prioritize current target, then nearest
    local priority = 0
    if current_target_guid and target.Guid == current_target_guid then
      priority = -1000 -- Highest priority for current target
    else
      priority = distance -- Lower distance = higher priority
    end

    if priority < best_distance then
      best_target = target
      best_distance = priority
    end

    ::continue::
  end

  -- If we found a target, try to interrupt
  if best_target then
    return self:CastEx(best_target)
  end

  return false
end

-- ── NullSpell ───────────────────────────────────────────────────────

local NullSpell = SpellWrapper:new(0, "")

-- ── Spell cache (global) ────────────────────────────────────────────

local function fmtSpellKey(name)
  local function tchelper(first, rest)
    return first:upper() .. rest:lower()
  end
  return name:gsub("(%a)([%w_'-]*)", tchelper):gsub("[%s_'%-:(),]+", "")
end

local SpellCache = {}

Spell = setmetatable({
  Cache = SpellCache,
  CacheCount = 0,
  NullSpell = NullSpell,
  Wrapper = SpellWrapper,
}, {
  __index = function(tbl, key)
    if SpellCache[key] then
      return SpellCache[key]
    end
    return NullSpell
  end,
})

function Spell:UpdateCache()
  SpellCache = {}

  -- Player spells
  local ok, spells = pcall(game.known_spells, true)
  if not ok or not spells then
    print("[Pallas] Spell cache: failed to read known spells")
    Spell.Cache = SpellCache
    return
  end

  for _, s in ipairs(spells) do
    if type(s) == "table" and s.name then
      local key = fmtSpellKey(s.name)
      if not SpellCache[key] then
        SpellCache[key] = SpellWrapper:new(s.id, s.name)
      end
    end
  end

  -- Pet spells (e.g. Rabid, Claw, etc.)
  local pok, pet_spells = pcall(game.pet_spells, true)
  if pok and pet_spells then
    for _, s in ipairs(pet_spells) do
      if type(s) == "table" and s.name then
        local key = fmtSpellKey(s.name)
        if not SpellCache[key] then
          SpellCache[key] = SpellWrapper:new(s.id, s.name)
        end
      end
    end
  end

  Spell.Cache = SpellCache
  local count = 0
  for _ in pairs(SpellCache) do
    count = count + 1
  end
  Spell.CacheCount = count
  print(string.format("[Pallas] Cached %d spells", count))
end

--- Check if the Global Cooldown is currently active.
function Spell:IsGCDActive()
  local ok, cd = pcall(game.spell_cooldown, 61304)
  return ok and cd and cd.on_cooldown or false
end

--- Create a SpellWrapper by explicit ID (for spells not in the spell book).
function Spell:ById(id)
  return SpellWrapper:new(id, game.get_spell_name(id) or "")
end

--- Create a SpellWrapper by name lookup.
function Spell:ByName(name)
  local key = fmtSpellKey(name)
  if SpellCache[key] then
    return SpellCache[key]
  end
  local id = game.find_spell_id(name)
  if id then
    return SpellWrapper:new(id, name)
  end
  return NullSpell
end

return Spell

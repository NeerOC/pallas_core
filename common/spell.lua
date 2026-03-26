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

-- ── Dispel type constants ──────────────────────────────────────────
DispelType = {
  Magic   = 1,
  Curse   = 2,
  Disease = 3,
  Poison  = 4,
  Enrage  = 9,
}

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
      if val == 1 then return true end

      -- val == 0: game says out of range.  IsSpellInRange can give false
      -- negatives for short-range / melee spells because it doesn't always
      -- account for combat reach on large models.  Override with the same
      -- formula the game uses in UnitInRange (sub_26FDFE0): sum both
      -- units' CombatReach (CGUnit + 0x11C74) and compare 3D distance.
      if val == 0 and Me then
        local mr = self._max_range
        if not mr then
          local iok, info = pcall(game.get_spell_info, self.Id)
          mr = (iok and info) and (info.max_range or 0) or 0
          self._max_range = mr
        end
        if mr > 0 and mr <= 10 then
          local d = Me:GetDistance(target)
          if d < 0 then return true end
          local my_cr    = Me.CombatReach     or 0
          local their_cr = target.CombatReach  or 0
          return d <= (mr + my_cr + their_cr)
        end
      end

      return false
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
function SpellWrapper:CastEx(target, opts)
  if type(opts) ~= "table" then opts = {} end
  local skipusable = opts.skipUsable or false
  local skipfacing = opts.skipFacing or false
  local skipmoving = opts.skipMoving or false
  local skiplos = opts.skipLos or false
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

  -- Moving check: if spell has cast time and player is moving, return false
  if not skipmoving and Me:IsMoving() then
    local iok, info = pcall(game.get_spell_info, self.Id)
    if iok and info and info.cast_time and info.cast_time > 0 then
      return false
    end
  end

  -- Range check: skip if target is out of spell range.
  if target and target.Guid ~= Me.Guid and not self:InRange(target) then
    return false
  end

  -- Facing check: most spells require a 180° frontal cone
  if not skipfacing and target and target.Guid ~= Me.Guid and Me and Me.obj_ptr and target.obj_ptr then
    local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
    if fok and not facing then
      return false
    end
  end

  -- Line of sight check
  if not skiplos and target and target.Guid ~= Me.Guid and Me and Me.obj_ptr and target.obj_ptr then
    local lok, visible = pcall(game.is_visible, Me.obj_ptr, target.obj_ptr, 0x03)
    if lok and not visible then
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

--- Dispel wrapper: scans friendly or enemy targets for dispellable auras.
---
--- Friendly (remove harmful debuffs from allies):
---   Spell.Cleanse:Dispel(true, {DispelType.Poison, DispelType.Magic})
---
--- Offensive (remove helpful buffs from enemies):
---   Spell.Purge:Dispel(false, {DispelType.Magic})
---
--- @param friendly boolean     true = dispel debuffs on friends, false = purge buffs on enemies
--- @param dispel_types table   Array of DispelType values this spell can remove
--- @param options table|nil    Optional: {maxRange=30, prioritizeTank=true, prioritizeSelf=true}
--- Returns true if a dispel was cast, false otherwise.
function SpellWrapper:Dispel(friendly, dispel_types, options)
  if not dispel_types or #dispel_types == 0 then return false end
  if not self:IsReady() then return false end

  options = options or {}
  local max_range = options.maxRange or 30

  if friendly then
    return self:_DispelFriendly(dispel_types, max_range, options)
  else
    return self:_DispelOffensive(dispel_types, max_range, options)
  end
end

function SpellWrapper:_DispelFriendly(dispel_types, max_range, options)
  local prioritize_tank = options.prioritizeTank ~= false
  local prioritize_self = options.prioritizeSelf ~= false

  local candidates = {}
  local friends = Heal and Heal.PriorityList or {}

  for _, entry in ipairs(friends) do
    local u = entry.Unit
    if u and not u.IsDead and u:HasDispellableDebuff(dispel_types) then
      local d = Me and Me:GetDistance(u) or 999
      if d <= max_range and self:InRange(u) then
        local priority = 100 - u.HealthPct
        if prioritize_tank and u:IsTank() then priority = priority + 50 end
        if prioritize_self and Me and u.Guid == Me.Guid then priority = priority + 30 end
        candidates[#candidates + 1] = { unit = u, priority = priority }
      end
    end
  end

  -- Also check self (Me) if not already in the list
  if Me and not Me.IsDead and Me:HasDispellableDebuff(dispel_types) then
    local dominated = false
    for _, c in ipairs(candidates) do
      if c.unit.Guid == Me.Guid then dominated = true; break end
    end
    if not dominated then
      local priority = 100 - Me.HealthPct
      if prioritize_self then priority = priority + 30 end
      candidates[#candidates + 1] = { unit = Me, priority = priority }
    end
  end

  if #candidates == 0 then return false end

  table.sort(candidates, function(a, b) return a.priority > b.priority end)
  return self:CastEx(candidates[1].unit)
end

function SpellWrapper:_DispelOffensive(dispel_types, max_range, options)
  local targets = Combat and Combat.Targets or {}
  local current_target = Me and Me.Target or nil
  local current_target_guid = current_target and not current_target.IsDead and current_target.Guid or nil

  local best_target = nil
  local best_priority = math.huge

  for _, target in ipairs(targets) do
    if not target or target.IsDead then goto continue end
    if not target:HasDispellableBuff(dispel_types) then goto continue end

    local distance = Me:GetDistance(target)
    if distance > max_range then goto continue end
    if not self:InRange(target) then goto continue end

    -- Prioritize current target, then nearest
    local priority = (current_target_guid and target.Guid == current_target_guid) and -1000 or distance
    if priority < best_priority then
      best_target = target
      best_priority = priority
    end

    ::continue::
  end

  if best_target then
    return self:CastEx(best_target)
  end

  return false
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

  local mode = PallasSettings.PallasInterruptMode or 0
  if mode == 2 then return false end
  if not self:IsReady() then return false end

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
    if players_only and not target.is_player then goto continue end

    local casting = false
    local is_channel = false
    local spell_id = 0
    local confirmed_immune = false
    local cast_info = nil

    if target.CastingInfo then
      local cast, chan = target:CastingInfo()
      if cast then
        casting = true
        spell_id = cast.spell_id or target.CastingSpellId or 0
        cast_info = cast
        if cast.not_interruptible then confirmed_immune = true end
      end
      if chan then
        casting = true
        is_channel = true
        spell_id = chan.spell_id or target.ChannelingSpellId or 0
        cast_info = chan
        if chan.not_interruptible then confirmed_immune = true end
      end
    end

    if not casting then
      if target.IsCasting then
        casting = true
        spell_id = target.CastingSpellId or 0
      elseif target.IsChanneling then
        casting = true
        is_channel = true
        spell_id = target.ChannelingSpellId or 0
      end
    end

    if not casting or confirmed_immune then goto continue end

    -- Whitelist mode: only interrupt spells listed in interrupts.lua
    if mode == 1 and interrupts then
      local found = false
      for _, id in pairs(interrupts) do
        if type(id) == "number" and id == spell_id then found = true; break end
      end
      if not found then goto continue end
    end

    local distance = Me:GetDistance(target)
    if not Me:InMeleeRange(target) and distance > spell_range then goto continue end

    -- Facing check for non-melee interrupts
    if not Me:InMeleeRange(target) and Me.obj_ptr and target.obj_ptr then
      local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
      if fok and not facing then goto continue end
    end

    -- Advanced timing logic
    local should_interrupt = true
    if cast_info and PallasSettings.PallasInterruptTiming then
      if cast_info.start_time and cast_info.end_time and cast_info.remaining then
        local cast_duration = cast_info.end_time - cast_info.start_time
        if cast_duration > 0 then
          if is_channel then
            should_interrupt = true
          else
            local elapsed_pct = ((cast_duration - cast_info.remaining) / cast_duration) * 100
            local interrupt_pct = PallasSettings.PallasInterruptPercentage or 80
            should_interrupt = elapsed_pct >= interrupt_pct
          end
        end
      end
    end

    if not should_interrupt then goto continue end

    -- Prioritize current target, then nearest
    local priority = (current_target_guid and target.Guid == current_target_guid) and -1000 or distance
    if priority < best_distance then
      best_target = target
      best_distance = priority
    end

    ::continue::
  end

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

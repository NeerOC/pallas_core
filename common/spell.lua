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

local FAIL_BACKOFF = 1.0   -- seconds to suppress a spell after a failed cast
local CAST_THROTTLE = 0.2 -- seconds before the same spell can be re-attempted

local CAST_OPTS_G1 = { ground = 1 }

local RESULT_SUCCESS   = 0
local RESULT_THROTTLED = 9
local RESULT_NOT_READY = 10  -- spell system busy (GCD rolling, pending cast)
local RESULT_ON_CD     = 11  -- GCD or spell cooldown still active
local RESULT_QUEUED    = 12

local SpellWrapper = {}
SpellWrapper.__index = SpellWrapper

function SpellWrapper:new(id, name)
  return setmetatable({
    Id      = id   or 0,
    Name    = name or "",
    IsKnown = id and id > 0 and (game.is_spell_known(id) or false) or false,
    _fail_until = 0,
    _cast_until = 0,
  }, SpellWrapper)
end

function SpellWrapper:IsReady()
  if self.Id == 0 or not self.IsKnown then return false end
  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then return false end
  local ok, cd = pcall(game.spell_cooldown, self.Id)
  if not ok or not cd then return false end
  return not cd.on_cooldown and cd.enabled
end

function SpellWrapper:IsUsable()
  return self:IsReady()
end

function SpellWrapper:GetCooldown()
  if self.Id == 0 then return nil end
  local ok, cd = pcall(game.spell_cooldown, self.Id)
  return ok and cd or nil
end

function SpellWrapper:InRange(target)
  if not target then return true end
  local ok, info = pcall(game.get_spell_info, self.Id)
  if not ok or not info then return true end
  local max_range = info.max_range or 0
  if max_range < 0.1 then return Me and Me:InMeleeRange(target) or false end
  local d = Me and Me:GetDistance(target) or -1
  if d < 0 then return true end  -- unknown distance: assume in range, let server reject
  return d <= max_range
end

--- Low-level cast.  Uses cast_spell_at_unit(id, obj_ptr, {ground=1}) which
--- resolves the 128-bit GUID from obj_ptr in C++, bypassing Lua double
--- precision issues with 64-bit GUID halves.  Returns the raw integer
--- result code and description string from the C++ layer.
function SpellWrapper:Cast(target)
  if self.Id == 0 then return -1, "no spell id" end

  if target and target.obj_ptr then
    local ok, c, desc = pcall(game.cast_spell_at_unit, self.Id,
                         target.obj_ptr, CAST_OPTS_G1)
    if ok then return c, desc or "" end
    return -1, tostring(c)
  end

  -- Self-cast fallback
  if Me and Me.obj_ptr then
    local ok, c, desc = pcall(game.cast_spell_at_unit, self.Id,
                         Me.obj_ptr, CAST_OPTS_G1)
    if ok then return c, desc or "" end
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
function SpellWrapper:CastEx(target)
  if self.Id == 0 or not self.IsKnown then return false end
  if Pallas._tick_throttled then return false end

  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then return false end

  local ok, cd = pcall(game.spell_cooldown, self.Id)
  if ok and cd and cd.on_cooldown then return false end

  -- Range check: skip if target is out of spell range
  if target and target ~= Me and not self:InRange(target) then return false end

  -- Facing check: most spells require a 180° frontal cone
  if target and target ~= Me and Me and Me.obj_ptr and target.obj_ptr then
    local fok, facing = pcall(game.is_facing, Me.obj_ptr, target.obj_ptr)
    if fok and not facing then return false end
  end

  local code, desc = self:Cast(target)

  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast      = self.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt  = target and target.Name or "self"
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
    Pallas._last_fail      = self.Name
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
  if self.Id == 0 or not self.IsKnown then return false end
  if Pallas._tick_throttled then return false end

  local now = os.clock()
  if now < self._fail_until or now < self._cast_until then return false end

  local x
  if type(x_or_entity) == "table" and x_or_entity.Position then
    local pos = x_or_entity.Position
    x, y, z = pos.x, pos.y, pos.z
  else
    x = x_or_entity
  end

  if not x or not y or not z then return false end

  local ok, c, d = pcall(game.cast_at_pos, self.Id, x, y, z)
  local code = ok and c or -1
  local desc = ok and (d or "") or tostring(c)

  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast      = self.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt  = "ground"
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
    Pallas._last_fail      = self.Name
    Pallas._last_fail_time = now
    Pallas._last_fail_code = code
    Pallas._last_fail_desc = desc
    return false
  end
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
    if SpellCache[key] then return SpellCache[key] end
    return NullSpell
  end
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
  for _ in pairs(SpellCache) do count = count + 1 end
  Spell.CacheCount = count
  print(string.format("[Pallas] Cached %d spells", count))
end

--- Create a SpellWrapper by explicit ID (for spells not in the spell book).
function Spell:ById(id)
  return SpellWrapper:new(id, game.get_spell_name(id) or "")
end

--- Create a SpellWrapper by name lookup.
function Spell:ByName(name)
  local key = fmtSpellKey(name)
  if SpellCache[key] then return SpellCache[key] end
  local id = game.find_spell_id(name)
  if id then return SpellWrapper:new(id, name) end
  return NullSpell
end

return Spell

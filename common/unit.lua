-- Unit wrapper — provides Pallas-style OOP methods over jmrMoP entity tables.
--
-- Entity tables come from game.objects() and contain:
--   obj_ptr, cgunit, guid, guid_lo, guid_hi, name, position, facing,
--   entry_id, class, unit = { health, max_health, level, ... }

local Unit = {}
Unit.__index = Unit

function Unit:New(entity)
  if not entity then
    return nil
  end
  local u = entity.unit or {}
  local o = setmetatable({
    obj_ptr = entity.obj_ptr,
    cgunit = entity.cgunit,
    Guid = entity.guid or "",
    guid_lo = entity.guid_lo or 0,
    guid_hi = entity.guid_hi or 0,
    Name = entity.name or u.name or "",
    Position = entity.position,
    Facing = entity.facing or 0,
    EntryId = entity.entry_id or 0,
    Class = entity.class or "",

    -- Snapshot scalars (refreshed each tick when the OM is re-read)
    Health = u.health or 0,
    MaxHealth = u.max_health or 1,
    Level = u.level or 0,
    UnitFlags = u.unit_flags or 0,
    Power = u.power or 0,
    MaxPower = u.max_power or 1,
    PowerType = u.power_type or 0,
    Speed = u.speed or 0,
    ClassId = u.class_id or 0,
    Race = u.race or 0,
    IsDead = u.is_dead or false,
    IsPlayer = u.is_player or false,
    InCombat = u.in_combat or false,
    IsMounted = u.is_mounted or false,
    MountDisplayId = u.mount_display_id or 0,
    Classification = u.classification or 0,
    ClassificationName = u.classification_name or "normal",
    IsCasting = u.is_casting or false,
    IsChanneling = u.is_channeling or false,
    CastingSpellId = u.casting_spell_id or 0,
    CastingSpellName = u.casting_spell_name or "",
    ChannelingSpellId = u.channeling_spell_id or 0,
    ChannelingSpellName = u.channeling_spell_name or "",
    Auras = u.auras or {},

    -- Melee range fields (from CGUnit descriptors)
    BoundingRadius = u.bounding_radius or 0,
    CombatReach = u.combat_reach or 0,
    UnitFlags3 = u.unit_flags3 or 0,

    -- Specialization (active player only, from GetSpecialization game func)
    SpecId = u.spec_id or 0, -- 1-based index (1-4), 0 = unknown
    SpecName = u.spec_name or "", -- e.g. "Fury", "Holy", "Restoration"

    -- Dynamic flags (from CGObject descriptor +0xCC)
    DynamicFlags = entity.dynamic_flags or u.dynamic_flags or 0,
    _is_lootable = entity.is_lootable or u.is_lootable or false,
  }, Unit)

  o.HealthPct = o.MaxHealth > 0 and (o.Health / o.MaxHealth * 100) or 0
  o.PowerPct = o.MaxPower > 0 and (o.Power / o.MaxPower * 100) or 0

  -- Combo points (powers[3], type 255)
  local cp = u.powers and u.powers[3]
  o.ComboPoints = (cp and cp.type == 255) and cp.current or 0

  return o
end

function Unit:IsCastingOrChanneling()
  -- OM snapshot is accurate for the local player (uses GetUnitSpellInfo).
  -- For the current target, also query the live game state as a fallback.
  if self.IsCasting or self.IsChanneling then
    return true
  end
  local token = self:_UnitToken()
  if token then
    local ok, cast = pcall(game.unit_casting_info, token)
    if ok and cast then
      return true
    end
    local ok2, chan = pcall(game.unit_channel_info, token)
    if ok2 and chan then
      return true
    end
  end
  return false
end

--- Resolve a WoW unit token for this unit (for game.unit_casting_info etc.).
--- Returns "player" for the local player, "target" for the current target, nil otherwise.
function Unit:_UnitToken()
  if Me and self.Guid == Me.Guid then
    return "player"
  end
  local ok, tgt = pcall(game.target)
  if ok and tgt and tgt.guid == self.Guid then
    return "target"
  end
  return nil
end

function Unit:DeadOrGhost()
  if self.IsDead then
    return true
  end
  local ok, result = pcall(game.unit_dead_or_ghost, self.obj_ptr)
  return ok and result or self.IsDead
end

function Unit:CanAttack(other)
  if not other then
    return false
  end
  local ok, result = pcall(game.unit_can_attack, self.obj_ptr, other.obj_ptr)
  return ok and result or false
end

function Unit:IsAttackable()
  local ok, result = pcall(game.unit_is_attackable, self.obj_ptr)
  return ok and result or false
end

function Unit:IsEnemy(other)
  if other then
    local ok, result = pcall(game.unit_is_enemy, self.obj_ptr, other.obj_ptr)
    return ok and result or false
  end
  local ok, result = pcall(game.unit_is_enemy, self.obj_ptr)
  return ok and result or false
end

function Unit:IsFriend(other)
  if other then
    local ok, result = pcall(game.unit_is_friend, self.obj_ptr, other.obj_ptr)
    return ok and result or false
  end
  local ok, result = pcall(game.unit_is_friend, self.obj_ptr)
  return ok and result or false
end

function Unit:GetReaction(other)
  if not other then
    return 4
  end
  local ok, result = pcall(game.unit_reaction, self.obj_ptr, other.obj_ptr)
  return ok and result or 4
end

function Unit:GetDistance(other)
  if not other then
    return 999
  end

  local sp = self.Position
  local op = other.Position

  -- Live fallback: position is nil out of combat for non-player entities.
  -- Query the archetype data directly which may succeed even when the
  -- snapshot didn't populate position (e.g. freshly entered combat).
  if not sp and self.obj_ptr then
    local ok, x, y, z = pcall(game.entity_position, self.obj_ptr)
    if ok and x then
      sp = { x = x, y = y, z = z }
      self.Position = sp
    end
  end
  if not op and other.obj_ptr then
    local ok, x, y, z = pcall(game.entity_position, other.obj_ptr)
    if ok and x then
      op = { x = x, y = y, z = z }
      other.Position = op
    end
  end

  if not sp or not op then
    return -1
  end
  return game.distance(sp.x, sp.y, sp.z, op.x, op.y, op.z)
end

function Unit:InMeleeRange(other)
  if not other then
    return false
  end

  -- Get distance between units
  local d = self:GetDistance(other)
  if d < 0 then
    return true
  end -- unknown distance: assume in range

  -- Enhanced check using bounding radius when available
  if game.entity_bounds and other.obj_ptr then
    local ok, bounds = pcall(game.entity_bounds, other.obj_ptr)
    if ok and bounds then
      -- Use blood DK approach: 5yd base + target's model half-width
      local melee_range = 5.0 + (bounds.width * 0.5)
      return d <= melee_range
    end
  end

  -- Fallback to standard melee range
  return d <= 5.0
end

function Unit:IsFacing(other, threshold)
  if not other then
    return false
  end
  local ok, result = pcall(game.is_facing, self.obj_ptr, other.obj_ptr, threshold)
  return ok and result or false
end

--- Match helper: returns true if aura entry matches a name or spell_id key.
local function aura_matches(a, key)
  if type(key) == "number" then
    return a.spell_id == key
  end
  return a.name == key
end

function Unit:HasAura(name_or_id)
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      if aura_matches(auras[i], name_or_id) then return true end
    end
    return false
  end
  local ok, result = pcall(game.has_aura, self.obj_ptr, name_or_id)
  return ok and result or false
end

--- Returns the full aura table for a given aura (name or spell_id).
--- Prefers the snapshot (Auras) so caster_name, dispel_type, etc. are available
--- without a live game call. Falls back to game.aura_info for units whose
--- snapshot may be incomplete.
function Unit:GetAura(name_or_id)
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      if aura_matches(auras[i], name_or_id) then return auras[i] end
    end
  end
  local ok, result = pcall(game.aura_info, self.obj_ptr, name_or_id)
  if ok and result then return result end
  return nil
end

--- Returns the aura only if it was cast by the local player.
--- Checks caster_name from the snapshot first, then falls back to
--- game.aura_info's is_from_player flag.
function Unit:GetAuraByMe(name_or_id)
  local auras = self.Auras
  if auras and Me then
    for i = 1, #auras do
      local a = auras[i]
      if aura_matches(a, name_or_id) then
        if a.caster_name and a.caster_name == Me.Name then return a end
        if a.caster_lo and Me.guid_lo and a.caster_lo == Me.guid_lo
            and a.caster_hi == Me.guid_hi then
          return a
        end
      end
    end
  end
  local ok, result = pcall(game.aura_info, self.obj_ptr, name_or_id)
  if ok and result and result.is_from_player then return result end
  return nil
end

--- Returns the aura only if it was cast by a specific unit.
--- @param name_or_id  Aura name or spell_id
--- @param caster      Unit wrapper of the caster to match
function Unit:GetAuraByCaster(name_or_id, caster)
  if not caster then return nil end
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if aura_matches(a, name_or_id) then
        if a.caster_name and caster.Name and a.caster_name == caster.Name then
          return a
        end
        if a.caster_lo and caster.guid_lo
            and a.caster_lo == caster.guid_lo
            and a.caster_hi == caster.guid_hi then
          return a
        end
      end
    end
  end
  return nil
end

function Unit:HasDebuffByMe(name_or_id)
  return self:GetAuraByMe(name_or_id) ~= nil
end

function Unit:HasVisibleAura(name_or_id)
  return self:HasAura(name_or_id)
end

function Unit:GetVisibleAura(name_or_id)
  return self:GetAura(name_or_id)
end

function Unit:HasBuffByMe(name_or_id)
  return self:GetAuraByMe(name_or_id) ~= nil
end

--- Returns all auras on this unit, each with full data:
---   spell_id, name, stacks, duration, expire_time, flags, time_mod,
---   instance_id, dispel_type, dispel_name, caster_lo, caster_hi, caster_name
function Unit:GetAuras()
  return self.Auras or {}
end

--- Returns all auras cast by a specific unit.
function Unit:GetAurasByCaster(caster)
  if not caster then return {} end
  local result = {}
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      local match = false
      if a.caster_name and caster.Name and a.caster_name == caster.Name then
        match = true
      elseif a.caster_lo and caster.guid_lo
          and a.caster_lo == caster.guid_lo
          and a.caster_hi == caster.guid_hi then
        match = true
      end
      if match then result[#result + 1] = a end
    end
  end
  return result
end

--- Returns all auras cast by the local player.
function Unit:GetAurasByMe()
  if not Me then return {} end
  return self:GetAurasByCaster(Me)
end

-- ── Dispel helpers ──────────────────────────────────────────────────
-- dispel_type values: 1=Magic, 2=Curse, 3=Disease, 4=Poison, 9=Enrage

--- Returns true if the unit has any dispellable debuff of the given type(s).
--- @param types number|table  Single dispel_type int or array of ints
function Unit:HasDispellableDebuff(types)
  if type(types) == "number" then types = { types } end
  local set = {}
  for _, t in ipairs(types) do set[t] = true end

  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type and set[a.dispel_type] then
        local flags = a.flags or 0
        local harmful = math.floor(flags / 16) % 2 == 1
        if harmful then return true end
      end
    end
  end
  return false
end

--- Returns the first dispellable debuff matching the given type(s), or nil.
--- @param types number|table  Single dispel_type int or array of ints
--- @return table|nil  aura entry with spell_id, dispel_type, remaining, etc.
function Unit:GetDispellableDebuff(types)
  if type(types) == "number" then types = { types } end
  local set = {}
  for _, t in ipairs(types) do set[t] = true end

  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type and set[a.dispel_type] then
        local flags = a.flags or 0
        local harmful = math.floor(flags / 16) % 2 == 1
        if harmful then return a end
      end
    end
  end
  return nil
end

--- Returns all dispellable debuffs matching the given type(s).
--- @param types number|table  Single dispel_type int or array of ints
function Unit:GetDispellableDebuffs(types)
  if type(types) == "number" then types = { types } end
  local set = {}
  for _, t in ipairs(types) do set[t] = true end

  local result = {}
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type and set[a.dispel_type] then
        local flags = a.flags or 0
        local harmful = math.floor(flags / 16) % 2 == 1
        if harmful then result[#result + 1] = a end
      end
    end
  end
  return result
end

--- Returns true if the unit has any dispellable buff (helpful aura) of the given type(s).
--- Used for offensive dispelling (purging enemy buffs).
--- @param types number|table  Single dispel_type int or array of ints
function Unit:HasDispellableBuff(types)
  if type(types) == "number" then types = { types } end
  local set = {}
  for _, t in ipairs(types) do set[t] = true end

  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type and set[a.dispel_type] then
        local flags = a.flags or 0
        local helpful = math.floor(flags / 256) % 2 == 1
        if helpful then return true end
      end
    end
  end
  return false
end

--- Returns true if the unit has any stealable (Magic) buff.
function Unit:HasStealableBuff()
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type == 1 then
        local flags = a.flags or 0
        local helpful = math.floor(flags / 256) % 2 == 1
        if helpful then return true end
      end
    end
  end
  return false
end

--- Returns the first stealable (Magic) buff, or nil.
function Unit:GetStealableBuff()
  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      local a = auras[i]
      if a.dispel_type == 1 then
        local flags = a.flags or 0
        local helpful = math.floor(flags / 256) % 2 == 1
        if helpful then return a end
      end
    end
  end
  return nil
end

function Unit:Role()
  local ok, result = pcall(game.unit_role, self.obj_ptr)
  return ok and result or "NONE"
end

function Unit:IsTank()
  local ok, result = pcall(game.unit_is_tank, self.obj_ptr)
  return ok and result or false
end

function Unit:IsHealer()
  local ok, result = pcall(game.unit_is_healer, self.obj_ptr)
  return ok and result or false
end

function Unit:IsDPS()
  local ok, result = pcall(game.unit_is_dps, self.obj_ptr)
  return ok and result or false
end

function Unit:IsMoving()
  local ok, moving = pcall(game.unit_is_moving)
  if ok then return moving end
  return false
end

function Unit:IsElite()
  local c = self.Classification
  return c == 1 or c == 2 or c == 3
end

function Unit:IsRare()
  local c = self.Classification
  return c == 2 or c == 4
end

function Unit:IsWorldBoss()
  return self.Classification == 3
end

--- True if the unit is boss-level (game level == -1 / skull).
--- Falls back to classification == 3 (worldboss) if is_boss field is unavailable.
function Unit:IsBoss()
  local data = self._data
  if data and data.is_boss ~= nil then
    return data.is_boss
  end
  return self.Classification == 3
end

function Unit:IsLootable()
  return self._is_lootable
end

--- Check if this unit is interruptible (casting or channeling a kickable spell).
--- Uses the live game state via unit_casting_info / unit_channel_info for
--- the player and current target. Falls back to the OM snapshot for other units.
function Unit:IsInterruptible()
  if not self:IsCastingOrChanneling() then
    return false
  end
  local token = self:_UnitToken()
  if token then
    local ok, cast = pcall(game.unit_casting_info, token)
    if ok and cast then
      return not cast.not_interruptible
    end
    local ok2, chan = pcall(game.unit_channel_info, token)
    if ok2 and chan then
      return not chan.not_interruptible
    end
  end
  return self.IsCasting or self.IsChanneling
end

function Unit:CastingInfo()
  if not self.obj_ptr then
    return nil, nil
  end
  -- Prefer live data for player/target
  local token = self:_UnitToken()
  if token then
    local ok, cast = pcall(game.unit_casting_info, token)
    local ok2, chan = pcall(game.unit_channel_info, token)
    return ok and cast or nil, ok2 and chan or nil
  end
  -- Fallback to OM snapshot
  local cast = nil
  local chan = nil
  if self.IsCasting then
    cast = { spell_id = self.CastingSpellId, spell_name = self.CastingSpellName }
  end
  if self.IsChanneling then
    chan = { spell_id = self.ChannelingSpellId, spell_name = self.ChannelingSpellName }
  end
  return cast, chan
end

-- Resolve the unit's target (returns a Unit wrapper or nil).
-- For the local player, uses game.target() to get the GUID/obj_ptr.
-- For any other unit, uses game.unit_target() to read the target from
-- the CGUnit descriptor.  In both cases the result is looked up in the
-- OM entity cache so the returned Unit has full data (position, auras, etc.).
function Unit:GetTarget()
  local tgt
  if Me and self.Guid == Me.Guid then
    local ok, t = pcall(game.target)
    if not ok or not t or not t.obj_ptr then
      return nil
    end
    tgt = t
  else
    local ok, t = pcall(game.unit_target, self.obj_ptr)
    if not ok or not t or not t.obj_ptr then
      return nil
    end
    tgt = t
  end

  local entities = Pallas and Pallas._entity_cache or {}
  for _, e in ipairs(entities) do
    if e.obj_ptr == tgt.obj_ptr then
      return Unit:New(e)
    end
  end

  return Unit:New(tgt)
end

-- Check if this unit is a valid target
function Unit:validTarget()
  if self.IsDead or self:DeadOrGhost() then
    return false
  end

  if Me and Me.CanAttack and not Me:CanAttack(self) then
    return false
  end

  return true
end

-- Check if a unit is in combat with any party member (excluding the player)
function Unit:isUnitInCombatWithParty(unit)
  if not unit or not unit.InCombat then
    return false
  end
  
  local target = unit:GetTarget()
  if not target then
    return false
  end
  
  -- Check if unit's target is any party member (excluding player)
  local party = Party and Party.currentParty
  if not party or not party.members then
    return false
  end
  
  for _, member in ipairs(party.members) do
    if member and member.guid and not member.guid.equals(Me.guid) and member.guid.equals(target.Guid) then
      return true
    end
  end
  
  return false
end

-- Get all attackable monsters within specified range of this unit
function Unit:getUnitsAroundUnit(range)
  local units = {}
  if not range or range <= 0 then
    return units
  end
  
  -- Loop through entity cache similar to Combat:CollectTargets()
  local entities = Pallas and Pallas._entity_cache or {}
  
  for _, e in ipairs(entities) do
    local cls = e.class
    if cls ~= "Unit" and cls ~= "Player" then goto skip end
    
    local eu = e.unit
    if not eu then goto skip end
    if eu.is_dead then goto skip end
    if eu.health and eu.health <= 0 then goto skip end
    
    -- Check if unit is attackable
    if not game.unit_can_attack(e.obj_ptr) then goto skip end
    
    -- Skip self
    if e.guid == self.Guid then goto skip end
    
    -- Create Unit wrapper and check distance
    local unit = Unit:New(e)
    if unit and unit:IsAttackable() and not unit:DeadOrGhost() then
      if self:GetDistance(unit) <= range then
        units[#units + 1] = unit
      end
    end
    
    ::skip::
  end
  
  return units
end

-- Alias used by Pallas-style code: unit.Target (property, not method).
-- Set by the refresh loop on Me only.
Unit.Target = nil

return Unit

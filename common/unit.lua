-- Unit wrapper — provides Pallas-style OOP methods over jmrMoP entity tables.
--
-- Entity tables come from game.objects() and contain:
--   obj_ptr, cgunit, guid, guid_lo, guid_hi, name, position, facing,
--   entry_id, class, unit = { health, max_health, level, ... }

local bit = require("bit")

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
    CastStart = u.cast_start or 0,
    CastEnd = u.cast_end or 0,
    ChannelingSpellId = u.channeling_spell_id or 0,
    ChannelingSpellName = u.channeling_spell_name or "",
    ChannelStart = u.channel_start or 0,
    ChannelEnd = u.channel_end or 0,
    NotInterruptible = u.not_interruptible or false,
    CastTargetLo = u.cast_target_lo or 0,
    CastTargetHi = u.cast_target_hi or 0,
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

  -- Combo points (powers[3])
  local cp = u.powers and u.powers[3]
  o.ComboPoints = cp and cp.current or 0

  -- Chi (powers[5])
  local chi = u.powers and u.powers[5]
  o.Chi = chi and chi.current or 0
  o.MaxChi = chi and chi.max or 0


  return o
end

--- Returns the Unit that this unit's current cast is targeting, or nil.
function Unit:GetCastTarget()
  if self.CastTargetLo == 0 and self.CastTargetHi == 0 then return nil end
  local entities = game.objects()
  if not entities then return nil end
  for _, e in ipairs(entities) do
    if e.guid_lo == self.CastTargetLo and e.guid_hi == self.CastTargetHi then
      return Unit:New(e)
    end
  end
  return nil
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
--- Returns "player", "target", "focus", or the obj_ptr (which C++ resolves).
function Unit:_UnitToken()
  if Me and self.Guid == Me.Guid then
    return "player"
  end
  if self.obj_ptr then
    return self.obj_ptr
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

function Unit:_ResolvePos()
  local p = self.Position
  if not p and self.obj_ptr then
    local ok, x, y, z = pcall(game.entity_position, self.obj_ptr)
    if ok and x then
      p = { x = x, y = y, z = z }
      self.Position = p
    end
  end
  return p
end

function Unit:GetDistance(other)
  if not other then return 999 end
  local sp = self:_ResolvePos()
  local op = other._ResolvePos and other:_ResolvePos() or other.Position
  if not sp or not op then return -1 end
  return game.distance(sp.x, sp.y, sp.z, op.x, op.y, op.z)
end

function Unit:GetDistance2D(other)
  if not other then return 999 end
  local sp = self:_ResolvePos()
  local op = other._ResolvePos and other:_ResolvePos() or other.Position
  if not sp or not op then return -1 end
  local dx = sp.x - op.x
  local dy = sp.y - op.y
  return math.sqrt(dx * dx + dy * dy)
end

local MELEE_LEEWAY = 4.0 / 3.0 -- 1.3333 yd base melee bonus
local MELEE_MIN    = 5.0        -- server enforces a 5 yd floor

function Unit:InMeleeRange(other)
  if not other then return false end

  -- WoW melee range = max(5, attacker.CombatReach + target.CombatReach + 4/3)
  -- Game uses 3D distance (confirmed via RE of sub_26FDFE0 UnitInRange).
  local d = self:GetDistance(other)
  if d < 0 then return true end

  local my_cr    = self.CombatReach  or 0
  local their_cr = other.CombatReach or 0
  local range    = my_cr + their_cr + MELEE_LEEWAY
  if range < MELEE_MIN then range = MELEE_MIN end

  return d <= range
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
--- Scans all aura slots via game.scan_aura_entry and matches caster guid
--- against the local player's guid to ensure ownership.
function Unit:GetAuraByMe(name_or_id)
  if not Me then return nil end
  local ptr = self.obj_ptr
  local my_lo = Me.guid_lo
  local my_hi = Me.guid_hi
  local count = #(self.Auras or {})
  for i = 0, count - 1 do
    local ok, a = pcall(game.scan_aura_entry, ptr, i)
    if not ok or not a then break end
    if aura_matches(a, name_or_id) and a.caster_lo == my_lo and a.caster_hi == my_hi then
      return a
    end
  end
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
--- @param whitelist table|nil  If provided, only match auras whose spell_id is in this set
function Unit:HasDispellableDebuff(types, whitelist)
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
        if harmful then
          if not whitelist or (a.spell_id and whitelist[a.spell_id]) then
            return true
          end
        end
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
--- @param whitelist table|nil  If provided, only match auras whose spell_id is in this set
function Unit:HasDispellableBuff(types, whitelist)
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
        if helpful then
          if not whitelist or (a.spell_id and whitelist[a.spell_id]) then
            return true
          end
        end
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
  local ok, moving = pcall(game.unit_is_moving, self.obj_ptr)
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

-- TrinityCore UNIT_FIELD_FLAGS — confirmed via dead skinnable beast showing
-- 0x04008000 (bits 15 + 26 = UNK_15 + SKINNABLE), matching expected state.
local UFLAG_IMMUNE_TO_PC  = 0x00000100  -- bit 8
local UFLAG_IMMUNE_TO_NPC = 0x00000200  -- bit 9
local UFLAG_IMMUNE        = 0x80000000  -- bit 31

local IMMUNE_AURAS = {
  [642]   = true,  -- Divine Shield
  [45438] = true,  -- Ice Block
  [19263] = true,  -- Deterrence
  [33786] = true,  -- Cyclone
  [710]   = true,  -- Banish
}

function Unit:IsImmune()
  local flags = self.UnitFlags or 0
  if bit.band(flags, UFLAG_IMMUNE_TO_PC + UFLAG_IMMUNE_TO_NPC + UFLAG_IMMUNE) ~= 0 then
    return true
  end

  local auras = self.Auras
  if auras then
    for i = 1, #auras do
      if IMMUNE_AURAS[auras[i].spell_id] then return true end
    end
  end
  return false
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

-- ── Crowd Control (UNIT_FIELD_FLAGS bit checks) ──
-- Works on ANY visible unit (enemies, party members, self).
-- C_LossOfControl only tracks the local player; unit flags are universal.

local FLAG_SILENCED = 0x00002000
local FLAG_PACIFIED = 0x00020000
local FLAG_STUNNED  = 0x00040000
local FLAG_DISARMED = 0x00200000
local FLAG_CONFUSED = 0x00400000
local FLAG_FLEEING  = 0x00800000
local FLAG_CC_ANY   = bit.bor(FLAG_SILENCED, FLAG_PACIFIED, FLAG_STUNNED,
                              FLAG_DISARMED, FLAG_CONFUSED, FLAG_FLEEING)

function Unit:IsStunned()
  return bit.band(self.UnitFlags, FLAG_STUNNED) ~= 0
end

function Unit:IsSilenced()
  return bit.band(self.UnitFlags, FLAG_SILENCED) ~= 0
end

function Unit:IsPacified()
  return bit.band(self.UnitFlags, FLAG_PACIFIED) ~= 0
end

function Unit:IsDisarmed()
  return bit.band(self.UnitFlags, FLAG_DISARMED) ~= 0
end

function Unit:IsFeared()
  return bit.band(self.UnitFlags, FLAG_FLEEING) ~= 0
end

function Unit:IsConfused()
  return bit.band(self.UnitFlags, FLAG_CONFUSED) ~= 0
end

--- Returns true if the unit has ANY CC flag active (stun/silence/fear/confuse/disarm/pacify).
function Unit:IsCrowdControlled()
  return bit.band(self.UnitFlags, FLAG_CC_ANY) ~= 0
end

--- Returns true if the unit is incapacitated (stunned, feared, or confused).
function Unit:IsIncapacitated()
  return bit.band(self.UnitFlags, bit.bor(FLAG_STUNNED, FLAG_CONFUSED, FLAG_FLEEING)) ~= 0
end

--- Returns true if the unit has any disabling CC (stun/silence/fear/confuse/pacify), excluding disarm and root.
function Unit:IsDisabled()
  return bit.band(self.UnitFlags, bit.bor(FLAG_STUNNED, FLAG_SILENCED, FLAG_PACIFIED, FLAG_CONFUSED, FLAG_FLEEING)) ~= 0
end

-- ── Speed / Slow / Root ──
-- Uses game.unit_speed() for dynamic per-unit speed (reflects buffs, slows, mounts).

local BASE_RUN_SPEED = 7.0

--- Returns currentSpeed, runSpeed, flightSpeed, swimSpeed (yd/s).
function Unit:GetSpeed()
  if not self.obj_ptr then return 0, 0, 0, 0 end
  local ok, cur, run, flight, swim = pcall(game.unit_speed, self.obj_ptr)
  if not ok then return 0, 0, 0, 0 end
  return cur, run, flight, swim
end

--- Returns true if the unit's run speed is below base (7.0 yd/s).
function Unit:IsSlowed()
  local _, run = self:GetSpeed()
  return run > 0 and run < BASE_RUN_SPEED
end

--- Returns the slow percentage (0-100). 0 = not slowed.
function Unit:SlowPercent()
  local _, run = self:GetSpeed()
  if run <= 0 or run >= BASE_RUN_SPEED then return 0 end
  return (1 - run / BASE_RUN_SPEED) * 100
end

--- Returns true if the unit is rooted (runSpeed == 0 but not stunned/feared/confused).
function Unit:IsRooted()
  local _, run = self:GetSpeed()
  if run > 0 then return false end
  return not self:IsStunned() and not self:IsFeared() and not self:IsConfused()
end

-- ── Loss of Control (local player only) ──
-- C_LossOfControl tracks detailed CC info (spell, duration, school lockout)
-- but only for the local player. Use the flag-based methods above for enemies.

function Unit:LossOfControlCount()
  if not self.obj_ptr then return 0 end
  local ok, count = pcall(game.loss_of_control_count, self.obj_ptr)
  return ok and count or 0
end

function Unit:GetLossOfControlEvents()
  if not self.obj_ptr then return {} end
  local ok, count = pcall(game.loss_of_control_count, self.obj_ptr)
  if not ok or not count or count == 0 then return {} end
  local events = {}
  for i = 1, count do
    local ok2, info = pcall(game.loss_of_control_info, self.obj_ptr, i)
    if ok2 and info then
      events[#events + 1] = info
    end
  end
  return events
end

function Unit:IsSchoolLocked()
  local events = self:GetLossOfControlEvents()
  for _, ev in ipairs(events) do
    if ev.locType == "SCHOOL_INTERRUPT" then return true, ev.lockoutSchool end
  end
  return false, 0
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
    if member and member.guid and member.guid ~= Me.Guid and member.guid == target.Guid then
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

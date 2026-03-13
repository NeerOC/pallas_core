-- Unit wrapper — provides Pallas-style OOP methods over jmrMoP entity tables.
--
-- Entity tables come from game.objects() and contain:
--   obj_ptr, cgunit, guid, guid_lo, guid_hi, name, position, facing,
--   entry_id, class, unit = { health, max_health, level, ... }

local Unit = {}
Unit.__index = Unit

function Unit:New(entity)
  if not entity then return nil end
  local u = entity.unit or {}
  local o = setmetatable({
    obj_ptr  = entity.obj_ptr,
    cgunit   = entity.cgunit,
    Guid     = entity.guid   or "",
    guid_lo  = entity.guid_lo or 0,
    guid_hi  = entity.guid_hi or 0,
    Name     = entity.name or u.name or "",
    Position = entity.position,
    Facing   = entity.facing or 0,
    EntryId  = entity.entry_id or 0,
    Class    = entity.class or "",

    -- Snapshot scalars (refreshed each tick when the OM is re-read)
    Health       = u.health or 0,
    MaxHealth    = u.max_health or 1,
    Level        = u.level or 0,
    UnitFlags    = u.unit_flags or 0,
    Power        = u.power or 0,
    MaxPower     = u.max_power or 1,
    PowerType    = u.power_type or 0,
    Speed        = u.speed or 0,
    ClassId      = u.class_id or 0,
    Race         = u.race or 0,
    IsDead       = u.is_dead or false,
    IsPlayer     = u.is_player or false,
    InCombat     = u.in_combat or false,
    IsMounted    = u.is_mounted or false,
    IsCasting       = u.is_casting or false,
    IsChanneling    = u.is_channeling or false,
    CastingSpellId  = u.casting_spell_id or 0,
    CastingSpellName= u.casting_spell_name or "",
    Auras           = u.auras or {},

    -- Specialization (active player only, from GetSpecialization game func)
    SpecId   = u.spec_id or 0,     -- 1-based index (1-4), 0 = unknown
    SpecName = u.spec_name or "",   -- e.g. "Fury", "Holy", "Restoration"

    -- Dynamic flags (from CGObject descriptor +0xCC)
    DynamicFlags = entity.dynamic_flags or u.dynamic_flags or 0,
    _is_lootable = entity.is_lootable or u.is_lootable or false,
  }, Unit)

  o.HealthPct = o.MaxHealth > 0 and (o.Health / o.MaxHealth * 100) or 0
  o.PowerPct  = o.MaxPower  > 0 and (o.Power  / o.MaxPower  * 100) or 0
  return o
end

function Unit:IsCastingOrChanneling()
  return self.IsCasting or self.IsChanneling
end

function Unit:DeadOrGhost()
  if self.IsDead then return true end
  local ok, result = pcall(game.unit_dead_or_ghost, self.obj_ptr)
  return ok and result or self.IsDead
end

function Unit:CanAttack(other)
  if not other then return false end
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
  if not other then return 4 end
  local ok, result = pcall(game.unit_reaction, self.obj_ptr, other.obj_ptr)
  return ok and result or 4
end

function Unit:GetDistance(other)
  if not other then return 999 end

  local sp = self.Position
  local op = other.Position

  -- Live fallback: position is nil out of combat for non-player entities.
  -- Query the archetype data directly which may succeed even when the
  -- snapshot didn't populate position (e.g. freshly entered combat).
  if not sp and self.obj_ptr then
    local ok, x, y, z = pcall(game.entity_position, self.obj_ptr)
    if ok and x then sp = { x = x, y = y, z = z }; self.Position = sp end
  end
  if not op and other.obj_ptr then
    local ok, x, y, z = pcall(game.entity_position, other.obj_ptr)
    if ok and x then op = { x = x, y = y, z = z }; other.Position = op end
  end

  if not sp or not op then return -1 end
  return game.distance(sp.x, sp.y, sp.z, op.x, op.y, op.z)
end

function Unit:InMeleeRange(other)
  local d = self:GetDistance(other)
  if d < 0 then return true end  -- unknown distance: assume in range
  return d <= 5.5
end

function Unit:IsFacing(other, threshold)
  if not other then return false end
  local ok, result = pcall(game.is_facing, self.obj_ptr, other.obj_ptr, threshold)
  return ok and result or false
end

function Unit:HasAura(name_or_id)
  local ok, result = pcall(game.has_aura, self.obj_ptr, name_or_id)
  return ok and result or false
end

function Unit:GetAura(name_or_id)
  local ok, result = pcall(game.aura_info, self.obj_ptr, name_or_id)
  if ok and result then return result end
  return nil
end

function Unit:GetAuraByMe(name_or_id)
  local aura = self:GetAura(name_or_id)
  if not aura then return nil end
  -- game.aura_info returns is_from_player (bool), not a GUID
  if aura.is_from_player then return aura end
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
  return self.Speed > 0.1
end

function Unit:IsLootable()
  return self._is_lootable
end

--- Check if this unit is interruptible.  For the player's current target,
--- we can query the live cast state via game.unit_casting_info("target").
--- For other units we fall back to the snapshot is_casting flag (no
--- not_interruptible data is available from the OM snapshot).
function Unit:IsInterruptible()
  if not self.IsCasting then return false end
  -- If this unit happens to be our current target, use the rich cast info
  local tgt = game.target()
  if tgt and tgt.guid == self.Guid then
    local ok, cast = pcall(game.unit_casting_info, "target")
    if ok and cast then
      return not cast.not_interruptible
    end
  end
  return true
end

function Unit:CastingInfo()
  if not self.obj_ptr then return nil, nil end
  local cast = nil
  local chan = nil
  if self.IsCasting then
    cast = { spell_id = self.CastingSpellId, spell_name = self.CastingSpellName }
  end
  if self.IsChanneling then chan = true end
  return cast, chan
end

-- Resolve the unit's target (returns a Unit wrapper or nil).
-- For the local player, uses game.target() to get the GUID/obj_ptr,
-- then looks up the full entity from the OM cache so we get position,
-- facing, auras, health, etc.  Falls back to the bare target table
-- if the entity isn't in the cache (e.g. cross-phase).
function Unit:GetTarget()
  if Me and self.Guid == Me.Guid then
    local ok, tgt = pcall(game.target)
    if not ok or not tgt or not tgt.obj_ptr then return nil end

    -- Look up full entity data from the OM snapshot
    local entities = Pallas and Pallas._entity_cache or {}
    for _, e in ipairs(entities) do
      if e.obj_ptr == tgt.obj_ptr then
        return Unit:New(e)
      end
    end

    return Unit:New(tgt)
  end
  return nil
end

-- Alias used by Pallas-style code: unit.Target (property, not method).
-- Set by the refresh loop on Me only.
Unit.Target = nil

return Unit

-- Combat targeting system (mirrors Pallas system/combat.lua).
--
-- Collects enemy units each tick, filters, and ranks them by priority.
-- Behaviors read Combat.BestTarget and Combat.EnemiesInMeleeRange.

Combat                     = Combat or Targeting:New()

Combat.BestTarget          = nil
Combat.EnemiesInMeleeRange = 0
Combat.Enemies             = 0

function Combat:Update()
  Targeting.Update(self)
end

function Combat:Reset()
  self.BestTarget          = nil
  self.EnemiesInMeleeRange = 0
  self.Enemies             = 0
  self.Targets             = {}
end

function Combat:WantToRun()
  if not Behavior:HasBehavior(BehaviorType.Combat) then return false end
  if not Me then return false end
  if Me.IsMounted then return false end
  return PallasSettings.PallasAttackOOC or Me.InCombat
end

function Combat:CollectTargets()
  if not Me.InCombat and PallasSettings.PallasAttackOOC then
    local tgt = Me.Target
    if tgt and not tgt.IsDead and Me:CanAttack(tgt) then
      self.Targets[#self.Targets + 1] = tgt
    end
    return
  end

  -- Pre-filter on raw entity data to avoid wrapping hundreds of irrelevant entities.
  local entities = Pallas._entity_cache or {}
  local mx, my, mz
  if Me.Position then
    mx, my, mz = Me.Position.x, Me.Position.y, Me.Position.z
  end

  for _, e in ipairs(entities) do
    local cls = e.class
    if cls ~= "Unit" and cls ~= "Player" then goto skip end

    local eu = e.unit
    if not eu then goto skip end
    if eu.is_dead then goto skip end
    if eu.health and eu.health <= 0 then goto skip end
    if not eu.in_combat and not PallasSettings.PallasAttackOOC then goto skip end
    if not Me:CanAttack(eu) then goto skip end

    -- Cheap squared-distance check (40yd = 1600 sq)
    if mx and e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      if dx * dx + dy * dy + dz * dz > 1600 then goto skip end
    end

    self.Targets[#self.Targets + 1] = Unit:New(e)
    ::skip::
  end
end

-- Traceline flags: terrain (0x01) + buildings/WMO (0x02).
-- Excludes models/doodads so creature geometry doesn't block the check.
local LOS_FLAGS = 0x03

function Combat:ExclusionFilter()
  local require_threat = not PallasSettings.PallasAttackOOC
  local my_tgt_guid = Me.Target and Me.Target.Guid or ""
  local keep = {}
  for _, u in ipairs(self.Targets) do
    if not u or not Me:CanAttack(u) then goto skip_ex end

    -- Threat gate: filter mobs that are in combat with something else, not us.
    -- Exempt the player's current target when "Always attack current target" is on.
    local is_my_target = u.Guid == my_tgt_guid
    if require_threat and not (is_my_target and PallasSettings.PallasAttackTarget) then
      local tok, tanking = pcall(game.unit_threat, u.obj_ptr)
      if not tok or tanking == nil then goto skip_ex end
    end

    -- Geometry-only LOS: terrain + buildings, no model collision
    do
      local ok, vis = pcall(game.is_visible, Me.obj_ptr, u.obj_ptr, LOS_FLAGS)
      if ok and not vis then goto skip_ex end
    end

    keep[#keep + 1] = u
    ::skip_ex::
  end
  self.Targets = keep
end

function Combat:InclusionFilter()
  if not PallasSettings.PallasAttackTarget then return end

  local tgt = Me.Target
  if not tgt then return end

  for _, u in ipairs(self.Targets) do
    if u.Guid == tgt.Guid then return end
  end

  if tgt.IsDead or tgt.Health <= 0 or not Me:CanAttack(tgt) then return end
  self.Targets[#self.Targets + 1] = tgt
end

function Combat:WeighFilter()
  local priority_list = {}
  local tgt_guid = Me.Target and Me.Target.Guid or ""
  for _, u in ipairs(self.Targets) do
    local priority = 0
    self.Enemies = self.Enemies + 1

    if Me:InMeleeRange(u) then
      self.EnemiesInMeleeRange = self.EnemiesInMeleeRange + 1
    end

    if tgt_guid == u.Guid then
      priority = priority + 50
    end

    priority_list[#priority_list + 1] = { Unit = u, Priority = priority }
  end

  table.sort(priority_list, function(a, b) return a.Priority > b.Priority end)
  if #priority_list == 0 then return end

  self.BestTarget = priority_list[1].Unit
end

function Combat:GetEnemiesWithinDistance(dist)
  local count = 0
  for _, u in ipairs(self.Targets) do
    if Me:GetDistance(u) <= dist then count = count + 1 end
  end
  return count
end

function Combat:GetTargetsAround(unit, distance)
  local count = 0
  for _, u in ipairs(self.Targets) do
    if unit:GetDistance(u) <= distance then count = count + 1 end
  end
  return count
end

return Combat

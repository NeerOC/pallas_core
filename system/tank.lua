-- Tank targeting system (mirrors Pallas system/tank.lua).
--
-- Like Combat but prioritises targets by threat status so the tank can pick
-- up loose mobs.

Tank = Tank or Targeting:New()

Tank.PriorityList = {}
Tank.BestTarget   = nil

function Tank:Update()
  Targeting.Update(self)

  if PallasSettings.PallasAutoTarget and Me and not Me.Target then
    if self.BestTarget and self.BestTarget:validTarget() then
      Me:SetTarget(self.BestTarget)
    end
  end
end

function Tank:Reset()
  self.Targets      = {}
  self.PriorityList = {}
  self.BestTarget   = nil
end

function Tank:WantToRun()
  if not Behavior:HasBehavior(BehaviorType.Tank) then return false end
  if not Me then return false end
  if Me.IsMounted then return false end
  return PallasSettings.PallasAttackOOC or Me.InCombat
end

function Tank:CollectTargets()
  if not Me.InCombat and PallasSettings.PallasAttackOOC then
    local tgt = Me.Target
    if tgt and not tgt.IsDead then
      self.Targets[#self.Targets + 1] = tgt
    end
    return
  end

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
    if not eu.in_combat then
      -- Only allow OOC units if they are the current target and AttackOOC is enabled
      local is_current_target = Me.Target and Me.Target.Guid == e.guid
      if not (PallasSettings.PallasAttackOOC and is_current_target) then
        goto skip
      end
    end

    if mx and e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      if dx*dx + dy*dy + dz*dz > 1600 then goto skip end
    end

    self.Targets[#self.Targets + 1] = Unit:New(e)
    ::skip::
  end
end

function Tank:ExclusionFilter()
  local keep = {}
  for _, u in ipairs(self.Targets) do
    if u and Me:CanAttack(u) then
      keep[#keep + 1] = u
    end
  end
  self.Targets = keep
end

function Tank:InclusionFilter()
  local tgt = Me.Target
  if not tgt then return end
  for _, u in ipairs(self.Targets) do
    if u.Guid == tgt.Guid then return end
  end
  if tgt.IsDead or tgt.Health <= 0 then return end
  self.Targets[#self.Targets + 1] = tgt
end

function Tank:WeighFilter()
  for _, u in ipairs(self.Targets) do
    local priority = 0

    local ok, is_tanking, status, scaled_pct, raw_pct, threat_val =
        pcall(game.unit_threat, u.obj_ptr)
    if ok and status then
      if status == 0 then
        priority = 50
      elseif status == 2 then
        priority = 25
      end
      priority = priority + (400 - (raw_pct or 100))
    else
      priority = 40 - Me:GetDistance(u)
    end

    self.PriorityList[#self.PriorityList + 1] = { Unit = u, Priority = priority }
  end

  table.sort(self.PriorityList, function(a, b) return a.Priority > b.Priority end)
  if #self.PriorityList == 0 then return end

  self.BestTarget = self.PriorityList[1].Unit
end

return Tank

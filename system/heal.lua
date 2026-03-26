-- Heal targeting system (mirrors Pallas system/heal.lua).
--
-- Collects friendly units each tick, filters, and ranks by priority
-- (role weight + health deficit).  Behaviors read Heal.PriorityList.

Heal = Heal or Targeting:New()

Heal.PriorityList = {}
Heal.Friends = {
  Tanks   = {},
  DPS     = {},
  Healers = {},
  All     = {},
}

function Heal:Update()
  Targeting.Update(self)
end

function Heal:Reset()
  self.PriorityList = {}
  self.HealTargets  = {}
  self.Friends      = {
    Tanks   = {},
    DPS     = {},
    Healers = {},
    All     = {},
  }
end

function Heal:WantToRun()
  if not Behavior:HasBehavior(BehaviorType.Heal) then return false end
  if not Me then return false end
  if Me.IsMounted then return false end
  return true
end

function Heal:CollectTargets()
  local entities = Pallas._entity_cache or {}
  local mx, my, mz
  if Me.Position then
    mx, my, mz = Me.Position.x, Me.Position.y, Me.Position.z
  end

  for _, e in ipairs(entities) do
    local cls = e.class
    if cls ~= "Unit" and cls ~= "Player" and cls ~= "ActivePlayer" then goto skip end

    local eu = e.unit
    if not eu then goto skip end

    -- Check if unit is dead or ghost using game API
    local dead_ok, is_dead_or_ghost = pcall(game.unit_dead_or_ghost, e.obj_ptr)
    if dead_ok and is_dead_or_ghost then goto skip end

    if eu.health and eu.health < 1 then goto skip end

    -- 40yd range pre-filter
    if mx and e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      if dx * dx + dy * dy + dz * dz > 1600 then goto skip end
    end

    self.HealTargets[#self.HealTargets + 1] = Unit:New(e)
    ::skip::
  end
end

-- Traceline flags: terrain (0x01) + buildings/WMO (0x02).
local LOS_FLAGS = 0x03

function Heal:ExclusionFilter()
  local keep = {}
  for _, u in ipairs(self.HealTargets) do
    if not u then goto skip_ex end
    if Me:CanAttack(u) then goto skip_ex end

    -- Line-of-sight check
    local los_ok, los = pcall(game.is_visible, Me.obj_ptr, u.obj_ptr, LOS_FLAGS)
    if not los_ok or not los then goto skip_ex end

    keep[#keep + 1] = u
    ::skip_ex::
  end
  self.HealTargets = keep
end

function Heal:InclusionFilter() end

function Heal:WeighFilter()
  local mana_multi = 30
  local ok_grp, in_group = pcall(game.is_in_group)
  in_group = ok_grp and in_group or false
  local members_set = {}

  if in_group then
    local ok, roster = pcall(game.group_members)
    if ok and roster then
      for _, m in ipairs(roster) do
        if m.guid_lo then members_set[m.guid_lo] = m end
      end
    end
  end

  for _, u in ipairs(self.HealTargets) do
    local priority = 0
    local is_tank, is_dps, is_heal = false, false, false

    local is_me = Me and u.Guid == Me.Guid
    local member = members_set[u.guid_lo]
    if not member and not is_me then goto continue end

    if u:IsTank() then
      priority = priority + 20; is_tank = true
    end
    if u:IsHealer() then
      priority = priority + 10; is_heal = true
    end
    if u:IsDPS() then
      priority = priority + 5; is_dps = true
    end

    priority = priority + (100 - u.HealthPct)
    priority = priority - ((100 - Me.PowerPct) * (mana_multi / 100))

    if priority > 0 or u.InCombat or is_me then
      self.PriorityList[#self.PriorityList + 1] = { Unit = u, Priority = priority }
    end

    if is_tank then
      self.Friends.Tanks[#self.Friends.Tanks + 1] = u
    elseif is_dps then
      self.Friends.DPS[#self.Friends.DPS + 1] = u
    elseif is_heal then
      self.Friends.Healers[#self.Friends.Healers + 1] = u
    end
    self.Friends.All[#self.Friends.All + 1] = u

    ::continue::
  end

  table.sort(self.PriorityList, function(a, b) return a.Priority > b.Priority end)
end

function Heal:GetLowestMember()
  local lowest = nil
  for _, v in ipairs(self.PriorityList) do
    if not lowest or lowest.HealthPct > v.Unit.HealthPct then
      lowest = v.Unit
    end
  end
  return lowest
end

function Heal:GetMembersBelow(pct)
  local members = {}
  for _, v in ipairs(self.PriorityList) do
    if v.Unit.HealthPct < pct then
      members[#members + 1] = v.Unit
    end
  end
  return members, #members
end

--- Returns the highest-priority member that has a dispellable debuff of the
--- given type(s), or nil if none found.
--- @param types number|table  Dispel type(s): 1=Magic, 2=Curse, 3=Disease, 4=Poison, 9=Enrage
function Heal:GetDispelTarget(types)
  for _, v in ipairs(self.PriorityList) do
    if v.Unit and not v.Unit.IsDead and v.Unit:HasDispellableDebuff(types) then
      return v.Unit
    end
  end
  return nil
end

--- Returns all members that have a dispellable debuff of the given type(s).
--- @param types number|table  Dispel type(s)
function Heal:GetDispelTargets(types)
  local targets = {}
  for _, v in ipairs(self.PriorityList) do
    if v.Unit and not v.Unit.IsDead and v.Unit:HasDispellableDebuff(types) then
      targets[#targets + 1] = v.Unit
    end
  end
  return targets, #targets
end

function Heal:GetMembersAround(friend, dist, threshold)
  threshold = threshold or 100
  local members = {}
  for _, v in ipairs(self.PriorityList) do
    if friend:GetDistance(v.Unit) <= dist and v.Unit.HealthPct < threshold then
      members[#members + 1] = v.Unit
    end
  end
  return #members, members
end

return Heal

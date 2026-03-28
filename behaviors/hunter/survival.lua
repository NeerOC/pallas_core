-- ═══════════════════════════════════════════════════════════════════
-- Survival Hunter behavior (MoP 5.5.3)
--
-- Single-Target Priority:
--   1. Maintain Aspect of the Hawk / Iron Hawk
--   2. Maintain Hunter's Mark
--   3. Explosive Shot on CD
--   4. Glaive Toss on CD (talent)
--   5. Black Arrow on CD
--   6. A Murder of Crows on CD (talent)
--   7. Dire Beast on CD (talent)
--   8. Maintain Serpent Sting
--   9. Fervor at low focus (talent)
--  10. Kill Shot (execute <20%)
--  11. Arcane Shot at 55+ focus (or Thrill of the Hunt proc)
--  12. Cobra Shot (filler)
--
-- AoE (>2 enemies within 10yd of target):
--   Explosive Shot (Lock and Load) > Multi-Shot > Fervor >
--   Dire Beast > Kill Shot > Black Arrow > Glaive Toss >
--   Cobra Shot
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Hunter (Survival)",
  Widgets = {
    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "SVUseRapidFire",
      text = "Use Rapid Fire",        default = true },
    { type = "checkbox", uid = "SVUseStampede",
      text = "Use Stampede",           default = true },
    { type = "checkbox", uid = "SVUseFervor",
      text = "Use Fervor",             default = true },

    { type = "text",     text = "=== Focus Management ===" },
    { type = "slider",   uid = "SVArcaneShotMinFocus",
      text = "Arcane Shot min focus",  default = 55, min = 30, max = 100 },
    { type = "slider",   uid = "SVFervorThreshold",
      text = "Fervor below focus %",   default = 50, min = 10, max = 80 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "SVUseCounterShot",
      text = "Use Counter Shot",       default = true },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "SVAutoAspects",
      text = "Auto Aspect (Iron Hawk in combat, Pack OOC)", default = true },
    { type = "checkbox", uid = "SVUseMastersCall",
      text = "Use Master's Call (root/snare removal)", default = true },
    { type = "checkbox", uid = "SVUseMisdirection",
      text = "Use Misdirection (aggro to tank)",       default = true },
    { type = "checkbox", uid = "SVSpreadSerpentSting",
      text = "Spread Serpent Sting (multi-dot)", default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "SVAoeEnabled",
      text = "Use AoE rotation",               default = true },
    { type = "slider",   uid = "SVAoeCount",
      text = "AoE mob threshold",              default = 2, min = 1, max = 10 },
    { type = "slider",   uid = "SVAoeRange",
      text = "AoE detection range (yards)",    default = 10, min = 5, max = 40 },
  },
}

-- ── Helpers ────────────────────────────────────────────────────

--- Returns true if any combat target is targeting the player.
local function MobsTargetingMe()
  for _, enemy in ipairs(Combat.Targets or {}) do
    local enemyTarget = enemy:GetTarget()
    if enemyTarget and enemyTarget.Guid == Me.Guid then
      return true
    end
  end
  return false
end

--- Finds the group's tank unit, or nil if none.
local function GetTank()
  for _, v in ipairs(Heal.PriorityList or {}) do
    if v.Unit and not v.Unit.IsDead and v.Unit:IsTank() and v.Unit.Guid ~= Me.Guid then
      return v.Unit
    end
  end
  return nil
end

--- Returns true if the player has an active ROOT or SNARE loss-of-control effect.
local function IsRootedOrSnared()
  local count = game.loss_of_control_count(Me.obj_ptr)
  if count == 0 then return false end
  for i = 1, count do
    local loc = game.loss_of_control_info(Me.obj_ptr, i)
    if loc and (loc.locType == "ROOT" or loc.locType == "SNARE") then
      return true
    end
  end
  return false
end

local function SpreadSerpentSting(target)
  if not Spell.SerpentSting.IsKnown then return false end
  for _, u in ipairs(Combat.Targets or {}) do
    if not u:HasAura("Serpent Sting") then
      local ok, visible = pcall(game.is_visible, Me.obj_ptr, u.obj_ptr, 0x03)
      if ok and visible then
        if Spell.SerpentSting:CastEx(u) then return true end
      end
    end
  end
  return false
end

-- ── Main rotation ──────────────────────────────────────────────

local function SurvivalCombat()
  -- ── Aspect management (Iron Hawk in combat, Pack out of combat) ──
  if PallasSettings.SVAutoAspects then
    if Me.InCombat then
      if not Me:HasAura("Aspect of the Iron Hawk") then
        if Spell.AspectOfTheIronHawk:CastEx(Me) then return end
      end
    else
      if not Me:HasAura("Aspect of the Pack") then
        if Spell.AspectOfThePack:CastEx(Me) then return end
      end
    end
  end

  local target = Combat.BestTarget
  if not target then return end

  -- Fervor (talent — instant 50 focus when starved)
  if PallasSettings.SVUseFervor and Me.PowerPct < (PallasSettings.SVFervorThreshold or 50) then
    if Spell.Fervor:CastEx(Me) then return end
  end

  -- Auto-range
  if not Me:IsAutoRanging() then
    Me:StartRanging(target)
  end

  if Me:IsCastingOrChanneling() then return end

  -- Counter Shot — interrupt enemy casts (off-GCD check)
  if PallasSettings.SVUseCounterShot then
    if Spell.CounterShot:Interrupt() then return end
  end

  -- Master's Call — break roots/snares on the player
  if PallasSettings.SVUseMastersCall and IsRootedOrSnared() then
    if Spell.MastersCall:CastEx(Me) then return end
  end

  -- Misdirection — redirect threat to tank if mobs are targeting me
  if PallasSettings.SVUseMisdirection and not Me:HasAura("Misdirection") and MobsTargetingMe() then
    local tank = GetTank()
    if tank then
      if Spell.Misdirection:CastEx(tank) then return end
    end
  end

  if Spell:IsGCDActive() then return end

  -- Determine AoE
  local use_aoe = false
  if PallasSettings.SVAoeEnabled then
    local aoe_range = PallasSettings.SVAoeRange or 10
    local aoe_count = PallasSettings.SVAoeCount or 2
    local nearby_target = Combat:GetTargetsAround(target, aoe_range)
    use_aoe = nearby_target > aoe_count
  end

  -- ── Priority list (MoP 5.5.3 Survival) ────────────────────

  -- 1. Maintain Hunter's Mark
  if not target:HasAura("Hunter's Mark") then
    if Spell.HuntersMark:CastEx(target) then return end
  end

  if use_aoe then
    -- ── AoE priority ───────────────────────────────────────

    -- Explosive Trap (ground-targeted AoE)
    if Spell.ExplosiveTrap:CastAtPos(target) then return end

    -- Explosive Shot (Lock and Load procs)
    if Spell.ExplosiveShot:CastEx(target) then return end

    -- Multi-Shot as main AoE spender
    if Spell.Multishot:CastEx(target) then return end

    -- Glaive Toss
    if Spell.GlaiveToss:CastEx(target) then return end

    -- Dire Beast
    if Spell.DireBeast:CastEx(target) then return end

    -- Kill Shot (execute)
    if Spell.KillShot:CastEx(target) then return end

    -- Black Arrow (still worth keeping up in AoE for L&L)
    if Spell.BlackArrow:CastEx(target) then return end

    -- Cobra Shot (filler)
    Spell.CobraShot:CastEx(target)
    return
  end

  -- ── Single-target priority ─────────────────────────────

  -- 2. Explosive Shot (top priority — also consumes Lock and Load)
  if Spell.ExplosiveShot:CastEx(target) then return end

  -- 3. Glaive Toss (talent)
  if Spell.GlaiveToss:CastEx(target) then return end

  -- 4. Black Arrow on CD
  if Spell.BlackArrow:CastEx(target) then return end

  -- 5. A Murder of Crows (talent)
  if Spell.AMurderOfCrows:CastEx(target) then return end

  -- 6. Dire Beast (talent)
  if Spell.DireBeast:CastEx(target) then return end

  -- 7. Maintain Serpent Sting
  if PallasSettings.SVSpreadSerpentSting then
    if SpreadSerpentSting(target) then return end
  elseif not target:HasAura("Serpent Sting") then
    if Spell.SerpentSting:CastEx(target) then return end
  end

  -- 8. Stampede on CD
  if PallasSettings.SVUseStampede then
    if Spell.Stampede:CastEx(Me) then return end
  end

  -- 9. Rapid Fire on CD
  if PallasSettings.SVUseRapidFire then
    if Spell.RapidFire:CastEx(Me) then return end
  end

  -- 10. Rabid (pet) on CD
  if Spell.Rabid:CastEx(Me) then return end

  -- 11. Kill Shot (execute <20%)
  if Spell.KillShot:CastEx(target) then return end

  -- 12. Arcane Shot at focus threshold (or Thrill of the Hunt proc)
  if Me:HasAura("Thrill of the Hunt") or Me.Power >= (PallasSettings.SVArcaneShotMinFocus or 55) then
    if Spell.ArcaneShot:CastEx(target) then return end
  end

  -- 13. Cobra Shot (filler / focus generator)
  Spell.CobraShot:CastEx(target)
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = SurvivalCombat,
}

return { Options = options, Behaviors = behaviors }

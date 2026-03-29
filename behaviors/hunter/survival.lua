-- ═══════════════════════════════════════════════════════════════════
-- Survival Hunter behavior (MoP Classic — level 85)
--
-- Pre-GCD (off-GCD abilities, checked every tick):
--   - Rapid Fire (avoid Heroism overlap)
--   - On-use trinkets (sync with Rapid Fire)
--   - Counter Shot interrupt
--   - Master's Call (root/snare removal)
--   - Misdirection (aggro to tank)
--   - Rabid (pet CD)
--
-- Single-Target Priority:
--   1. Kill Shot (scan all targets ≤20%)
--   2. Explosive Shot — Lock and Load proc (immediate)
--   3. Black Arrow (clip protection <1.5s, L&L proc source)
--   4. A Murder of Crows / Lynx Rush / Blink Strike (tier 5 talent)
--   5. Explosive Shot — regular (on CD)
--   6. Explosive Trap (at target pos, stationary only)
--   7. Dire Beast (talent)
--   8. Serpent Sting (apply only if missing; Cobra Shot refreshes)
--   9. Stampede (sync with RF / Heroism, if high enough level)
--  10. Arcane Shot (focus-conserve: hold for ES/BA coming off CD)
--  11. Cobra Shot (filler, CD-aware + focus cap)
--
-- Cleave (2 targets):
--   Kill Shot > L&L ES > Black Arrow > Tier5 > ES > Multi-Shot
--   (surplus focus) > Dire Beast > Cobra Shot
--
-- AoE (3+ targets):
--   Explosive Trap > L&L ES only > Multi-Shot (focus-gated) >
--   Kill Shot > Dire Beast > Cobra Shot
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
    { type = "checkbox", uid = "SVSyncCooldowns",
      text = "Sync Stampede with Rapid Fire / Heroism", default = true },
    { type = "checkbox", uid = "SVAvoidRFHeroism",
      text = "Avoid Rapid Fire during Heroism",         default = true },
    { type = "checkbox", uid = "SVUseTrinkets",
      text = "Use on-use trinkets with Rapid Fire",     default = true },

    { type = "text",     text = "=== Focus Management ===" },
    { type = "slider",   uid = "SVArcaneShotMinFocus",
      text = "Arcane Shot min focus",  default = 55, min = 30, max = 100 },
    { type = "slider",   uid = "SVFervorThreshold",
      text = "Fervor below focus %",   default = 50, min = 10, max = 80 },
    { type = "checkbox", uid = "SVSmartFocus",
      text = "Smart focus conservation (hold for ES/BA)", default = true },
    { type = "slider",   uid = "SVCobraShotFocusCap",
      text = "Cobra Shot focus cap (skip above)", default = 75, min = 50, max = 100 },

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
    { type = "checkbox", uid = "SVUseTranqShot",
      text = "Use Tranquilizing Shot (auto-purge)", default = true },
    { type = "checkbox", uid = "SVUseMendPet",
      text = "Use Mend Pet",           default = true },
    { type = "slider",   uid = "SVMendPetHP",
      text = "Mend Pet health %",      default = 75, min = 20, max = 95 },
    { type = "checkbox", uid = "SVUseExhilaration",
      text = "Use Exhilaration (self-heal)",        default = true },
    { type = "slider",   uid = "SVExhilPlayerHP",
      text = "Exhilaration player HP %",            default = 50, min = 10, max = 80 },
    { type = "slider",   uid = "SVExhilPetHP",
      text = "Exhilaration pet HP %",               default = 20, min = 5,  max = 50 },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "SVAoeEnabled",
      text = "Use AoE rotation",               default = true },
    { type = "slider",   uid = "SVAoeCount",
      text = "AoE mob threshold",              default = 3, min = 2, max = 10 },
    { type = "slider",   uid = "SVAoeRange",
      text = "AoE detection range (yards)",    default = 10, min = 5, max = 40 },
    { type = "checkbox", uid = "SVCleaveEnabled",
      text = "Use Cleave rotation (2 targets)", default = true },
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

--- Returns remaining seconds on a debuff cast by the player, or 0.
local function DebuffRemaining(unit, name_or_id)
  local aura = unit:GetAuraByMe(name_or_id)
  if not aura or not aura.expire_time then return 0 end
  local remaining = (aura.expire_time - game.game_time()) * 0.001
  return remaining > 0 and remaining or 0
end

--- Real cooldown remaining (ignores GCD — duration < 2s is just GCD).
local function CdRemaining(spell)
  if not spell.IsKnown then return -1 end
  local cd = spell:GetCooldown()
  if cd and cd.on_cooldown and (cd.duration or 0) > 2 then
    return cd.remaining or 0
  end
  return 0
end

--- Returns true if player has any Heroism-type buff.
local function HasHeroism()
  return Me:HasAura("Heroism")
      or Me:HasAura("Bloodlust")
      or Me:HasAura("Time Warp")
      or Me:HasAura("Ancient Hysteria")
end

--- Casts the player's active tier 5 talent (AMoC / Lynx Rush / Blink Strike).
--- AMoC: health gate + execute scan. Lynx Rush: pet must be in melee range.
--- Blink Strike: on CD. Returns true if anything fired.
local function CastTier5Talent(target)
  -- A Murder of Crows (spell 131894)
  if Spell.AMurderOfCrows.IsKnown then
    -- Execute priority: scan all targets for ≤20% HP (CD resets on kill)
    for _, u in ipairs(Combat.Targets or {}) do
      if not u.IsDead and u.HealthPct <= 20 then
        if Spell.AMurderOfCrows:CastEx(u) then return true end
      end
    end
    -- Health gate: only on targets that will live long enough (HP > 3x player max)
    if target.Health > (Me.MaxHealth * 3) then
      if Spell.AMurderOfCrows:CastEx(target) then return true end
    end
    return false
  end

  -- Lynx Rush (spell 120697) — pet must exist and be in melee range of its target
  if Spell.LynxRush and Spell.LynxRush.IsKnown then
    local pet = Pet.GetPrimary and Pet.GetPrimary()
    if pet and not pet.IsDead then
      if Spell.LynxRush:CastEx(target) then return true end
    end
    return false
  end

  -- Blink Strike (spell 112830) — on CD
  if Spell.BlinkStrike and Spell.BlinkStrike.IsKnown then
    if Spell.BlinkStrike:CastEx(target) then return true end
    return false
  end

  return false
end

-- ── Aspect management + Hunter's Mark (Extra behavior) ──────────

local function SurvivalExtra()
  -- Aspect switching
  if not PallasSettings.SVAutoAspects then return end

  local anyone_in_combat = false
  for _, v in ipairs(Heal.PriorityList or {}) do
    if v.Unit and not v.Unit.IsDead and v.Unit.InCombat then
      anyone_in_combat = true
      break
    end
  end

  if anyone_in_combat then
    if not Me:HasAura("Aspect of the Iron Hawk") and not Me:HasAura("Aspect of the Hawk") then
      if not Spell.AspectOfTheIronHawk:CastEx(Me) then
        Spell.AspectOfTheHawk:CastEx(Me)
      end
    end
  else
    if not Me:HasAura("Aspect of the Pack") then
      Spell.AspectOfThePack:CastEx(Me)
    end
  end
end

-- ── Main rotation ──────────────────────────────────────────────

local function SurvivalCombat()

  local target = Combat.BestTarget
  if not target then return end

  -- Mend Pet — auto-heal pet when low
  if PallasSettings.SVUseMendPet and Spell.MendPet.IsKnown then
    local pet = Pet.GetPrimary and Pet.GetPrimary()
    if pet and not pet.IsDead and pet.HealthPct < (PallasSettings.SVMendPetHP or 75) then
      if not pet:HasAura("Mend Pet") then
        if Spell.MendPet:CastEx(pet) then return end
      end
    end
  end

  -- Exhilaration — self-heal when player or pet HP critical
  if PallasSettings.SVUseExhilaration and Spell.Exhilaration and Spell.Exhilaration.IsKnown then
    local pet = Pet.GetPrimary and Pet.GetPrimary()
    local player_low = Me.HealthPct < (PallasSettings.SVExhilPlayerHP or 50)
    local pet_low = pet and not pet.IsDead and pet.HealthPct < (PallasSettings.SVExhilPetHP or 20)
    if player_low or pet_low then
      if Spell.Exhilaration:CastEx(Me) then return end
    end
  end

  -- Fervor (talent — instant 50 focus when starved)
  if PallasSettings.SVUseFervor and Me.PowerPct < (PallasSettings.SVFervorThreshold or 50) then
    if Spell.Fervor:CastEx(Me) then return end
  end

  -- Auto-range
  if not Me:IsAutoRanging() then
    Me:StartRanging(target)
  end

  if Me:IsCastingOrChanneling() then return end

  -- ── Off-GCD abilities (checked before GCD gate) ────────────

  -- Counter Shot — interrupt enemy casts
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

  -- Rapid Fire — off-GCD, checked before GCD gate
  if PallasSettings.SVUseRapidFire and Spell.RapidFire.IsKnown then
    local can_rf = true
    if PallasSettings.SVAvoidRFHeroism and HasHeroism() then can_rf = false end
    if Me:HasAura("Rapid Fire") then can_rf = false end
    if can_rf then
      if Spell.RapidFire:CastEx(Me) then
        -- Pop on-use trinkets with Rapid Fire
        if PallasSettings.SVUseTrinkets then
          if Item.Trinket1 and Item.Trinket1:IsReady() then Item.Trinket1:Use() end
          if Item.Trinket2 and Item.Trinket2:IsReady() then Item.Trinket2:Use() end
        end
        return
      end
    end
  end

  -- Rabid (pet) — off-GCD
  if Spell.Rabid:CastEx(Me) then end

  -- Tranquilizing Shot — auto-purge stealable buffs
  if PallasSettings.SVUseTranqShot and Spell.TranquilizingShot and Spell.TranquilizingShot.IsKnown then
    if target:HasStealableBuff() then
      if Spell.TranquilizingShot:CastEx(target) then return end
    end
  end

  if Spell:IsGCDActive() then return end

  -- ── Determine target count for ST / Cleave / AoE ─────────
  local nearby_count = 0
  if PallasSettings.SVAoeEnabled or PallasSettings.SVCleaveEnabled then
    local aoe_range = PallasSettings.SVAoeRange or 10
    nearby_count = Combat:GetTargetsAround(target, aoe_range)
  end

  local aoe_threshold = PallasSettings.SVAoeCount or 3
  local use_aoe = PallasSettings.SVAoeEnabled and nearby_count >= aoe_threshold
  local use_cleave = not use_aoe and PallasSettings.SVCleaveEnabled and nearby_count >= 2

  -- cache frequently used values
  local es_cd = CdRemaining(Spell.ExplosiveShot)
  local ba_cd = CdRemaining(Spell.BlackArrow)
  local has_lnl = Me:HasAura("Lock and Load")

  -- ══════════════════════════════════════════════════════════
  -- ── AoE priority (3+ targets) ────────────────────────────
  -- ══════════════════════════════════════════════════════════
  if use_aoe then

    -- Explosive Trap (ground-targeted via lua path for Trap Launcher)
    if Spell.ExplosiveTrap:CastAtPosLuaPath(target) then return end

    -- Explosive Shot — Lock and Load procs ONLY in AoE (focus better spent on Multi-Shot)
    if has_lnl then
      if Spell.ExplosiveShot:CastEx(target) then return end
    end

    -- Multi-Shot — main AoE spender, focus-gated to avoid starving priority shots
    if Me.Power >= 40 or Me:HasAura("Thrill of the Hunt") then
      -- Hold if ES L&L might proc and we're low, or if BA is about to come off CD
      local hold_ms = false
      if es_cd < 1.5 and Me.Power < 25 then hold_ms = true end
      if ba_cd < 2 and Me.Power < 35 then hold_ms = true end
      if not hold_ms then
        if Spell.Multishot:CastEx(target) then return end
      end
    end

    -- Kill Shot (execute — scan ≤20% HP targets)
    for _, ks_target in ipairs(Combat.Targets) do
      if not ks_target.IsDead and ks_target.HealthPct <= 20 then
        if Spell.KillShot:CastEx(ks_target) then return end
      end
    end

    -- Dire Beast
    if Spell.DireBeast:CastEx(target) then return end

    -- Stampede (if known — level 87+)
    if PallasSettings.SVUseStampede and Spell.Stampede and Spell.Stampede.IsKnown then
      if PallasSettings.SVSyncCooldowns then
        if Me:HasAura("Rapid Fire") or HasHeroism() or target.HealthPct < 5 then
          if Spell.Stampede:CastEx(Me) then return end
        end
      else
        if Spell.Stampede:CastEx(Me) then return end
      end
    end

    -- Cobra Shot (filler — CD-aware: skip if ES/BA about to come off CD with enough focus)
    local skip_cobra = false
    if es_cd < 1.5 and Me.Power > 25 then skip_cobra = true end
    if ba_cd < 1.5 and Me.Power > 35 then skip_cobra = true end
    if not skip_cobra and Me.Power < (PallasSettings.SVCobraShotFocusCap or 75) then
      Spell.CobraShot:CastEx(target)
    end
    return
  end

  -- ══════════════════════════════════════════════════════════
  -- ── Cleave priority (2 targets) ──────────────────────────
  -- ══════════════════════════════════════════════════════════
  if use_cleave then

    -- Kill Shot (execute scan)
    for _, ks_target in ipairs(Combat.Targets) do
      if not ks_target.IsDead and ks_target.HealthPct <= 20 then
        if Spell.KillShot:CastEx(ks_target) then return end
      end
    end

    -- Explosive Shot — L&L procs first
    if has_lnl then
      if Spell.ExplosiveShot:CastEx(target) then return end
    end

    -- Black Arrow — L&L proc source, keep uptime (clip protection)
    if DebuffRemaining(target, "Black Arrow") < 1.5 then
      if Spell.BlackArrow:CastEx(target) then return end
    end

    -- Tier 5 talent (AMoC / Lynx Rush / Blink Strike)
    if CastTier5Talent(target) then return end

    -- Explosive Shot — regular (non-L&L)
    if Spell.ExplosiveShot:CastEx(target) then return end

    -- Explosive Trap
    if not target:IsMoving() then
      if Spell.ExplosiveTrap:CastAtPosLuaPath(target) then return end
    end

    -- Multi-Shot — weave with surplus focus only (cleave, not full AoE)
    if Me:HasAura("Thrill of the Hunt") or Me.Power >= 55 then
      if Spell.Multishot:CastEx(target) then return end
    end

    -- Dire Beast
    if Spell.DireBeast:CastEx(target) then return end

    -- Serpent Sting — apply only if completely absent (Cobra Shot refreshes it)
    if not target:HasAura("Serpent Sting") then
      if Spell.SerpentSting:CastEx(target) then return end
    end

    -- Stampede (if known)
    if PallasSettings.SVUseStampede and Spell.Stampede and Spell.Stampede.IsKnown then
      if PallasSettings.SVSyncCooldowns then
        if Me:HasAura("Rapid Fire") or HasHeroism() or target.HealthPct < 5 then
          if Spell.Stampede:CastEx(Me) then return end
        end
      else
        if Spell.Stampede:CastEx(Me) then return end
      end
    end

    -- Arcane Shot — smart focus conservation (same logic as ST)
    local cleave_arcane_ok = false
    if Me:HasAura("Thrill of the Hunt") then
      cleave_arcane_ok = true
    elseif Me.Power >= (PallasSettings.SVArcaneShotMinFocus or 55) then
      if PallasSettings.SVSmartFocus then
        if es_cd < 1 and Me.Power < 35 then
          cleave_arcane_ok = false
        elseif ba_cd < 2 and Me.Power < 45 then
          cleave_arcane_ok = false
        elseif Spell.AMurderOfCrows.IsKnown and CdRemaining(Spell.AMurderOfCrows) < 2
               and target.HealthPct <= 20 and Me.Power < 60 then
          cleave_arcane_ok = false
        else
          cleave_arcane_ok = true
        end
      else
        cleave_arcane_ok = true
      end
    end
    if cleave_arcane_ok then
      if Spell.ArcaneShot:CastEx(target) then return end
    end

    -- Cobra Shot (filler — CD-aware)
    local skip_cobra = false
    if es_cd < 1.5 and Me.Power > 25 then skip_cobra = true end
    if ba_cd < 1.5 and Me.Power > 35 then skip_cobra = true end
    if not skip_cobra and Me.Power < (PallasSettings.SVCobraShotFocusCap or 75) then
      Spell.CobraShot:CastEx(target)
    end
    return
  end

  -- ══════════════════════════════════════════════════════════
  -- ── Single-target priority ───────────────────────────────
  -- ══════════════════════════════════════════════════════════

  -- 1. Kill Shot (execute — scan all targets ≤20% HP)
  for _, ks_target in ipairs(Combat.Targets) do
    if not ks_target.IsDead and ks_target.HealthPct <= 20 then
      if Spell.KillShot:CastEx(ks_target) then return end
    end
  end

  -- 2. Explosive Shot — Lock and Load gets absolute priority
  if has_lnl then
    if Spell.ExplosiveShot:CastEx(target) then return end
  end

  -- 3. Black Arrow — L&L proc source, maximize uptime (clip protection <1.5s)
  if DebuffRemaining(target, "Black Arrow") < 1.5 then
    if Spell.BlackArrow:CastEx(target) then return end
  end

  -- 4. Tier 5 talent (AMoC / Lynx Rush / Blink Strike)
  if CastTier5Talent(target) then return end

  -- 5. Explosive Shot — regular (on CD, after Black Arrow for uptime priority)
  if Spell.ExplosiveShot:CastEx(target) then return end

  -- 6. Explosive Trap (only if target is stationary)
  if not target:IsMoving() then
    if Spell.ExplosiveTrap:CastAtPosLuaPath(target) then return end
  end

  -- 7. Dire Beast (talent)
  if Spell.DireBeast:CastEx(target) then return end

  -- 8. Serpent Sting — apply only if completely absent
  --    Cobra Shot (filler) extends SS duration, so don't waste focus recasting
  if not target:HasAura("Serpent Sting") then
    if Spell.SerpentSting:CastEx(target) then return end
  end

  -- 9. Stampede (if known — level 87+)
  if PallasSettings.SVUseStampede and Spell.Stampede and Spell.Stampede.IsKnown then
    if PallasSettings.SVSyncCooldowns then
      if Me:HasAura("Rapid Fire") or HasHeroism() or target.HealthPct < 5 then
        if Spell.Stampede:CastEx(Me) then return end
      end
    else
      if Spell.Stampede:CastEx(Me) then return end
    end
  end

  -- 10. Arcane Shot — smart focus conservation
  local arcane_ok = false
  if Me:HasAura("Thrill of the Hunt") then
    arcane_ok = true
  elseif Me.Power >= (PallasSettings.SVArcaneShotMinFocus or 55) then
    if PallasSettings.SVSmartFocus then
      -- Hold focus if Explosive Shot is about to come off CD and we're low
      if es_cd < 1 and Me.Power < 35 then
        arcane_ok = false
      -- Hold focus if Black Arrow is about to come off CD and we're low
      elseif ba_cd < 2 and Me.Power < 45 then
        arcane_ok = false
      -- Hold focus if AMoC is about to come off CD on a dying target
      elseif Spell.AMurderOfCrows.IsKnown and CdRemaining(Spell.AMurderOfCrows) < 2
             and target.HealthPct <= 20 and Me.Power < 60 then
        arcane_ok = false
      else
        arcane_ok = true
      end
    else
      arcane_ok = true
    end
  end
  if arcane_ok then
    if Spell.ArcaneShot:CastEx(target) then return end
  end

  -- 11. Cobra Shot (filler / focus generator)
  --     CD-aware: skip if ES or BA about to come off CD and we have enough focus
  --     Focus cap: don't waste regen above threshold
  local skip_cobra = false
  if es_cd < 1.5 and Me.Power > 25 then skip_cobra = true end
  if ba_cd < 1.5 and Me.Power > 35 then skip_cobra = true end
  if not skip_cobra and Me.Power < (PallasSettings.SVCobraShotFocusCap or 75) then
    Spell.CobraShot:CastEx(target)
  end
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = SurvivalCombat,
  [BehaviorType.Extra]  = SurvivalExtra,
}

return { Options = options, Behaviors = behaviors }

-- ═══════════════════════════════════════════════════════════════════
-- Protection Warrior behavior (MoP 5.5.3)
--
-- Priority-based tank rotation with active mitigation management,
-- threat-aware targeting, defensive cooldown automation, and
-- configurable Shield Block vs Shield Barrier logic.
--
-- Single-Target Priority:
--   1. Shield Slam (highest damage/threat, procs Sword and Board)
--   2. Revenge (procs on dodge/parry, free, strong threat)
--   3. Devastate (Sunder Armor stacks, S&B proc fishing)
--   4. Thunder Clap (maintain Weakened Blows, Deep Wounds spread)
--   5. Execute (<20% or Sudden Death proc via Ultimatum)
--   6. Heroic Strike (Ultimatum proc = free, or excess rage dump)
--   7. Battle Shout (filler, rage gen)
--
-- Active Mitigation:
--   Shield Block — 60 rage, 6s 100% block. Use vs physical damage.
--   Shield Barrier — 20-60 rage, absorb shield. Use vs magic or
--     when Shield Block is already active.
--   Configurable: auto (smart logic), prefer Block, prefer Barrier.
--
-- AoE Priority (3+ targets):
--   Thunder Clap (spread Deep Wounds) → Shield Slam → Revenge
--   → Devastate → Cleave (instead of HS)
--
-- Defensives:
--   Shield Wall, Last Stand, Demoralizing Shout, Spell Reflection,
--   Enraged Regeneration, Rallying Cry, Impending Victory
--
-- Threat:
--   Taunt loose mobs, Heroic Throw for ranged pickup, auto-target
--   via Tank.BestTarget (threat-prioritized).
-- ═══════════════════════════════════════════════════════════════════

local function S(uid)
  return PallasSettings[uid] ~= false
end

-- ── Options ──────────────────────────────────────────────────────

local options = {
  Name = "Warrior (Protection)",
  Widgets = {
    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "ProtUseShieldSlam",
      text = "Shield Slam",                   default = true },
    { type = "checkbox", uid = "ProtUseRevenge",
      text = "Revenge",                       default = true },
    { type = "checkbox", uid = "ProtUseDevastate",
      text = "Devastate",                     default = true },
    { type = "checkbox", uid = "ProtUseThunderClap",
      text = "Thunder Clap",                  default = true },
    { type = "checkbox", uid = "ProtUseExecute",
      text = "Execute (<20%)",                default = true },
    { type = "checkbox", uid = "ProtUseHeroicStrike",
      text = "Heroic Strike (off-GCD dump)",  default = true },
    { type = "slider",   uid = "ProtHSRageThreshold",
      text = "Heroic Strike min rage",        default = 80, min = 40, max = 110 },
    { type = "checkbox", uid = "ProtUseCleave",
      text = "Cleave (AoE rage dump)",        default = true },

    { type = "text",     text = "=== Active Mitigation ===" },
    { type = "combobox", uid = "ProtMitigationMode",
      text = "Active mitigation",             default = 0,
      options = { "Auto (smart)", "Prefer Shield Block", "Prefer Shield Barrier", "Manual (disabled)" } },
    { type = "slider",   uid = "ProtShieldBlockRage",
      text = "Shield Block min rage",         default = 60, min = 40, max = 80 },
    { type = "slider",   uid = "ProtShieldBarrierRage",
      text = "Shield Barrier min rage",       default = 40, min = 20, max = 80 },
    { type = "checkbox", uid = "ProtBarrierOverBlock",
      text = "Shield Barrier when Block is active", default = true },
    { type = "slider",   uid = "ProtBarrierHP",
      text = "Shield Barrier HP % threshold", default = 80, min = 30, max = 100 },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "ProtUseAvatar",
      text = "Avatar (talent)",               default = true },
    { type = "checkbox", uid = "ProtUseBloodbath",
      text = "Bloodbath (talent)",             default = true },
    { type = "checkbox", uid = "ProtUseStormBolt",
      text = "Storm Bolt (talent)",           default = true },
    { type = "checkbox", uid = "ProtUseDragonRoar",
      text = "Dragon Roar (talent)",          default = true },
    { type = "checkbox", uid = "ProtUseBladestorm",
      text = "Bladestorm (talent, AoE only)", default = false },
    { type = "checkbox", uid = "ProtUseShockwave",
      text = "Shockwave (talent, AoE stun)",  default = true },
    { type = "checkbox", uid = "ProtUseBerserkerRage",
      text = "Berserker Rage",                default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "ProtUseShieldWall",
      text = "Shield Wall",                   default = true },
    { type = "slider",   uid = "ProtShieldWallHP",
      text = "Shield Wall HP %",              default = 30, min = 10, max = 60 },
    { type = "checkbox", uid = "ProtUseLastStand",
      text = "Last Stand",                    default = true },
    { type = "slider",   uid = "ProtLastStandHP",
      text = "Last Stand HP %",               default = 25, min = 10, max = 50 },
    { type = "checkbox", uid = "ProtUseDemoShout",
      text = "Demoralizing Shout",            default = true },
    { type = "slider",   uid = "ProtDemoShoutHP",
      text = "Demoralizing Shout HP %",       default = 60, min = 20, max = 90 },
    { type = "checkbox", uid = "ProtUseSpellReflect",
      text = "Spell Reflection",              default = true },
    { type = "checkbox", uid = "ProtUseEnragedRegen",
      text = "Enraged Regeneration",          default = true },
    { type = "slider",   uid = "ProtEnragedRegenHP",
      text = "Enraged Regen HP %",            default = 45, min = 15, max = 70 },
    { type = "checkbox", uid = "ProtUseRallyingCry",
      text = "Rallying Cry",                  default = true },
    { type = "slider",   uid = "ProtRallyingCryHP",
      text = "Rallying Cry HP %",             default = 20, min = 10, max = 50 },
    { type = "checkbox", uid = "ProtUseImpendingVictory",
      text = "Impending Victory (talent)",    default = true },
    { type = "slider",   uid = "ProtImpendingVictoryHP",
      text = "Impending Victory HP %",        default = 55, min = 20, max = 80 },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "ProtUsePummel",
      text = "Pummel",                        default = true },
    { type = "checkbox", uid = "ProtUseDisruptingShout",
      text = "Disrupting Shout (AoE kick)",   default = true },
    { type = "slider",   uid = "ProtDisruptingShoutCount",
      text = "Disrupting Shout min casters",  default = 2, min = 1, max = 5 },

    { type = "text",     text = "=== Threat ===" },
    { type = "checkbox", uid = "ProtUseTaunt",
      text = "Taunt loose mobs",              default = true },
    { type = "checkbox", uid = "ProtUseHeroicThrow",
      text = "Heroic Throw (ranged pickup)",  default = true },
    { type = "slider",   uid = "ProtHeroicThrowDist",
      text = "Heroic Throw min distance",     default = 15, min = 5, max = 30 },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "ProtMaintainShout",
      text = "Maintain Battle Shout",         default = true },
    { type = "checkbox", uid = "ProtAutoAttack",
      text = "Auto start attack",             default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "ProtAoeEnabled",
      text = "Use AoE rotation",              default = true },
    { type = "slider",   uid = "ProtAoeThreshold",
      text = "AoE enemy count",               default = 3, min = 2, max = 8 },
    { type = "slider",   uid = "ProtDeepWoundsSpread",
      text = "Thunder Clap if enemies without Deep Wounds", default = 3, min = 1, max = 8 },
  },
}

-- ── Interrupts ───────────────────────────────────────────────────

local function TryInterrupt()
  if S("ProtUsePummel") then
    if Spell.Pummel:Interrupt() then return true end
  end

  if S("ProtUseDisruptingShout") and Spell.DisruptingShout.IsKnown then
    local min_casters = PallasSettings.ProtDisruptingShoutCount or 2
    local casters = 0
    for _, enemy in ipairs(Combat.Targets) do
      if not enemy.IsDead and Me:GetDistance(enemy) <= 10 and enemy:IsCastingOrChanneling() then
        casters = casters + 1
      end
    end
    if casters >= min_casters then
      if Spell.DisruptingShout:CastEx(Me) then return true end
    end
  end

  return false
end

-- ── Threat Management ────────────────────────────────────────────

local function TryTauntLoose()
  if not S("ProtUseTaunt") then return false end

  for _, enemy in ipairs(Combat.Targets) do
    if not enemy.IsDead and enemy.InCombat then
      local enemyTarget = enemy:GetTarget()
      if enemyTarget and enemyTarget.Guid ~= Me.Guid and enemyTarget.IsPlayer then
        if Spell.Taunt:CastEx(enemy, { skipFacing = true }) then return true end
      end
    end
  end

  return false
end

local function TryHeroicThrow()
  if not S("ProtUseHeroicThrow") then return false end

  local ht_min = PallasSettings.ProtHeroicThrowDist or 15

  for _, enemy in ipairs(Combat.Targets) do
    if not enemy.IsDead and enemy.InCombat then
      local enemyTarget = enemy:GetTarget()
      if enemyTarget and enemyTarget.Guid ~= Me.Guid and enemyTarget.IsPlayer then
        local dist = Me:GetDistance(enemy)
        if dist >= ht_min and dist <= 30 then
          if Spell.HeroicThrow:CastEx(enemy) then return true end
        end
      end
    end
  end

  return false
end

-- ── Active Mitigation ────────────────────────────────────────────

local function TryActiveMitigation()
  local mode = PallasSettings.ProtMitigationMode or 0
  if mode == 3 then return false end

  local has_block = Me:HasAura("Shield Block")
  local hp = Me.HealthPct
  local rage = Me.Power

  local block_rage = PallasSettings.ProtShieldBlockRage or 60
  local barrier_rage = PallasSettings.ProtShieldBarrierRage or 40
  local barrier_hp = PallasSettings.ProtBarrierHP or 80

  -- Mode 0: Auto (smart) — Block for physical, Barrier when Block is up or vs magic
  if mode == 0 then
    -- Shield Block if not already active and enough rage
    if not has_block and rage >= block_rage then
      if Spell.ShieldBlock:CastEx(Me) then return true end
    end

    -- Shield Barrier when Block is already active OR at lower HP
    if S("ProtBarrierOverBlock") and has_block and hp < barrier_hp and rage >= barrier_rage then
      if Spell.ShieldBarrier:CastEx(Me) then return true end
    end

    -- Shield Barrier as fallback when Block is on CD
    if not has_block and rage >= barrier_rage and hp < barrier_hp then
      local cd = Spell.ShieldBlock:GetCooldown()
      if cd and cd.on_cooldown then
        if Spell.ShieldBarrier:CastEx(Me) then return true end
      end
    end

  -- Mode 1: Prefer Shield Block
  elseif mode == 1 then
    if not has_block and rage >= block_rage then
      if Spell.ShieldBlock:CastEx(Me) then return true end
    end
    if has_block and rage >= barrier_rage and hp < barrier_hp then
      if Spell.ShieldBarrier:CastEx(Me) then return true end
    end

  -- Mode 2: Prefer Shield Barrier
  elseif mode == 2 then
    if rage >= barrier_rage and hp < barrier_hp then
      if Spell.ShieldBarrier:CastEx(Me) then return true end
    end
    if not has_block and rage >= block_rage then
      if Spell.ShieldBlock:CastEx(Me) then return true end
    end
  end

  return false
end

-- ── Defensives ───────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  -- Impending Victory (talent heal, on GCD but critical at low HP)
  -- We handle this early because it's a life-saving ability
  if S("ProtUseImpendingVictory") and hp < (PallasSettings.ProtImpendingVictoryHP or 55) then
    local target = Tank.BestTarget or Combat.BestTarget
    if target and Me:InMeleeRange(target) then
      if Spell.ImpendingVictory:CastEx(target) then return true end
    end
  end

  -- Shield Wall (major defensive, off-GCD)
  if S("ProtUseShieldWall") and hp < (PallasSettings.ProtShieldWallHP or 30) then
    if not Me:HasAura("Shield Wall") then
      if Spell.ShieldWall:CastEx(Me) then return true end
    end
  end

  -- Last Stand (emergency, off-GCD)
  if S("ProtUseLastStand") and hp < (PallasSettings.ProtLastStandHP or 25) then
    if Spell.LastStand:CastEx(Me) then return true end
  end

  -- Demoralizing Shout (damage reduction aura, off-GCD)
  if S("ProtUseDemoShout") and hp < (PallasSettings.ProtDemoShoutHP or 60) then
    if Spell.DemoralizingShout:CastEx(Me) then return true end
  end

  -- Enraged Regeneration
  if S("ProtUseEnragedRegen") and hp < (PallasSettings.ProtEnragedRegenHP or 45) then
    if Spell.EnragedRegeneration:CastEx(Me) then return true end
  end

  -- Rallying Cry (emergency, affects group)
  if S("ProtUseRallyingCry") and hp < (PallasSettings.ProtRallyingCryHP or 20) then
    if Spell.RallyingCry:CastEx(Me) then return true end
  end

  -- Spell Reflection (react to incoming casts)
  if S("ProtUseSpellReflect") and not Me:HasAura("Spell Reflection") then
    for _, enemy in ipairs(Combat.Targets) do
      if not enemy.IsDead and enemy:IsCastingOrChanneling() then
        local d = Me:GetDistance(enemy)
        if d <= 40 then
          if Spell.SpellReflection:CastEx(Me) then return true end
        end
      end
    end
  end

  return false
end

-- ── Heroic Strike / Cleave (off-GCD) ────────────────────────────

local function TryHeroicStrikeOrCleave(target)
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  local nearby = Combat:GetEnemiesWithinDistance(8)

  -- Ultimatum proc: free Heroic Strike (or Cleave in AoE)
  if Me:HasAura("Ultimatum") then
    if S("ProtUseCleave") and nearby >= 2 then
      return Spell.Cleave:CastEx(target)
    end
    if S("ProtUseHeroicStrike") then
      return Spell.HeroicStrike:CastEx(target)
    end
  end

  -- Normal rage dump (only when we can afford it after active mitigation)
  local hs_rage = PallasSettings.ProtHSRageThreshold or 80
  if Me.Power < hs_rage then return false end

  if S("ProtUseCleave") and nearby >= 3 then
    return Spell.Cleave:CastEx(target)
  end

  if S("ProtUseHeroicStrike") then
    return Spell.HeroicStrike:CastEx(target)
  end

  return false
end

-- ── Single-Target Rotation ───────────────────────────────────────

local function SingleTarget(target)
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  -- 1. Shield Slam (highest priority — damage, threat, rage gen via S&B)
  if S("ProtUseShieldSlam") then
    if Spell.ShieldSlam:CastEx(target) then return true end
  end

  -- 2. Revenge (free on dodge/parry, strong damage/threat)
  if S("ProtUseRevenge") then
    if Spell.Revenge:CastEx(target) then return true end
  end

  -- 3. Storm Bolt (talent, on CD for damage + stun)
  if S("ProtUseStormBolt") and Spell.StormBolt.IsKnown then
    if Spell.StormBolt:CastEx(target) then return true end
  end

  -- 4. Dragon Roar (talent, high damage)
  if S("ProtUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- 5. Execute (<20%, Sudden Death proc)
  if S("ProtUseExecute") and target.HealthPct > 0 and target.HealthPct < 20 then
    if Me.Power >= 30 then
      if Spell.Execute:CastEx(target, { skipUsable = true }) then return true end
    end
  end

  -- 6. Thunder Clap (maintain Weakened Blows on target)
  if S("ProtUseThunderClap") and not target:HasAura("Weakened Blows") then
    if Spell.ThunderClap:CastEx(Me) then return true end
  end

  -- 7. Devastate (filler — procs Sword and Board, applies Sunder Armor)
  if S("ProtUseDevastate") then
    if Spell.Devastate:CastEx(target) then return true end
  end

  -- 8. Battle Shout (absolute filler for rage gen)
  if S("ProtMaintainShout") then
    if Spell.BattleShout:CastEx(Me) then return true end
  end

  return false
end

-- ── AoE Rotation ─────────────────────────────────────────────────

local function AoERotation(target)
  if not target then return false end

  local nearby = Combat:GetEnemiesWithinDistance(8)

  -- Thunder Clap (spread Deep Wounds via Blood and Thunder, apply Weakened Blows)
  if S("ProtUseThunderClap") then
    local no_wounds = 0
    for _, enemy in ipairs(Combat.Targets) do
      if not enemy.IsDead and Me:GetDistance(enemy) <= 8 then
        if not enemy:HasAura("Deep Wounds") then
          no_wounds = no_wounds + 1
        end
      end
    end
    local spread_thresh = PallasSettings.ProtDeepWoundsSpread or 3
    if no_wounds >= spread_thresh or nearby >= 5 then
      if Spell.ThunderClap:CastEx(Me) then return true end
    end
  end

  -- Bladestorm (talent, massive AoE)
  if S("ProtUseBladestorm") and Spell.Bladestorm.IsKnown and nearby >= 4 then
    if Spell.Bladestorm:CastEx(Me) then return true end
  end

  -- Dragon Roar
  if S("ProtUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- Shockwave (AoE + stun)
  if S("ProtUseShockwave") and Spell.Shockwave.IsKnown and nearby >= 3 then
    if Spell.Shockwave:CastEx(Me) then return true end
  end

  -- Shield Slam
  if S("ProtUseShieldSlam") and Me:InMeleeRange(target) then
    if Spell.ShieldSlam:CastEx(target) then return true end
  end

  -- Revenge
  if S("ProtUseRevenge") and Me:InMeleeRange(target) then
    if Spell.Revenge:CastEx(target) then return true end
  end

  -- Thunder Clap (even if not for Deep Wounds spread, low CD and good AoE threat)
  if S("ProtUseThunderClap") then
    if Spell.ThunderClap:CastEx(Me) then return true end
  end

  -- Devastate
  if S("ProtUseDevastate") and Me:InMeleeRange(target) then
    if Spell.Devastate:CastEx(target) then return true end
  end

  return false
end

-- ── Main Combat Function ─────────────────────────────────────────

local function ProtCombat()
  if Me.IsMounted then return end
  if Me:IsIncapacitated() then return end
  if Me:IsCastingOrChanneling() then return end

  -- OOC: Maintain Battle Shout
  if not Me.InCombat then
    if S("ProtMaintainShout") and not Me:HasAura("Battle Shout") then
      Spell.BattleShout:CastEx(Me)
    end
    return
  end

  local target = Tank.BestTarget or Combat.BestTarget
  if not target then return end

  -- Auto attack
  if S("ProtAutoAttack") and Me:InMeleeRange(target) then
    if not Me:IsAutoAttacking() then
      Me:StartAttack(target)
    end
  end

  -- Berserker Rage: break fear/sap
  if S("ProtUseBerserkerRage") then
    if Me:IsFeared() or Me:IsConfused() then
      Spell.BerserkerRage:CastEx(Me)
    end
  end

  -- Off-GCD: Active Mitigation (Shield Block / Shield Barrier)
  TryActiveMitigation()

  -- Off-GCD: Heroic Strike / Cleave
  TryHeroicStrikeOrCleave(target)

  -- Defensives (most are off-GCD)
  if UseDefensives() then return end

  if Spell:IsGCDActive() then return end

  -- Interrupts
  if TryInterrupt() then return end

  -- Taunt loose mobs
  if TryTauntLoose() then return end

  -- Heroic Throw ranged pickup
  if TryHeroicThrow() then return end

  -- Offensive cooldowns
  if S("ProtUseAvatar") and Spell.Avatar.IsKnown then
    Spell.Avatar:CastEx(Me)
  end
  if S("ProtUseBloodbath") and Spell.Bloodbath.IsKnown then
    Spell.Bloodbath:CastEx(Me)
  end

  -- AoE vs ST
  local use_aoe = false
  if PallasSettings.ProtAoeEnabled then
    local nearby = Combat:GetEnemiesWithinDistance(8)
    use_aoe = nearby >= (PallasSettings.ProtAoeThreshold or 3)
  end

  if use_aoe then
    if not AoERotation(target) then
      SingleTarget(target)
    end
  else
    SingleTarget(target)
  end
end

-- ── Export ────────────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = ProtCombat,
}

return { Options = options, Behaviors = behaviors }

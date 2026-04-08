-- ═══════════════════════════════════════════════════════════════════
-- Fury Warrior behavior (MoP 5.5.3)
--
-- Priority-based rotation with PvP/PvE mode, burst keybind toggle,
-- Colossus Smash window management, Enrage uptime tracking, and
-- Bloodsurge proc handling.
--
-- Single-Target PvE Priority:
--   1. Bloodthirst on cooldown (Enrage proc, rage gen, primary)
--   2. Colossus Smash on cooldown (pool rage beforehand)
--   3. Execute (<20%) — replaces most fillers in execute phase
--   4. Storm Bolt (talent, on CD)
--   5. Raging Blow (requires Enrage, prefer spending at 2 charges)
--   6. Wild Strike (Bloodsurge proc = free)
--   7. Heroic Strike (off-GCD during CS window / high rage)
--   8. Dragon Roar / Shockwave (talent)
--   9. Berserker Rage (if not Enraged after BT)
--  10. Wild Strike (filler during CS if rage allows)
--  11. Battle Shout (filler, rage gen)
--
-- Execute Phase (<20%):
--   BT (Enrage maintenance only if not Enraged) → CS → Execute
--   → Raging Blow (during CS) → HS (off-GCD during CS)
--
-- AoE Priority (3+ targets):
--   Whirlwind (Meat Cleaver) → Raging Blow (cleaves) → BT → Cleave
--   → Dragon Roar / Bladestorm / Shockwave
--
-- 2-Target Cleave:
--   Normal ST rotation but Cleave replaces Heroic Strike
--
-- Burst CDs (Recklessness / Avatar|Bloodbath / Skull Banner):
--   Gated by a configurable toggle key. Synced with CS window.
-- ═══════════════════════════════════════════════════════════════════

local function S(uid)
  return PallasSettings[uid] ~= false
end

-- ── ImGuiKey name table ──────────────────────────────────────────

local KEY_NAMES = {
  [512] = "Tab",
  [513] = "Left", [514] = "Right", [515] = "Up", [516] = "Down",
  [517] = "PgUp", [518] = "PgDn", [519] = "Home", [520] = "End",
  [521] = "Ins", [522] = "Del", [523] = "Backspace", [524] = "Space",
  [525] = "Enter", [526] = "Escape",
  [527] = "LCtrl", [528] = "LShift", [529] = "LAlt", [530] = "LSuper",
  [531] = "RCtrl", [532] = "RShift", [533] = "RAlt", [534] = "RSuper",
  [535] = "Menu",
  [584] = "'", [585] = ",", [586] = "-", [587] = ".", [588] = "/",
  [589] = ";", [590] = "=", [591] = "[", [592] = "\\", [593] = "]",
  [594] = "`",
  [595] = "CapsLock", [596] = "ScrollLock", [597] = "NumLock",
  [598] = "PrtSc", [599] = "Pause",
  [610] = "KP.", [611] = "KP/", [612] = "KP*",
  [613] = "KP-", [614] = "KP+", [615] = "KPEnter", [616] = "KP=",
}
for i = 0, 9  do KEY_NAMES[536 + i] = tostring(i)       end
for i = 0, 25 do KEY_NAMES[546 + i] = string.char(65+i) end
for i = 1, 12 do KEY_NAMES[571 + i] = "F" .. i          end
for i = 0, 9  do KEY_NAMES[600 + i] = "KP" .. i         end

local SCAN_MIN, SCAN_MAX = 512, 616
local recording_burst_key = false
local burst_key_code      = nil
local burst_enabled       = false

local WF_HUD    = 1 + 64 + 4096 + 8192
local COND_FIRST = 4

-- ── Options ──────────────────────────────────────────────────────

local options = {
  Name = "Warrior (Fury)",
  Widgets = {
    { type = "text",     text = "=== Mode ===" },
    { type = "combobox", uid = "FuryMode",
      text = "Mode",                          default = 0,
      options = { "PvE", "PvP" } },

    { type = "text",     text = "=== Burst ===" },
    { type = "checkbox", uid = "FuryShowBurst",
      text = "Show burst HUD (set keybind via HUD)", default = true },
    { type = "slider",   uid = "FuryBurstMinHP",
      text = "Don't burst below enemy HP %",  default = 10, min = 5, max = 50 },

    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "FuryUseBloodthirst",
      text = "Bloodthirst",                   default = true },
    { type = "checkbox", uid = "FuryUseColossusSmash",
      text = "Colossus Smash",                default = true },
    { type = "checkbox", uid = "FuryUseRagingBlow",
      text = "Raging Blow",                   default = true },
    { type = "checkbox", uid = "FuryUseWildStrike",
      text = "Wild Strike",                   default = true },
    { type = "checkbox", uid = "FuryUseExecute",
      text = "Execute",                       default = true },
    { type = "checkbox", uid = "FuryUseHeroicStrike",
      text = "Heroic Strike (off-GCD dump)",  default = true },
    { type = "slider",   uid = "FuryHSRageThreshold",
      text = "Heroic Strike min rage",        default = 80, min = 30, max = 110 },
    { type = "checkbox", uid = "FuryHSDuringCS",
      text = "Heroic Strike during Colossus Smash", default = true },
    { type = "checkbox", uid = "FuryUseWhirlwind",
      text = "Whirlwind (AoE / Meat Cleaver)", default = true },
    { type = "checkbox", uid = "FuryUseCleave",
      text = "Cleave (AoE rage dump)",        default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "FuryUseRecklessness",
      text = "Recklessness",                  default = true },
    { type = "checkbox", uid = "FuryUseAvatar",
      text = "Avatar (talent)",               default = true },
    { type = "checkbox", uid = "FuryUseBloodbath",
      text = "Bloodbath (talent)",             default = true },
    { type = "checkbox", uid = "FuryUseStormBolt",
      text = "Storm Bolt (talent, on CD)",    default = true },
    { type = "checkbox", uid = "FuryUseDragonRoar",
      text = "Dragon Roar (talent)",          default = true },
    { type = "checkbox", uid = "FuryUseBladestorm",
      text = "Bladestorm (talent, AoE only)", default = true },
    { type = "checkbox", uid = "FuryUseShockwave",
      text = "Shockwave (talent)",            default = true },
    { type = "checkbox", uid = "FuryUseBerserkerRage",
      text = "Berserker Rage (Enrage trigger)", default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "FuryUseDieBySword",
      text = "Die by the Sword",              default = true },
    { type = "slider",   uid = "FuryDieBySwordHP",
      text = "Die by the Sword HP %",         default = 35, min = 10, max = 60 },
    { type = "checkbox", uid = "FuryUseRallyingCry",
      text = "Rallying Cry",                  default = true },
    { type = "slider",   uid = "FuryRallyingCryHP",
      text = "Rallying Cry HP %",             default = 25, min = 10, max = 50 },
    { type = "checkbox", uid = "FuryUseEnragedRegen",
      text = "Enraged Regeneration",          default = true },
    { type = "slider",   uid = "FuryEnragedRegenHP",
      text = "Enraged Regen HP %",            default = 40, min = 15, max = 70 },
    { type = "checkbox", uid = "FuryUseImpendingVictory",
      text = "Impending Victory (talent)",    default = true },
    { type = "slider",   uid = "FuryImpendingVictoryHP",
      text = "Impending Victory HP %",        default = 60, min = 20, max = 80 },

    { type = "text",     text = "=== PvP ===" },
    { type = "checkbox", uid = "FuryUseHamstring",
      text = "Maintain Hamstring",            default = true },
    { type = "checkbox", uid = "FuryUseSpellReflect",
      text = "Spell Reflection (on cast)",    default = true },
    { type = "checkbox", uid = "FuryUseMassReflect",
      text = "Mass Spell Reflection (talent)", default = true },
    { type = "checkbox", uid = "FuryUseIntimidatingShout",
      text = "Intimidating Shout",            default = false },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "FuryUsePummel",
      text = "Pummel",                        default = true },
    { type = "checkbox", uid = "FuryUseDisruptingShout",
      text = "Disrupting Shout (AoE kick)",   default = true },
    { type = "slider",   uid = "FuryDisruptingShoutCount",
      text = "Disrupting Shout min casters",  default = 2, min = 1, max = 5 },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "FuryMaintainShout",
      text = "Maintain Battle Shout",         default = true },
    { type = "checkbox", uid = "FuryAutoAttack",
      text = "Auto start attack",             default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "FuryAoeEnabled",
      text = "Use AoE rotation",              default = true },
    { type = "slider",   uid = "FuryAoeThreshold",
      text = "AoE enemy count",               default = 3, min = 2, max = 8 },
    { type = "slider",   uid = "FuryCleaveCount",
      text = "Cleave at enemies (replaces HS)", default = 2, min = 2, max = 5 },
  },
}

-- ── Helpers ──────────────────────────────────────────────────────

local function cd_remaining(spell)
  if not spell.IsKnown then return -1 end
  local cd = spell:GetCooldown()
  if cd and cd.on_cooldown and (cd.duration or 0) > 2 then
    return math.ceil(cd.remaining or 0)
  end
  return 0
end

local function is_pvp()
  return (PallasSettings.FuryMode or 0) == 1
end

local function is_enraged()
  return Me:HasAura("Enrage")
end

local function has_bloodsurge()
  return Me:HasAura("Bloodsurge")
end

local function raging_blow_charges()
  local ok, charges = pcall(game.spell_charges, Spell.RagingBlow.Id)
  if ok and charges then
    return charges.current or 0
  end
  return 0
end

local function in_cs_window(target)
  if not target then return false end
  return target:HasAura("Colossus Smash")
end

local function in_execute_phase(target)
  if not target then return false end
  return target.HealthPct > 0 and target.HealthPct < 20
end

local function meat_cleaver_stacks()
  local mc = Me:GetAura("Meat Cleaver")
  if not mc then return 0 end
  return mc.stacks or 0
end

-- ── Interrupts ───────────────────────────────────────────────────

local function TryInterrupt()
  if S("FuryUsePummel") then
    if Spell.Pummel:Interrupt() then return true end
  end

  if S("FuryUseDisruptingShout") and Spell.DisruptingShout.IsKnown then
    local min_casters = PallasSettings.FuryDisruptingShoutCount or 2
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

-- ── Defensives ───────────────────────────────────────────────────

local function UseDefensives(target)
  local hp = Me.HealthPct

  if S("FuryUseImpendingVictory") and hp < (PallasSettings.FuryImpendingVictoryHP or 60) then
    if target and Spell.ImpendingVictory:CastEx(target) then return true end
  end

  if S("FuryUseDieBySword") and hp < (PallasSettings.FuryDieBySwordHP or 35) then
    if Spell.DieByTheSword:CastEx(Me) then return true end
  end

  if S("FuryUseEnragedRegen") and hp < (PallasSettings.FuryEnragedRegenHP or 40) then
    if Spell.EnragedRegeneration:CastEx(Me) then return true end
  end

  if S("FuryUseRallyingCry") and hp < (PallasSettings.FuryRallyingCryHP or 25) then
    if Spell.RallyingCry:CastEx(Me) then return true end
  end

  return false
end

-- ── PvP Utilities ────────────────────────────────────────────────

local function TrySpellReflect()
  if not is_pvp() then return false end
  if not S("FuryUseSpellReflect") then return false end
  if not Spell.SpellReflection.IsKnown then return false end
  if Me:HasAura("Spell Reflection") then return false end

  for _, enemy in ipairs(Combat.Targets) do
    if enemy.IsPlayer and enemy:IsCastingOrChanneling() then
      if Me:GetDistance(enemy) <= 40 then
        if Spell.SpellReflection:CastEx(Me) then return true end
      end
    end
  end

  if S("FuryUseMassReflect") and Spell.MassSpellReflection.IsKnown then
    for _, enemy in ipairs(Combat.Targets) do
      if enemy.IsPlayer and enemy:IsCastingOrChanneling() then
        if Spell.MassSpellReflection:CastEx(Me) then return true end
      end
    end
  end

  return false
end

local function TryHamstring(target)
  if not is_pvp() then return false end
  if not S("FuryUseHamstring") then return false end
  if not target or not target.IsPlayer then return false end
  if not Me:InMeleeRange(target) then return false end
  if target:HasAura("Hamstring") then return false end
  return Spell.Hamstring:CastEx(target)
end

-- ── Heroic Strike / Cleave (off-GCD) ────────────────────────────

local function TryHeroicStrikeOrCleave(target)
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  local nearby = Combat:GetEnemiesWithinDistance(8)
  local cleave_count = PallasSettings.FuryCleaveCount or 2

  -- Use Cleave instead of HS when multiple targets
  if S("FuryUseCleave") and nearby >= cleave_count then
    local in_cs = in_cs_window(target)
    if Me:HasAura("Ultimatum") then
      return Spell.Cleave:CastEx(target)
    elseif in_cs and Me.Power >= 30 then
      return Spell.Cleave:CastEx(target)
    elseif Me.Power >= (PallasSettings.FuryHSRageThreshold or 80) then
      return Spell.Cleave:CastEx(target)
    end
    return false
  end

  if not S("FuryUseHeroicStrike") then return false end

  local hs_rage = PallasSettings.FuryHSRageThreshold or 80
  local in_cs = in_cs_window(target)
  local use_hs = false

  if Me:HasAura("Ultimatum") then
    use_hs = true
  elseif S("FuryHSDuringCS") and in_cs and Me.Power >= 30 then
    use_hs = true
  elseif Me.Power >= hs_rage then
    use_hs = true
  end

  if use_hs then
    return Spell.HeroicStrike:CastEx(target)
  end
  return false
end

-- ── Burst CDs ────────────────────────────────────────────────────

local function UseBurstCDs(target)
  if not burst_enabled then return false end
  if not target then return false end
  local min_hp = PallasSettings.FuryBurstMinHP or 10
  if target.HealthPct > 0 and target.HealthPct < min_hp then return false end

  local target_ttd = (TTD and target) and TTD.Get(target) or 999

  if S("FuryUseRecklessness") and target_ttd > 12 then
    if Spell.Recklessness:CastEx(Me) then return true end
  end

  if S("FuryUseAvatar") and Spell.Avatar.IsKnown and target_ttd > 10 then
    if Spell.Avatar:CastEx(Me) then return true end
  end

  if S("FuryUseBloodbath") and Spell.Bloodbath.IsKnown and target_ttd > 10 then
    if Spell.Bloodbath:CastEx(Me) then return true end
  end

  return false
end

-- ── Berserker Rage (Enrage maintenance) ──────────────────────────

local function TryBerserkerRage()
  if not S("FuryUseBerserkerRage") then return false end
  if is_enraged() then return false end
  return Spell.BerserkerRage:CastEx(Me)
end

-- ── Single-Target PvE ────────────────────────────────────────────

local function SingleTarget(target)
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  local executing = in_execute_phase(target)
  local in_cs = in_cs_window(target)
  local enraged = is_enraged()
  local rb_charges = raging_blow_charges()

  -- ── Execute Phase (<20%) ──
  if executing then
    -- Bloodthirst: only for Enrage maintenance if not Enraged
    if S("FuryUseBloodthirst") and not enraged then
      if Spell.Bloodthirst:CastEx(target) then return true end
    end

    -- Berserker Rage for Enrage if BT is on CD and not Enraged
    if not enraged then
      if TryBerserkerRage() then return true end
    end

    -- Colossus Smash
    if S("FuryUseColossusSmash") and Spell.ColossusSmash:CastEx(target) then return true end

    -- Execute (primary in execute phase, skip BT if we have enough rage during CS)
    if S("FuryUseExecute") then
      if Spell.Execute:CastEx(target) then return true end
    end

    -- Raging Blow during CS (still strong, costs no rage effectively)
    if S("FuryUseRagingBlow") and in_cs and enraged then
      if Spell.RagingBlow:CastEx(target) then return true end
    end

    -- Bloodthirst as filler (rage gen + Enrage fishing)
    if S("FuryUseBloodthirst") then
      if Spell.Bloodthirst:CastEx(target) then return true end
    end

    -- Raging Blow (spend charges even outside CS in execute)
    if S("FuryUseRagingBlow") and enraged then
      if Spell.RagingBlow:CastEx(target) then return true end
    end

    return false
  end

  -- ── Normal Rotation ──

  -- 1. Bloodthirst (primary — generates rage, procs Enrage and Bloodsurge)
  if S("FuryUseBloodthirst") and Spell.Bloodthirst:CastEx(target) then return true end

  -- 2. Berserker Rage if BT didn't produce Enrage
  if not is_enraged() then
    if TryBerserkerRage() then return true end
  end

  -- 3. Colossus Smash
  if S("FuryUseColossusSmash") and Spell.ColossusSmash:CastEx(target) then return true end

  -- 4. Storm Bolt (on CD for damage)
  if S("FuryUseStormBolt") and Spell.StormBolt.IsKnown then
    if Spell.StormBolt:CastEx(target) then return true end
  end

  -- 5. Raging Blow at 2 charges (prevent capping, or always during CS)
  if S("FuryUseRagingBlow") and enraged then
    if rb_charges >= 2 or in_cs then
      if Spell.RagingBlow:CastEx(target) then return true end
    end
  end

  -- 6. Wild Strike (Bloodsurge proc = free, instant)
  if S("FuryUseWildStrike") and has_bloodsurge() then
    if Spell.WildStrike:CastEx(target) then return true end
  end

  -- 7. Dragon Roar (talent, high damage)
  if S("FuryUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- 8. Raging Blow (single charge, lower priority outside CS)
  if S("FuryUseRagingBlow") and enraged then
    if Spell.RagingBlow:CastEx(target) then return true end
  end

  -- 9. Wild Strike as filler during CS (costs rage but worth it)
  if S("FuryUseWildStrike") and in_cs and Me.Power >= 30 then
    if Spell.WildStrike:CastEx(target) then return true end
  end

  -- 10. Shockwave (talent)
  if S("FuryUseShockwave") and Spell.Shockwave.IsKnown then
    if Spell.Shockwave:CastEx(Me) then return true end
  end

  -- 11. Wild Strike as general filler at high rage to avoid capping
  if S("FuryUseWildStrike") and Me.Power >= 90 then
    if Spell.WildStrike:CastEx(target) then return true end
  end

  -- 12. Battle Shout (filler, rage gen)
  if S("FuryMaintainShout") then
    if Spell.BattleShout:CastEx(Me) then return true end
  end

  return false
end

-- ── AoE Rotation ─────────────────────────────────────────────────

local function AoERotation(target)
  if not target then return false end

  local nearby = Combat:GetEnemiesWithinDistance(8)
  local enraged = is_enraged()

  -- Bladestorm (talent, massive AoE, highest priority)
  if S("FuryUseBladestorm") and Spell.Bladestorm.IsKnown and nearby >= 4 then
    if Spell.Bladestorm:CastEx(Me) then return true end
  end

  -- Dragon Roar
  if S("FuryUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- Bloodthirst (maintain Enrage for Raging Blow + Mastery scaling)
  if S("FuryUseBloodthirst") and Me:InMeleeRange(target) then
    if Spell.Bloodthirst:CastEx(target) then return true end
  end

  -- Berserker Rage for Enrage
  if not enraged then
    TryBerserkerRage()
    enraged = is_enraged()
  end

  -- Whirlwind (Meat Cleaver buff for Raging Blow to cleave)
  if S("FuryUseWhirlwind") then
    if Spell.Whirlwind:CastEx(Me) then return true end
  end

  -- Raging Blow (with Meat Cleaver, cleaves all nearby targets)
  if S("FuryUseRagingBlow") and enraged and Me:InMeleeRange(target) then
    if meat_cleaver_stacks() > 0 then
      if Spell.RagingBlow:CastEx(target) then return true end
    end
  end

  -- Colossus Smash (still worth it in AoE for armor debuff)
  if S("FuryUseColossusSmash") and Me:InMeleeRange(target) then
    if Spell.ColossusSmash:CastEx(target) then return true end
  end

  -- Shockwave (AoE + stun)
  if S("FuryUseShockwave") and Spell.Shockwave.IsKnown and nearby >= 3 then
    if Spell.Shockwave:CastEx(Me) then return true end
  end

  -- Raging Blow without Meat Cleaver (still good ST damage)
  if S("FuryUseRagingBlow") and enraged and Me:InMeleeRange(target) then
    if Spell.RagingBlow:CastEx(target) then return true end
  end

  -- Wild Strike (Bloodsurge proc)
  if S("FuryUseWildStrike") and has_bloodsurge() and Me:InMeleeRange(target) then
    if Spell.WildStrike:CastEx(target) then return true end
  end

  return false
end

-- ── Main Combat Function ─────────────────────────────────────────

local function FuryCombat()
  if Me.IsMounted then return end
  if Me:IsIncapacitated() then return end
  if Me:IsCastingOrChanneling() then return end

  -- Maintain Battle Shout OOC
  if not Me.InCombat then
    if S("FuryMaintainShout") and not Me:HasAura("Battle Shout") then
      Spell.BattleShout:CastEx(Me)
    end
    return
  end

  local target = Combat.BestTarget
  if not target then return end

  -- Auto attack
  if S("FuryAutoAttack") and Me:InMeleeRange(target) then
    if not Me:IsAutoAttacking() then
      Me:StartAttack(target)
    end
  end

  -- Berserker Rage: break fear/sap
  if S("FuryUseBerserkerRage") then
    if Me:IsFeared() or Me:IsConfused() then
      Spell.BerserkerRage:CastEx(Me)
    end
  end

  -- Off-GCD: Heroic Strike / Cleave
  TryHeroicStrikeOrCleave(target)

  -- Defensives
  if UseDefensives(target) then return end

  -- PvP: Spell Reflect
  if TrySpellReflect() then return end

  if Spell:IsGCDActive() then return end

  -- Interrupts
  if TryInterrupt() then return end

  -- Burst CDs (synced with CS)
  if UseBurstCDs(target) then return end

  -- PvP: Hamstring uptime
  if TryHamstring(target) then return end

  -- AoE vs ST
  local use_aoe = false
  if PallasSettings.FuryAoeEnabled then
    local nearby = Combat:GetEnemiesWithinDistance(8)
    use_aoe = nearby >= (PallasSettings.FuryAoeThreshold or 3)
  end

  if use_aoe then
    if not AoERotation(target) then
      SingleTarget(target)
    end
  else
    SingleTarget(target)
  end
end

-- ── Burst HUD ────────────────────────────────────────────────────

local function draw_burst_hud()
  if not Me then return end

  if burst_key_code == nil then
    burst_key_code = PallasSettings.FuryBurstKeyCode or 576
  end

  if not recording_burst_key and burst_key_code then
    if imgui.is_key_pressed(burst_key_code) then
      burst_enabled = not burst_enabled
    end
  end

  if not PallasSettings.FuryShowBurst then return end

  imgui.set_next_window_pos(450, 10, COND_FIRST)
  imgui.set_next_window_bg_alpha(0.8)
  local visible = imgui.begin_window("##FuryBurst", WF_HUD)
  if visible then
    if recording_burst_key then
      imgui.text_colored(1, 1, 0, 1, ">>> Press any key (Esc to cancel) <<<")
      for k = SCAN_MIN, SCAN_MAX do
        if imgui.is_key_pressed(k) then
          if k == 526 then
            recording_burst_key = false
          else
            burst_key_code = k
            PallasSettings.FuryBurstKeyCode = k
            recording_burst_key = false
          end
          break
        end
      end
    else
      local key_name = KEY_NAMES[burst_key_code] or ("Key" .. tostring(burst_key_code))

      local reck_rem = cd_remaining(Spell.Recklessness)
      local cs_rem   = cd_remaining(Spell.ColossusSmash)
      local enraged  = is_enraged()

      local cd_line = string.format("Reck: %ds | CS: %ds", reck_rem >= 0 and reck_rem or 0, cs_rem >= 0 and cs_rem or 0)

      if not burst_enabled then
        imgui.text_colored(0.6, 0.6, 0.6, 1, "FURY BURST: OFF")
        imgui.text_colored(0.5, 0.5, 0.5, 1, cd_line)
      elseif Me:HasAura("Recklessness") then
        imgui.text_colored(1, 0.2, 0.2, 1, "BURSTING!")
        imgui.text_colored(1, 0.6, 0.6, 1, cd_line)
      elseif reck_rem == 0 then
        imgui.text_colored(0.2, 1, 0.2, 1, "BURST: READY")
      else
        imgui.text_colored(1, 0.8, 0, 1, "BURST: ON")
        imgui.text_colored(1, 0.8, 0, 1, cd_line)
      end

      imgui.same_line(0, 8)
      if enraged then
        imgui.text_colored(0.2, 1, 0.2, 1, "ENRAGED")
      else
        imgui.text_colored(1, 0.3, 0.3, 1, "no enrage")
      end

      if burst_enabled then
        if imgui.button("Disable Burst", 110, 0) then burst_enabled = false end
      else
        if imgui.button("Enable Burst", 110, 0) then burst_enabled = true end
      end

      imgui.same_line()
      if imgui.button("[" .. key_name .. "] Set Key", 100, 0) then
        recording_burst_key = true
      end
    end
  end
  imgui.end_window()
end

Pallas._behavior_draw = draw_burst_hud

-- ── Export ────────────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = FuryCombat,
}

return { Options = options, Behaviors = behaviors }

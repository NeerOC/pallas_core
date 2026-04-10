-- ═══════════════════════════════════════════════════════════════════
-- Arms Warrior behavior (MoP 5.5.3)
--
-- Priority-based rotation with PvP/PvE mode, burst keybind toggle,
-- Colossus Smash window management, and Taste for Blood tracking.
--
-- Outside Colossus Smash:
--   1. Colossus Smash (opens damage window)
--   2. Bladestorm / Dragon Roar (big CDs between CS windows)
--   3. Mortal Strike
--   4. Overpower
--   5. Slam (only at 80+ rage — pool for CS windows)
--   6. Battle Shout (filler, rage gen)
--   Heroic Strike off-GCD at high rage / during CS / 5-stack TfB
--
-- During Colossus Smash:
--   MS → Slam → Overpower → Heroic Throw
--
-- Execute Phase (<20%):
--   CS (if not up) → MS → Execute → Overpower → Dragon Roar → Shout
--
-- AoE Priority (3+ targets):
--   SS → Thunder Clap → Bladestorm → CS → MS → Slam → Dragon Roar
--   → Whirlwind → Shout → Overpower
--
-- PvP Additions:
--   Hamstring uptime, Spell Reflection, Die by the Sword, defensive
--   stance dance at low HP, Intimidating Shout, Shattering Throw
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
  Name = "Warrior (Arms)",
  Widgets = {
    { type = "text",     text = "=== Mode ===" },
    { type = "combobox", uid = "ArmsMode",
      text = "Mode",                          default = 0,
      options = { "PvE", "PvP" } },

    { type = "text",     text = "=== Burst ===" },
    { type = "checkbox", uid = "ArmsShowBurst",
      text = "Show burst HUD (set keybind via HUD)", default = true },
    { type = "slider",   uid = "ArmsBurstMinHP",
      text = "Don't burst below enemy HP %",  default = 10, min = 5, max = 50 },

    { type = "text",     text = "=== Rotation Spells ===" },
    { type = "checkbox", uid = "ArmsUseMortalStrike",
      text = "Mortal Strike",                 default = true },
    { type = "checkbox", uid = "ArmsUseColossusSmash",
      text = "Colossus Smash",                default = true },
    { type = "checkbox", uid = "ArmsUseExecute",
      text = "Execute",                       default = true },
    { type = "checkbox", uid = "ArmsUseOverpower",
      text = "Overpower",                     default = true },
    { type = "checkbox", uid = "ArmsUseSlam",
      text = "Slam",                          default = true },
    { type = "checkbox", uid = "ArmsUseHeroicStrike",
      text = "Heroic Strike (off-GCD dump)",  default = true },
    { type = "slider",   uid = "ArmsHSRageThreshold",
      text = "Heroic Strike min rage",        default = 80, min = 30, max = 110 },
    { type = "checkbox", uid = "ArmsHSDuringCS",
      text = "Heroic Strike during Colossus Smash", default = true },
    { type = "checkbox", uid = "ArmsUseThunderClap",
      text = "Thunder Clap (Weakened Blows)", default = true },
    { type = "checkbox", uid = "ArmsUseHeroicThrow",
      text = "Heroic Throw (CS window filler)", default = true },
    { type = "checkbox", uid = "ArmsUseSweepingStrikes",
      text = "Sweeping Strikes (AoE)",        default = true },
    { type = "checkbox", uid = "ArmsUseWhirlwind",
      text = "Whirlwind (AoE)",               default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "ArmsUseRecklessness",
      text = "Recklessness",                  default = true },
    { type = "checkbox", uid = "ArmsUseAvatar",
      text = "Avatar (talent)",               default = true },
    { type = "checkbox", uid = "ArmsUseBloodbath",
      text = "Bloodbath (talent)",             default = true },
    { type = "checkbox", uid = "ArmsUseStormBolt",
      text = "Storm Bolt (talent, on CD)",    default = true },
    { type = "checkbox", uid = "ArmsUseDragonRoar",
      text = "Dragon Roar (talent)",          default = true },
    { type = "checkbox", uid = "ArmsUseBladestorm",
      text = "Bladestorm (talent)",          default = true },
    { type = "checkbox", uid = "ArmsBladestormAoeOnly",
      text = "Bladestorm AoE only",          default = false },
    { type = "checkbox", uid = "ArmsUseShockwave",
      text = "Shockwave (talent)",            default = true },
    { type = "checkbox", uid = "ArmsUseBerserkerRage",
      text = "Berserker Rage (fear break + Enrage uptime)", default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "ArmsUseDieBySword",
      text = "Die by the Sword",              default = true },
    { type = "slider",   uid = "ArmsDieBySwordHP",
      text = "Die by the Sword HP %",         default = 35, min = 10, max = 60 },
    { type = "checkbox", uid = "ArmsUseShieldWall",
      text = "Shield Wall",                   default = true },
    { type = "slider",   uid = "ArmsShieldWallHP",
      text = "Shield Wall HP %",              default = 25, min = 10, max = 50 },
    { type = "checkbox", uid = "ArmsUseRallyingCry",
      text = "Rallying Cry",                  default = true },
    { type = "slider",   uid = "ArmsRallyingCryHP",
      text = "Rallying Cry HP %",             default = 25, min = 10, max = 50 },
    { type = "checkbox", uid = "ArmsUseEnragedRegen",
      text = "Enraged Regeneration",          default = true },
    { type = "slider",   uid = "ArmsEnragedRegenHP",
      text = "Enraged Regen HP %",            default = 40, min = 15, max = 70 },
    { type = "checkbox", uid = "ArmsUseImpendingVictory",
      text = "Impending Victory (talent)",    default = true },
    { type = "slider",   uid = "ArmsImpendingVictoryHP",
      text = "Impending Victory HP %",        default = 60, min = 20, max = 80 },
    { type = "checkbox", uid = "ArmsUseSpellReflect",
      text = "Smart Spell Reflection (react to incoming casts)", default = true },
    { type = "checkbox", uid = "ArmsUseMassReflect",
      text = "Mass Spell Reflection (talent)", default = true },
    { type = "slider",   uid = "ArmsReflectReactTime",
      text = "Reflect react time (sec remaining)", default = 1.5, min = 0.1, max = 3.0, step = 0.1 },

    { type = "text",     text = "=== PvP ===" },
    { type = "checkbox", uid = "ArmsUseHamstring",
      text = "Maintain Hamstring",            default = true },
    { type = "checkbox", uid = "ArmsUseIntimidatingShout",
      text = "Intimidating Shout (PvP fear)", default = false },
    { type = "checkbox", uid = "ArmsUseShatteringThrow",
      text = "Shattering Throw (on immune)",  default = true },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "ArmsUsePummel",
      text = "Pummel",                        default = true },
    { type = "checkbox", uid = "ArmsUseDisruptingShout",
      text = "Disrupting Shout (AoE kick)",   default = true },
    { type = "slider",   uid = "ArmsDisruptingShoutCount",
      text = "Disrupting Shout min casters",  default = 2, min = 1, max = 5 },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "ArmsMaintainShout",
      text = "Maintain Battle Shout",         default = true },
    { type = "checkbox", uid = "ArmsAutoAttack",
      text = "Auto start attack",             default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "ArmsAoeEnabled",
      text = "Use AoE rotation",              default = true },
    { type = "slider",   uid = "ArmsAoeThreshold",
      text = "AoE enemy count",               default = 3, min = 2, max = 8 },
    { type = "slider",   uid = "ArmsSweepingStrikesCount",
      text = "Sweeping Strikes at enemies",   default = 2, min = 2, max = 5 },
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
  return (PallasSettings.ArmsMode or 0) == 1
end

local function in_cs_window(target)
  if not target then return false end
  local cs = target:GetAura("Colossus Smash")
  return cs ~= nil
end

local function in_execute_phase(target)
  if not target then return false end
  return target.HealthPct > 0 and target.HealthPct < 20
end

local function has_sudden_death()
  return Me:HasAura("Sudden Death")
end

local function taste_for_blood_stacks()
  local tfb = Me:GetAura("Taste for Blood")
  if not tfb then return 0 end
  return tfb.stacks or 0
end

-- ── Interrupts ───────────────────────────────────────────────────

local function TryInterrupt()
  if S("ArmsUsePummel") then
    if Spell.Pummel:Interrupt() then return true end
  end

  if S("ArmsUseDisruptingShout") and Spell.DisruptingShout.IsKnown then
    local min_casters = PallasSettings.ArmsDisruptingShoutCount or 2
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

  if S("ArmsUseImpendingVictory") and hp < (PallasSettings.ArmsImpendingVictoryHP or 60) then
    if target and Spell.ImpendingVictory:CastEx(target) then return true end
  end

  if S("ArmsUseDieBySword") and hp < (PallasSettings.ArmsDieBySwordHP or 35) then
    if Spell.DieByTheSword:CastEx(Me) then return true end
  end

  if S("ArmsUseShieldWall") and hp < (PallasSettings.ArmsShieldWallHP or 25) then
    if Spell.ShieldWall:CastEx(Me) then return true end
  end

  if S("ArmsUseEnragedRegen") and hp < (PallasSettings.ArmsEnragedRegenHP or 40) then
    if Spell.EnragedRegeneration:CastEx(Me) then return true end
  end

  if S("ArmsUseRallyingCry") and hp < (PallasSettings.ArmsRallyingCryHP or 25) then
    if Spell.RallyingCry:CastEx(Me) then return true end
  end

  return false
end

-- ── Spell Reflection (Smart — react to incoming casts) ──────────

local SCHOOL_PHYSICAL = 1

--- Detect if an enemy is casting a non-physical spell at us that is
--- close to finishing, and reflect it.  Works in both PvE and PvP.
--- Falls back to Mass Spell Reflection when regular SR is on cooldown.
local function TrySpellReflect()
  if not S("ArmsUseSpellReflect") then return false end
  if Me:HasAura("Spell Reflection") then return false end

  local sr_ready   = Spell.SpellReflection.IsKnown and Spell.SpellReflection:IsReady()
  local msr_ready  = S("ArmsUseMassReflect")
      and Spell.MassSpellReflection.IsKnown
      and Spell.MassSpellReflection:IsReady()
  if not sr_ready and not msr_ready then return false end

  local react   = PallasSettings.ArmsReflectReactTime or 1.5
  local my_guid = Me.Guid
  local my_lo   = Me.guid_lo
  local my_hi   = Me.guid_hi
  local now_gt  = nil

  for _, enemy in ipairs(Combat.Targets) do
    if enemy.IsDead then goto next_reflect end
    if not enemy.IsCasting and not enemy.IsChanneling then goto next_reflect end

    local spell_id = enemy.IsCasting and enemy.CastingSpellId
        or enemy.IsChanneling and enemy.ChannelingSpellId
    if not spell_id or spell_id == 0 then goto next_reflect end

    -- Is this mob targeting us?
    local targeting_us = false
    if (enemy.CastTargetLo or 0) ~= 0 or (enemy.CastTargetHi or 0) ~= 0 then
      targeting_us = (enemy.CastTargetLo == my_lo and enemy.CastTargetHi == my_hi)
    else
      local tok, tgt = pcall(game.unit_target, enemy.obj_ptr)
      if tok and tgt and tgt.guid == my_guid then
        targeting_us = true
      end
    end
    if not targeting_us then goto next_reflect end

    -- Skip physical spells (can't be reflected)
    local sok, school = pcall(game.get_spell_school, spell_id)
    if sok and school == SCHOOL_PHYSICAL then goto next_reflect end

    -- Compute remaining cast time
    local remaining = 999

    if Me.Target and not Me.Target.IsDead and Me.Target.Guid == enemy.Guid then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        remaining = cast.remaining or 999
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then remaining = chan.remaining or 999 end
      end
    end

    if remaining == 999 then
      local cast_end = enemy.IsCasting and enemy.CastEnd or enemy.ChannelEnd
      if cast_end and cast_end > 0 then
        if not now_gt then
          local ok, t = pcall(game.game_time)
          now_gt = ok and t or 0
        end
        if now_gt > 0 then
          remaining = cast_end - now_gt
          if remaining < 0 then remaining = 0 end
        end
      end
    end

    if remaining <= react then
      if sr_ready then
        if Spell.SpellReflection:CastEx(Me) then return true end
      end
      if msr_ready then
        if Spell.MassSpellReflection:CastEx(Me) then return true end
      end
    end

    ::next_reflect::
  end
  return false
end

-- ── PvP Utilities ────────────────────────────────────────────────

local function TryHamstring(target)
  if not is_pvp() then return false end
  if not S("ArmsUseHamstring") then return false end
  if not target then return false end
  if not target.IsPlayer then return false end
  if not Me:InMeleeRange(target) then return false end
  if target:HasAura("Hamstring") then return false end
  return Spell.Hamstring:CastEx(target)
end

local function TryShatteringThrow()
  if not is_pvp() then return false end
  if not S("ArmsUseShatteringThrow") then return false end
  if not Spell.ShatteringThrow.IsKnown then return false end

  for _, enemy in ipairs(Combat.Targets) do
    if enemy:IsImmune() and Me:GetDistance(enemy) <= 30 then
      if Spell.ShatteringThrow:CastEx(enemy) then return true end
    end
  end
  return false
end

local function TryIntimidatingShout(target)
  if not is_pvp() then return false end
  if not S("ArmsUseIntimidatingShout") then return false end
  if not Spell.IntimidatingShout.IsKnown then return false end

  -- Fear a nearby enemy that ISN'T our kill target
  for _, enemy in ipairs(Combat.Targets) do
    if not enemy.IsDead and enemy ~= target and Me:GetDistance(enemy) <= 8 then
      return Spell.IntimidatingShout:CastEx(enemy)
    end
  end
  return false
end

-- ── Heroic Strike (off-GCD) ─────────────────────────────────────

local function TryHeroicStrike(target)
  if not S("ArmsUseHeroicStrike") then return false end
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  local hs_rage = PallasSettings.ArmsHSRageThreshold or 80
  local use_hs = false

  if Me:HasAura("Ultimatum") then
    use_hs = true
  elseif S("ArmsHSDuringCS") and in_cs_window(target) and Me.Power >= 30 then
    use_hs = true
  elseif taste_for_blood_stacks() >= 5 then
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
  local min_hp = PallasSettings.ArmsBurstMinHP or 10
  if target.HealthPct > 0 and target.HealthPct < min_hp then return false end

  local target_ttd = (TTD and target) and TTD.Get(target) or 999

  if S("ArmsUseRecklessness") and target_ttd > 12 then
    if Spell.Recklessness:CastEx(Me) then return true end
  end

  if S("ArmsUseAvatar") and Spell.Avatar.IsKnown and target_ttd > 10 then
    if Spell.Avatar:CastEx(Me) then return true end
  end

  if S("ArmsUseBloodbath") and Spell.Bloodbath.IsKnown and target_ttd > 10 then
    if Spell.Bloodbath:CastEx(Me) then return true end
  end

  return false
end

-- ── Single-Target PvE ────────────────────────────────────────────
-- Guide structure: rotation changes based on CS debuff and execute phase.
--   Outside CS: CS > Bladestorm/DR > MS > OP > Slam@80rage > Shout
--   During  CS: MS > Slam > OP > Heroic Throw
--   Execute:    CS > MS > Execute > OP > DR > Shout

local function SingleTarget(target)
  if not target then return false end
  if not Me:InMeleeRange(target) then return false end

  local executing = in_execute_phase(target)
  local in_cs = in_cs_window(target)

  -- Sudden Death proc: free Execute at any HP, always consume immediately
  if S("ArmsUseExecute") and has_sudden_death() then
    if Spell.Execute:CastEx(target, { skipUsable = true }) then return true end
  end

  -- ── Execute Phase (<20%) ──
  if executing then
    if S("ArmsUseColossusSmash") and not in_cs then
      if Spell.ColossusSmash:CastEx(target) then return true end
    end
    if S("ArmsUseMortalStrike") and Spell.MortalStrike:CastEx(target) then return true end
    if S("ArmsUseExecute") and Spell.Execute:CastEx(target) then return true end
    if S("ArmsUseOverpower") and Spell.Overpower:CastEx(target) then return true end
    if S("ArmsUseDragonRoar") and Spell.DragonRoar.IsKnown then
      if Spell.DragonRoar:CastEx(Me) then return true end
    end
    if S("ArmsMaintainShout") and Spell.BattleShout:CastEx(Me) then return true end
    return false
  end

  -- ── During Colossus Smash Window ──
  if in_cs then
    if S("ArmsUseMortalStrike") and Spell.MortalStrike:CastEx(target) then return true end
    if S("ArmsUseSlam") and Me.Power >= 20 then
      if Spell.Slam:CastEx(target) then return true end
    end
    if S("ArmsUseOverpower") and Spell.Overpower:CastEx(target) then return true end
    if S("ArmsUseHeroicThrow") and Spell.HeroicThrow.IsKnown then
      if Spell.HeroicThrow:CastEx(target) then return true end
    end
    if S("ArmsMaintainShout") and Spell.BattleShout:CastEx(Me) then return true end
    return false
  end

  -- ── Outside Colossus Smash ──

  -- 1. Colossus Smash (top priority — opens damage window)
  if S("ArmsUseColossusSmash") and Spell.ColossusSmash:CastEx(target) then return true end

  -- 2. Bladestorm / Dragon Roar (big damage CDs, use between CS windows)
  if S("ArmsUseBladestorm") and not S("ArmsBladestormAoeOnly") and Spell.Bladestorm.IsKnown then
    if Spell.Bladestorm:CastEx(Me) then return true end
  end
  if S("ArmsUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- 2b. Storm Bolt (on CD for damage)
  if S("ArmsUseStormBolt") and Spell.StormBolt.IsKnown then
    if Spell.StormBolt:CastEx(target) then return true end
  end

  -- 3. Mortal Strike
  if S("ArmsUseMortalStrike") and Spell.MortalStrike:CastEx(target) then return true end

  -- 4. Overpower (never cap TfB stacks)
  if S("ArmsUseOverpower") and Spell.Overpower:CastEx(target) then return true end

  -- 5. Slam (only at high rage outside CS — save rage for CS windows)
  if S("ArmsUseSlam") and Me.Power >= 80 then
    if Spell.Slam:CastEx(target) then return true end
  end

  -- 6. Thunder Clap (Weakened Blows maintenance)
  if S("ArmsUseThunderClap") and not target:HasAura("Weakened Blows") then
    if Spell.ThunderClap:CastEx(Me) then return true end
  end

  -- 7. Battle Shout (filler for rage gen)
  if S("ArmsMaintainShout") and Spell.BattleShout:CastEx(Me) then return true end

  return false
end

-- ── AoE Rotation (3+ targets) ───────────────────────────────────
-- Guide: SS > Thunder Clap > Bladestorm > CS > MS > Slam > DR > Shout > OP

local function AoERotation(target)
  if not target then return false end

  local nearby = Combat:GetEnemiesWithinDistance(8)

  -- 1. Sweeping Strikes (2+ targets, 10s buff)
  local ss_count = PallasSettings.ArmsSweepingStrikesCount or 2
  if S("ArmsUseSweepingStrikes") and nearby >= ss_count then
    if not Me:HasAura("Sweeping Strikes") then
      if Spell.SweepingStrikes:CastEx(Me) then return true end
    end
  end

  -- 2. Thunder Clap (refresh Deep Wounds on all targets via Blood and Thunder)
  if S("ArmsUseThunderClap") then
    if Spell.ThunderClap:CastEx(Me) then return true end
  end

  -- 3. Bladestorm (talent, massive AoE)
  if S("ArmsUseBladestorm") and Spell.Bladestorm.IsKnown then
    if Spell.Bladestorm:CastEx(Me) then return true end
  end

  -- 4. Colossus Smash (on highest-health target)
  if S("ArmsUseColossusSmash") and Me:InMeleeRange(target) then
    if Spell.ColossusSmash:CastEx(target) then return true end
  end

  -- 5. Mortal Strike
  if S("ArmsUseMortalStrike") and Me:InMeleeRange(target) then
    if Spell.MortalStrike:CastEx(target) then return true end
  end

  -- 6. Slam
  if S("ArmsUseSlam") and Me:InMeleeRange(target) and Me.Power >= 20 then
    if Spell.Slam:CastEx(target) then return true end
  end

  -- 7. Dragon Roar
  if S("ArmsUseDragonRoar") and Spell.DragonRoar.IsKnown then
    if Spell.DragonRoar:CastEx(Me) then return true end
  end

  -- 8. Shockwave (talent, AoE + stun)
  if S("ArmsUseShockwave") and Spell.Shockwave.IsKnown and nearby >= 3 then
    if Spell.Shockwave:CastEx(Me) then return true end
  end

  -- 9. Whirlwind
  if S("ArmsUseWhirlwind") and nearby >= 2 then
    if Spell.Whirlwind:CastEx(Me) then return true end
  end

  -- 10. Battle Shout (filler)
  if S("ArmsMaintainShout") and Spell.BattleShout:CastEx(Me) then return true end

  -- 11. Overpower
  if S("ArmsUseOverpower") and Me:InMeleeRange(target) then
    if Spell.Overpower:CastEx(target) then return true end
  end

  return false
end

-- ── Main Combat Function ─────────────────────────────────────────

local function ArmsCombat()
  if Me.IsMounted then return end
  if Me:IsIncapacitated() then return end
  if Me:IsCastingOrChanneling() then return end

  -- Maintain Battle Shout OOC
  if not Me.InCombat then
    if S("ArmsMaintainShout") and not Me:HasAura("Battle Shout") then
      Spell.BattleShout:CastEx(Me)
    end
    return
  end

  local target = Combat.BestTarget
  if not target then return end

  -- Auto attack
  if S("ArmsAutoAttack") and Me:InMeleeRange(target) then
    if not Me:IsAutoAttacking() then
      Me:StartAttack(target)
    end
  end

  -- Berserker Rage: break fear/sap + offensive Enrage uptime
  if S("ArmsUseBerserkerRage") then
    if Me:IsFeared() or Me:IsConfused() then
      Spell.BerserkerRage:CastEx(Me)
    elseif not Me:HasAura("Enrage") then
      Spell.BerserkerRage:CastEx(Me)
    end
  end

  -- Off-GCD: Heroic Strike
  TryHeroicStrike(target)

  -- Defensives
  if UseDefensives(target) then return end

  -- Smart Spell Reflect (react to incoming non-physical casts targeting us)
  if TrySpellReflect() then return end

  -- PvP: Shattering Throw on immune targets
  if TryShatteringThrow() then return end

  -- PvP: Intimidating Shout (fear)
  if TryIntimidatingShout(target) then return end

  if Spell:IsGCDActive() then return end

  -- Interrupts
  if TryInterrupt() then return end

  -- Burst CDs (synced with CS)
  if UseBurstCDs(target) then return end

  -- PvP: Hamstring uptime
  if TryHamstring(target) then return end

  -- AoE vs ST
  local use_aoe = false
  if PallasSettings.ArmsAoeEnabled then
    local nearby = Combat:GetEnemiesWithinDistance(8)
    use_aoe = nearby >= (PallasSettings.ArmsAoeThreshold or 3)
  end

  if use_aoe then
    if not AoERotation(target) then
      SingleTarget(target)
    end
  else
    -- Sweeping Strikes at 2+ even in ST mode (guide: "use SS and follow ST rotation")
    local ss_count = PallasSettings.ArmsSweepingStrikesCount or 2
    if S("ArmsUseSweepingStrikes") and Combat:GetEnemiesWithinDistance(8) >= ss_count then
      if not Me:HasAura("Sweeping Strikes") then
        if Spell.SweepingStrikes:CastEx(Me) then return end
      end
    end
    SingleTarget(target)
  end
end

-- ── Burst HUD ────────────────────────────────────────────────────

local function draw_burst_hud()
  if not Me then return end

  if burst_key_code == nil then
    burst_key_code = PallasSettings.ArmsBurstKeyCode or 576
  end

  if not recording_burst_key and burst_key_code then
    if imgui.is_key_pressed(burst_key_code) then
      burst_enabled = not burst_enabled
    end
  end

  if not PallasSettings.ArmsShowBurst then return end

  imgui.set_next_window_pos(450, 10, COND_FIRST)
  imgui.set_next_window_bg_alpha(0.8)
  local visible = imgui.begin_window("##ArmsBurst", WF_HUD)
  if visible then
    if recording_burst_key then
      imgui.text_colored(1, 1, 0, 1, ">>> Press any key (Esc to cancel) <<<")
      for k = SCAN_MIN, SCAN_MAX do
        if imgui.is_key_pressed(k) then
          if k == 526 then
            recording_burst_key = false
          else
            burst_key_code = k
            PallasSettings.ArmsBurstKeyCode = k
            recording_burst_key = false
          end
          break
        end
      end
    else
      local key_name = KEY_NAMES[burst_key_code] or ("Key" .. tostring(burst_key_code))

      local reck_rem = cd_remaining(Spell.Recklessness)
      local cs_rem   = cd_remaining(Spell.ColossusSmash)

      local cd_line = string.format("Reck: %ds | CS: %ds", reck_rem >= 0 and reck_rem or 0, cs_rem >= 0 and cs_rem or 0)

      if not burst_enabled then
        imgui.text_colored(0.6, 0.6, 0.6, 1, "ARMS BURST: OFF")
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
  [BehaviorType.Combat] = ArmsCombat,
}

return { Options = options, Behaviors = behaviors }

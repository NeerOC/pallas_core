-- ═══════════════════════════════════════════════════════════════════
-- Blood Death Knight behavior (MoP 5.5.3)
--
-- Works at any level: falls through unknown spells to baseline
-- abilities (Icy Touch, Plague Strike, Blood Strike, Death Coil).
--
-- Endgame Single-Target Priority:
--   1. Blood Presence (maintain)
--   2. Horn of Winter (maintain buff)
--   3. Diseases (Outbreak → Icy Touch + Plague Strike fallback)
--   4. Dancing Rune Weapon on CD
--   5. Bone Shield (maintain)
--   6. Crimson Scourge proc → Blood Boil / Death and Decay
--   7. Death Strike (primary heal/shield)
--   8. Soul Reaper (<35%) / Heart Strike / Blood Strike (Blood rune)
--   9. Death and Decay on CD
--  10. Rune Strike / Death Coil (Runic Power dump)
--  11. Empower Rune Weapon (rune starved)
--  12. Horn of Winter / Icy Touch (filler)
--
-- AoE (3+ enemies):
--   Death and Decay > diseases > Pestilence (spread) >
--   Blood Boil (replaces Heart/Blood Strike) > Death Strike >
--   Rune Strike / Death Coil > Horn of Winter
--
-- Defensives: Vampiric Blood, Icebound Fortitude, Anti-Magic Shell,
--   Rune Tap, Death Pact
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Death Knight (Blood)",
  Widgets = {
    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "BloodUseDRW",
      text = "Use Dancing Rune Weapon",  default = true },
    { type = "checkbox", uid = "BloodUseERW",
      text = "Use Empower Rune Weapon (no runes)", default = true },

    { type = "text",     text = "=== Defensives ===" },
    { type = "checkbox", uid = "BloodUseVampiricBlood",
      text = "Use Vampiric Blood",       default = true },
    { type = "slider",   uid = "BloodVBThreshold",
      text = "Vampiric Blood HP %",      default = 50, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseIBF",
      text = "Use Icebound Fortitude",   default = true },
    { type = "slider",   uid = "BloodIBFThreshold",
      text = "IBF HP %",                 default = 35, min = 15, max = 60 },
    { type = "checkbox", uid = "BloodUseAMS",
      text = "Use Anti-Magic Shell",     default = false },
    { type = "checkbox", uid = "BloodUseRuneTap",
      text = "Use Rune Tap",             default = true },
    { type = "slider",   uid = "BloodRuneTapThreshold",
      text = "Rune Tap HP %",            default = 60, min = 20, max = 80 },
    { type = "checkbox", uid = "BloodUseDeathPact",
      text = "Use Death Pact (sacrifice ghoul)", default = false },
    { type = "slider",   uid = "BloodDeathPactThreshold",
      text = "Death Pact HP %",          default = 25, min = 10, max = 50 },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "BloodMaintainHoW",
      text = "Maintain Horn of Winter",  default = true },
    { type = "checkbox", uid = "BloodMaintainPresence",
      text = "Auto Blood Presence",      default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "BloodAoeEnabled",
      text = "Use AoE rotation (3+ enemies)", default = true },
    { type = "slider",   uid = "BloodAoeThreshold",
      text = "AoE enemy count",          default = 3, min = 2, max = 8 },

    { type = "text",     text = "=== Runic Power ===" },
    { type = "slider",   uid = "BloodRSThreshold",
      text = "Rune Strike above RP",     default = 80, min = 30, max = 110 },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 10

-- ── Helpers ────────────────────────────────────────────────────

local function has_diseases(target)
  return target:HasAura("Frost Fever") and target:HasAura("Blood Plague")
end

local function diseases_expiring(target)
  local ff = target:GetAura("Frost Fever")
  local bp = target:GetAura("Blood Plague")
  if not ff or not bp then return true end
  local ff_rem = ff.remaining or 0
  local bp_rem = bp.remaining or 0
  return ff_rem < 4 or bp_rem < 4
end

--- Apply diseases: Outbreak if known, otherwise Icy Touch + Plague Strike.
local function ApplyDiseases(target)
  if has_diseases(target) then return false end

  -- Outbreak (instant, applies both — learned at higher levels)
  if Spell.Outbreak:CastEx(target) then return true end

  -- Fallback: Icy Touch (Frost Fever) + Plague Strike (Blood Plague)
  if not target:HasAura("Frost Fever") then
    if Spell.IcyTouch:CastEx(target) then return true end
  end
  if not target:HasAura("Blood Plague") then
    if Spell.PlagueStrike:CastEx(target) then return true end
  end

  return false
end

--- Spend Runic Power: Rune Strike if known, else Death Coil.
local function SpendRP(target)
  local threshold = PallasSettings.BloodRSThreshold or 80
  if Me.Power < threshold then return false end

  if Spell.RuneStrike:CastEx(target) then return true end
  if Spell.DeathCoil:CastEx(target) then return true end
  return false
end

-- ── Defensives ─────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  if PallasSettings.BloodUseVampiricBlood and hp < (PallasSettings.BloodVBThreshold or 50) then
    if Spell.VampiricBlood:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseRuneTap and hp < (PallasSettings.BloodRuneTapThreshold or 60) then
    if Spell.RuneTap:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseIBF and hp < (PallasSettings.BloodIBFThreshold or 35) then
    if Spell.IceboundFortitude:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseAMS then
    if Spell.AntiMagicShell:CastEx(Me) then return true end
  end

  if PallasSettings.BloodUseDeathPact and hp < (PallasSettings.BloodDeathPactThreshold or 25) then
    if Spell.DeathPact:CastEx(Me) then return true end
  end

  return false
end

-- ── Single-Target Priority ────────────────────────────────────

local function SingleTarget(target)
  -- 1. Diseases
  if ApplyDiseases(target) then return true end

  -- 2. Dancing Rune Weapon on CD
  if PallasSettings.BloodUseDRW then
    if Spell.DancingRuneWeapon:CastEx(Me) then return true end
  end

  -- 3. Bone Shield (maintain)
  if not Me:HasAura("Bone Shield") then
    if Spell.BoneShield:CastEx(Me) then return true end
  end

  -- 4. Crimson Scourge proc
  if Me:HasAura("Crimson Scourge") then
    if diseases_expiring(target) then
      if Spell.BloodBoil:CastEx(target) then return true end
    else
      if Spell.DeathAndDecay:CastAtPos(target) then return true end
    end
  end

  -- 5. Death Strike (primary heal + Blood Shield)
  if Spell.DeathStrike:CastEx(target) then return true end

  -- 6. Soul Reaper (<35%), Heart Strike, Blood Strike (Blood rune spenders)
  if target.HealthPct > 0 and target.HealthPct < 35 then
    if Spell.SoulReaper:CastEx(target) then return true end
  end
  if Spell.HeartStrike:CastEx(target) then return true end
  if Spell.BloodStrike:CastEx(target) then return true end

  -- 7. Death and Decay on CD
  if Spell.DeathAndDecay:CastAtPos(target) then return true end

  -- 8. Blood Boil to refresh expiring diseases
  if diseases_expiring(target) then
    if Spell.BloodBoil:CastEx(target) then return true end
  end

  -- 9. Runic Power dump (Rune Strike → Death Coil)
  if SpendRP(target) then return true end

  -- 10. Empower Rune Weapon (rune + RP starved)
  if PallasSettings.BloodUseERW and Me.Power < 40 then
    if Spell.EmpowerRuneWeapon:CastEx(Me) then return true end
  end

  -- 11. Horn of Winter (filler — generates RP)
  if Spell.HornOfWinter:CastEx(Me) then return true end

  -- 12. Baseline fillers when nothing else is available
  if Spell.IcyTouch:CastEx(target) then return true end
  if Spell.PlagueStrike:CastEx(target) then return true end

  return false
end

-- ── AoE Priority ──────────────────────────────────────────────

local function AoERotation(target)
  -- 1. Death and Decay
  if Spell.DeathAndDecay:CastAtPos(target) then return true end

  -- 2. Diseases
  if ApplyDiseases(target) then return true end

  -- 3. Pestilence to spread diseases
  if has_diseases(target) then
    if Spell.Pestilence:CastEx(target) then return true end
  end

  -- 4. Bone Shield
  if not Me:HasAura("Bone Shield") then
    if Spell.BoneShield:CastEx(Me) then return true end
  end

  -- 5. Crimson Scourge proc
  if Me:HasAura("Crimson Scourge") then
    if Spell.BloodBoil:CastEx(target) then return true end
  end

  -- 6. Blood Boil (replaces Heart/Blood Strike in AoE)
  if Spell.BloodBoil:CastEx(target) then return true end

  -- 7. Death Strike (self-sustain)
  if Spell.DeathStrike:CastEx(target) then return true end

  -- 8. Blood Strike (AoE fallback when Blood Boil not known)
  if Spell.BloodStrike:CastEx(target) then return true end

  -- 9. RP dump
  if SpendRP(target) then return true end

  -- 10. Empower Rune Weapon
  if PallasSettings.BloodUseERW and Me.Power < 40 then
    if Spell.EmpowerRuneWeapon:CastEx(Me) then return true end
  end

  -- 11. Horn of Winter / baseline fillers
  if Spell.HornOfWinter:CastEx(Me) then return true end
  if Spell.IcyTouch:CastEx(target) then return true end
  if Spell.PlagueStrike:CastEx(target) then return true end

  return false
end

-- ── Main Combat Function ──────────────────────────────────────

local function BloodDKCombat()
  local target = Combat.BestTarget
  if not target then return end

  -- Maintain Blood Presence
  if PallasSettings.BloodMaintainPresence then
    if not Me:HasAura("Blood Presence") then
      if Spell.BloodPresence:CastEx(Me) then return end
    end
  end

  -- Maintain Horn of Winter buff
  if PallasSettings.BloodMaintainHoW then
    if not Me:HasAura("Horn of Winter") then
      if Spell.HornOfWinter:CastEx(Me) then return end
    end
  end

  -- Defensives
  if UseDefensives() then return end

  -- Determine AoE
  local use_aoe = false
  if PallasSettings.BloodAoeEnabled then
    local nearby = Combat:GetTargetsAround(target, AOE_RANGE)
    use_aoe = nearby >= (PallasSettings.BloodAoeThreshold or 3)
  end

  if use_aoe then
    AoERotation(target)
  else
    SingleTarget(target)
  end
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = BloodDKCombat,
}

return { Options = options, Behaviors = behaviors }

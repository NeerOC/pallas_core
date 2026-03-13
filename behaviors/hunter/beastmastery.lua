-- ═══════════════════════════════════════════════════════════════════
-- Jmr-BM — Beast Mastery Hunter behavior
--
-- Single-Target Priority:
--   1. Maintain Hunter's Mark
--   2. Maintain Serpent Sting
--   3. Stampede on CD
--   4. Rapid Fire on CD
--   5. Bestial Wrath on CD
--   6. Rabid (pet) on CD
--   7. Dire Beast on CD
--   8. Kill Shot (execute)
--   9. Kill Command on CD
--  10. Glaive Toss on CD
--  11. Focus Fire at 5 Frenzy
--  12. Arcane Shot at 70+ focus
--  13. Cobra Shot (filler)
--
-- AoE (>2 enemies within 10yd of target):
--   Same priority but Multi-Shot replaces Arcane Shot.
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Hunter (Beast Mastery)",
  Widgets = {
    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "BMUseStampede",
      text = "Use Stampede",       default = true },
    { type = "checkbox", uid = "BMUseRapidFire",
      text = "Use Rapid Fire",     default = true },
    { type = "checkbox", uid = "BMUseBestialWrath",
      text = "Use Bestial Wrath",  default = true },
    { type = "checkbox", uid = "BMUseFervor",
      text = "Use Fervor",         default = true },

    { type = "text",     text = "=== Focus Management ===" },
    { type = "slider",   uid = "BMArcaneShotMinFocus",
      text = "Arcane Shot min focus",  default = 70, min = 30, max = 100 },
    { type = "slider",   uid = "BMFervorThreshold",
      text = "Fervor below focus %",   default = 40, min = 10, max = 80 },

    { type = "text",     text = "=== Utility ===" },
    { type = "checkbox", uid = "BMAutoAspectHawk",
      text = "Maintain Aspect of the Hawk", default = true },
    { type = "checkbox", uid = "BMSpreadSerpentSting",
      text = "Spread Serpent Sting (multi-dot)", default = true },

    { type = "text",     text = "=== AoE ===" },
    { type = "checkbox", uid = "BMAoeEnabled",
      text = "Use AoE rotation (Multi-Shot)",  default = true },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local FOCUS_FIRE_FRENZY_STACKS = 5
local AOE_RANGE = 10   -- enemies within 10yd of target triggers AoE
local AOE_COUNT = 2    -- more than 2 enemies = AoE

-- ── Helpers ────────────────────────────────────────────────────

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

local function BeastMasteryCombat()
  local target = Combat.BestTarget
  if not target then return end

  -- ── Pre-combat maintenance (aspect) ──────────────────────────
  if PallasSettings.BMAutoAspectHawk then
    if not Me:HasAura("Aspect of the Hawk") and not Me:HasAura("Aspect of the Iron Hawk") then
      if Spell.AspectOfTheHawk:CastEx(Me) then return end
      if Spell.AspectOfTheIronHawk:CastEx(Me) then return end
    end
  end

  -- Fervor (talent — instant 50 focus when starved)
  if PallasSettings.BMUseFervor and Me.PowerPct < (PallasSettings.BMFervorThreshold or 40) then
    if Spell.Fervor:CastEx(Me) then return end
  end

  -- Determine AoE: >2 enemies within 10yd of our target
  local use_aoe = false
  if PallasSettings.BMAoeEnabled then
    local nearby_target = Combat:GetTargetsAround(target, AOE_RANGE)
    use_aoe = nearby_target > AOE_COUNT
  end

  -- ── Priority list (matches MoP 5.5.3 BM guide) ──────────────

  -- 1. Maintain Hunter's Mark
  if not target:HasAura("Hunter's Mark") then
    if Spell.HuntersMark:CastEx(target) then return end
  end

  -- 2. Maintain Serpent Sting
  if PallasSettings.BMSpreadSerpentSting then
    if SpreadSerpentSting(target) then return end
  elseif not target:HasAura("Serpent Sting") then
    if Spell.SerpentSting:CastEx(target) then return end
  end

  -- 3. Stampede on CD
  if PallasSettings.BMUseStampede then
    if Spell.Stampede:CastEx(Me) then return end
  end

  -- 4. Rapid Fire on CD
  if PallasSettings.BMUseRapidFire then
    if Spell.RapidFire:CastEx(Me) then return end
  end

  -- 5. Bestial Wrath on CD
  if PallasSettings.BMUseBestialWrath then
    if Spell.BestialWrath:CastEx(Me) then return end
  end

  -- 6. Rabid (pet) on CD
  if Spell.Rabid:CastEx(Me) then return end

  -- 7. Dire Beast on CD
  if Spell.DireBeast:CastEx(target) then return end

  -- 8. Kill Shot (execute)
  if Spell.KillShot:CastEx(target) then return end

  -- 9. Kill Command on CD
  if Spell.KillCommand:CastEx(target) then return end

  -- 10. Glaive Toss on CD
  if Spell.GlaiveToss:CastEx(target) then return end

  -- 11. Focus Fire at 5 Frenzy stacks
  local frenzy = Me:GetAura("Frenzy")
  if frenzy and frenzy.stacks and frenzy.stacks >= FOCUS_FIRE_FRENZY_STACKS then
    if Spell.FocusFire:CastEx(Me) then return end
  end

  -- 12. Arcane Shot / Multi-Shot (focus dump at 70+)
  if Me.Power >= (PallasSettings.BMArcaneShotMinFocus or 70) then
    if use_aoe then
      if Spell.MultiShot:CastEx(target) then return end
    else
      if Spell.ArcaneShot:CastEx(target) then return end
    end
  end

  -- 13. Cobra Shot (filler)
  Spell.CobraShot:CastEx(target)
end

-- ── Export ───────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = BeastMasteryCombat,
}

return { Options = options, Behaviors = behaviors }

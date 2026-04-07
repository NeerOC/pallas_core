-- ═══════════════════════════════════════════════════════════════════
-- Retribution Paladin behavior (MoP 5.5.3)
--
-- Priority-based rotation with full defensive, utility, and interrupt
-- support for dungeon/raid environments.
--
-- Single-Target Priority:
--   1. Inquisition (maintain 3HP)
--   2. Hammer of Wrath (<20% or Avenging Wrath active)
--   3. Templar's Verdict (5 HP or Divine Purpose proc)
--   4. Exorcism (always instant for Ret in MoP)
--   5. Crusader Strike
--   6. Judgment
--   7. Templar's Verdict (3+ HP)
--
-- AoE Priority (3+ enemies):
--   1. Inquisition (maintain 3HP)
--   2. Divine Storm (5 HP or Divine Purpose proc)
--   3. Hammer of Wrath (<20% or AW)
--   4. Hammer of the Righteous
--   5. Exorcism
--   6. Judgment
--   7. Divine Storm (3+ HP)
--   8. Consecration
--
-- Burst CDs (fire freely; use hold-to-pause for manual timing):
--   Avenging Wrath, Guardian of Ancient Kings, Holy Avenger (T5),
--   Execution Sentence / Light's Hammer / Holy Prism (T6, TTD-gated),
--   Synapse Springs
--
-- Interrupts:  Rebuke → Hammer of Justice (stun interrupt)
--              → Blinding Light (AoE interrupt fallback, togglable)
--
-- Defensives:  Divine Shield, Divine Protection, Sacred Shield,
--              Word of Glory (emergency self-heal)
--
-- Party Utility: Hand of Sacrifice, Lay on Hands, Blessing of Kings,
--                Hand of Protection, Cleanse (party), Hand of Freedom (party)
-- Cleanse & Freedom (self): self-only toggles
-- ═══════════════════════════════════════════════════════════════════

-- ── Settings helper ────────────────────────────────────────────

local function S(uid)
  return PallasSettings[uid] ~= false
end

local function V(uid, default)
  local v = PallasSettings[uid]
  if v == nil then return default end
  return v
end

-- ── Menu options ────────────────────────────────────────────────

local options = {
  Name = "Paladin (Retribution)",
  Widgets = {
    { type = "text",     text = "=== Defensives ===" },
    { type = "slider",   uid = "RetDivineProtectionHP",
      text = "Divine Protection HP %",     default = 50, min = 10, max = 80 },
    { type = "slider",   uid = "RetDivineShieldHP",
      text = "Divine Shield HP %",         default = 15, min = 5,  max = 30 },
    { type = "slider",   uid = "RetWordOfGloryHP",
      text = "Word of Glory HP %",         default = 30, min = 10, max = 60 },

    { type = "text",     text = "=== Buffs ===" },
    { type = "checkbox", uid = "RetAutoBlessings",
      text = "Auto Blessings",             default = true },

    { type = "text",     text = "=== Cleanse & Hand of Freedom ===" },
    { type = "checkbox", uid = "RetUseCleanseSelf",
      text = "Cleanse (Self)",             default = true },
    { type = "checkbox", uid = "RetUseHandOfFreedomSelf",
      text = "Hand of Freedom (Self)",     default = true },

    { type = "text",     text = "=== Interrupts ===" },
    { type = "checkbox", uid = "RetUseInterrupt",
      text = "Use Interrupts",             default = true },

    { type = "text",     text = "=== Cooldowns ===" },
    { type = "checkbox", uid = "RetUseCooldowns",
      text = "Use Cooldowns",                  default = false },
    { type = "slider",   uid = "RetT6MinTTD",
      text = "T6 talent min TTD (sec)",        default = 10, min = 3, max = 30 },

    { type = "text",     text = "=== Party Utility ===" },
    { type = "slider",   uid = "RetSacrificeHP",
      text = "Hand of Sacrifice ally HP %", default = 30, min = 10, max = 60 },
    { type = "slider",   uid = "RetLayOnHandsHP",
      text = "Lay on Hands ally HP %",      default = 15, min = 5,  max = 30 },
    { type = "checkbox", uid = "RetUseHandOfProtection",
      text = "Hand of Protection (Party)",   default = false },
    { type = "slider",   uid = "RetBopHP",
      text = "Hand of Protection HP %", default = 15, min = 5, max = 30 },
    { type = "checkbox", uid = "RetUseCleanseParty",
      text = "Cleanse (Party)",             default = true },
    { type = "checkbox", uid = "RetUseHandOfFreedomParty",
      text = "Hand of Freedom (Party)",   default = true },
  },
}

-- ── Constants ──────────────────────────────────────────────────

local AOE_RANGE = 8

-- Inquisition: refresh only when missing / <= 3s left; requires 3 real HP
local INQ_MIN_HP      = 3
local INQ_REFRESH_SEC = 3

-- Spell IDs for auras/checks where name lookup might be ambiguous
local DIVINE_PURPOSE_ID   = 90174
local SACRED_SHIELD_ID    = 20925
local AVENGING_WRATH_ID   = 31884
local FORBEARANCE_ID      = 25771

-- Blessing auras: spell IDs for localization-safe detection
local BLESSING_OF_KINGS_AURA_ID = 20217
local BLESSING_OF_MIGHT_AURA_ID = 19740

-- Glyph of Double Jeopardy: after Judgment, next Judgment on a different
-- target deals +20% damage (MoP glyph)
local DOUBLE_JEOPARDY_ID  = 121027

-- Seal aura IDs
local SEAL_OF_TRUTH_ID         = 31801
local SEAL_OF_RIGHTEOUSNESS_ID = 20154

-- Hand of Freedom aura ID
local HAND_OF_FREEDOM_ID = 1044

--- Last unit we cast Judgment on (GUID), for Double Jeopardy target swapping
local last_judgment_guid = nil

-- ── Self-buff cast helper ────────────────────────────────────────
-- Uses cast_spell_at_unit targeting Me.obj_ptr for safe self-casting.

local RESULT_SUCCESS    = 0
local RESULT_THROTTLED  = 9
local RESULT_NOT_READY  = 10
local RESULT_ON_CD      = 11
local RESULT_QUEUED     = 12

local function CastNoTarget(spell)
  if not spell or not spell.IsKnown or spell.Id == 0 then return false end
  if Pallas._tick_throttled then return false end
  local now = os.clock()
  if now < (spell._fail_until or 0) or now < (spell._cast_until or 0) then
    return false
  end
  local uok, usable = pcall(game.is_usable_spell, spell.Id)
  if uok and not usable then return false end
  local cok, cd = pcall(game.spell_cooldown, spell.Id)
  if cok and cd and cd.on_cooldown then return false end

  local ok, c, desc = pcall(game.cast_spell_at_unit, spell.Id, Me.obj_ptr)
  local code = ok and c or -1
  if code == RESULT_SUCCESS or code == RESULT_QUEUED then
    Pallas._last_cast      = spell.Name
    Pallas._last_cast_time = now
    Pallas._last_cast_tgt  = "self"
    Pallas._last_cast_code = code
    Pallas._last_cast_desc = ok and (desc or "") or ""
    spell._cast_until = now + 0.2
    Pallas._tick_throttled = true
    return true
  elseif code == RESULT_THROTTLED or code == RESULT_NOT_READY or code == RESULT_ON_CD then
    Pallas._tick_throttled = true
  elseif code >= 0 then
    spell._fail_until      = now + 1.0
    Pallas._last_fail      = spell.Name
    Pallas._last_fail_time = now
    Pallas._last_fail_code = code
    Pallas._last_fail_desc = ok and (desc or "") or ""
  end
  return false
end

-- ── Enemy Collection (reuse across combat/interrupt) ──────────────

local MELEE_LEEWAY = 4.0 / 3.0
local MELEE_MIN    = 5.0

local function GetCombatEnemies()
  local entities = Pallas._entity_cache or {}
  if not Me or not Me.Position then return {} end
  local mx, my, mz = Me.Position.x, Me.Position.y, Me.Position.z

  local results = {}
  for _, e in ipairs(entities) do
    local cls = e.class
    if cls ~= "Unit" and cls ~= "Player" then goto skip end

    local eu = e.unit
    if not eu then goto skip end
    if eu.is_dead then goto skip end
    if eu.health and eu.health <= 0 then goto skip end
    if not eu.in_combat then
      -- Allow current target through (training dummies, AttackOOC)
      local is_current_target = Me.Target and Me.Target.Guid == (e.guid or "")
      if not is_current_target then goto skip end
    end

    local a_ok, attackable = pcall(game.unit_is_attackable, e.obj_ptr)
    if a_ok and not attackable then goto skip end

    local u = Unit:New(e)
    if u:IsImmune() then goto skip end

    if e.position then
      local dx = mx - e.position.x
      local dy = my - e.position.y
      local dz = mz - e.position.z
      local dist_sq = dx * dx + dy * dy + dz * dz
      if dist_sq <= 1600 then -- 40yd max
        if TTD then TTD.Update(u) end
        results[#results + 1] = {
          unit = u,
          dist_sq = dist_sq,
        }
      end
    end
    ::skip::
  end

  if TTD then TTD.Cleanup() end
  table.sort(results, function(a, b) return a.dist_sq < b.dist_sq end)
  return results
end

local function MeleeTarget(enemies)
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local my_cr = Me.CombatReach or 0
  local best = nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 225 then break end -- 15yd early out
    local their_cr = entry.unit.CombatReach or 0
    local range = my_cr + their_cr + MELEE_LEEWAY
    if range < MELEE_MIN then range = MELEE_MIN end
    if entry.dist_sq <= range * range then
      -- Prefer the player's current target if it's in melee range
      if tgt_guid and entry.unit.Guid == tgt_guid then
        return entry.unit
      end
      best = best or entry.unit
    end
  end

  return best
end

local function GetTargetInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil
  local best = nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end
    if tgt_guid and entry.unit.Guid == tgt_guid then
      return entry.unit
    end
    best = best or entry.unit
  end

  return best
end

local function RangedTarget(enemies) return GetTargetInRange(enemies, 30) end

local function HasDoubleJeopardyProc()
  return Me:HasAura(DOUBLE_JEOPARDY_ID) or Me:HasAura("Double Jeopardy")
end

--- Prefer another enemy in Judgment range while Double Jeopardy is active (glyph).
local function JudgmentTarget(enemies, primary_ranged)
  if not primary_ranged then return nil end
  if not Spell.Judgment or not Spell.Judgment.IsKnown then return nil end
  if not HasDoubleJeopardyProc() or not last_judgment_guid then
    return primary_ranged
  end
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 900 then break end -- 30 yd
    local u = entry.unit
    if u.Guid ~= last_judgment_guid and Spell.Judgment:InRange(u) then
      return u
    end
  end
  return primary_ranged
end

local function CastJudgment(enemies, primary_ranged)
  if not primary_ranged then return false end
  if not Spell.Judgment or not Spell.Judgment.IsKnown then return false end
  local jt = JudgmentTarget(enemies, primary_ranged)
  if not jt then return false end
  if Spell.Judgment:CastEx(jt) then
    last_judgment_guid = jt.Guid
    return true
  end
  return false
end

local function EnemiesInRange(enemies, range_yd)
  local range_sq = range_yd * range_yd
  local count = 0
  for _, entry in ipairs(enemies) do
    if entry.dist_sq > range_sq then break end
    count = count + 1
  end
  return count
end

-- ── Holy Power helpers ───────────────────────────────────────────

local function GetHolyPower()
  -- Holy Power is power type 9
  if Me.PowerType == 9 then
    return Me.Power
  end
  local ok, val = pcall(game.unit_power, Me.obj_ptr, 9)
  if ok and val then return val end
  return 0
end

-- ── Interrupt System ─────────────────────────────────────────────
-- Rebuke (melee) → HoJ (ranged/melee, if rebuke OOR or on CD)
-- → Blinding Light (AoE interrupt fallback, togglable)

local function TryInterrupt(enemies)
  if not S("RetUseInterrupt") then return false end

  local rebuke_ready = Spell.Rebuke and Spell.Rebuke.IsKnown and Spell.Rebuke:IsReady()
  local hoj_ready    = Spell.HammerOfJustice and Spell.HammerOfJustice.IsKnown
                       and Spell.HammerOfJustice:IsReady()
  local blind_ready  = Spell.BlindingLight and Spell.BlindingLight.IsKnown
                       and Spell.BlindingLight:IsReady()

  if not rebuke_ready and not hoj_ready and not blind_ready then return false end

  local tgt_guid = Me.Target and not Me.Target.IsDead and Me.Target.Guid or nil

  for _, entry in ipairs(enemies) do
    if entry.dist_sq > 900 then break end -- 30yd max for any interrupt
    local u = entry.unit

    -- Determine if casting/channeling and whether it's interruptible
    local casting = false
    local confirmed_immune = false

    -- For our current target, use the live game API (more accurate)
    if tgt_guid and u.Guid == tgt_guid then
      local ok, cast = pcall(game.unit_casting_info, "target")
      if ok and cast then
        casting = true
        if cast.not_interruptible then confirmed_immune = true end
      else
        local ok2, chan = pcall(game.unit_channel_info, "target")
        if ok2 and chan then
          casting = true
          if chan.not_interruptible then confirmed_immune = true end
        end
      end
    else
      -- For non-target mobs, rely on OM snapshot
      if u.IsCasting or u.IsChanneling then
        casting = true
        -- NotInterruptible from snapshot; may be stale but best we have
        if u.NotInterruptible then confirmed_immune = true end
      end
    end

    if not casting then goto next_enemy end
    if confirmed_immune then goto next_enemy end

    -- Priority 1: Rebuke (melee range, 15s CD)
    if rebuke_ready and Spell.Rebuke:InRange(u) then
      if Spell.Rebuke:CastEx(u) then return true end
    end

    -- Priority 2: Hammer of Justice (10yd range, stun interrupt)
    if hoj_ready and not u:IsStunned() then
      if Spell.HammerOfJustice:InRange(u) then
        if Spell.HammerOfJustice:CastEx(u) then return true end
      end
    end

    -- Priority 3: Blinding Light (10yd AoE interrupt fallback)
    if blind_ready and entry.dist_sq <= 100 then -- 10yd
      if CastNoTarget(Spell.BlindingLight) then return true end
    end

    ::next_enemy::
  end

  return false
end

-- ── Blessing Management ──────────────────────────────────────────
-- MoP: only ONE blessing can be active at a time. Kings > Might.
--   - No buff at all → cast Kings
--   - MotW or Legacy of the Emperor already active → cast Might (stats covered)
--   - Our blessing is about to expire (< 5 min) → refresh it
--   - Never replace our own active blessing with a different one

local BLESSING_REFRESH_SEC = 5 * 60  -- only refresh when < 5 min remaining

local blessing_cast_at = 0
local blessing_active  = false  -- trust our own cast; HasAura may not see blessings
local blessing_cast_id = 0      -- which blessing we last cast

local function GetBlessingAura(spell_id, name)
  local a = Me:GetAura(spell_id)
  if a then return a end
  return Me:GetAura(name)
end

--- Returns remaining seconds on an aura, or 0 if missing/unreadable.
local function AuraRemaining(aura)
  if not aura then return 0 end
  local r = aura.remaining
  if type(r) == "number" and r > 0 then return r end
  if aura.expire_time then
    local ok, now = pcall(game.game_time)
    if ok and type(now) == "number" then
      local rem = aura.expire_time - now
      return rem > 0 and rem or 0
    end
  end
  -- Aura exists but can't read duration — return large number to avoid spam
  return 9999
end

local function MaintainBlessings()
  if not S("RetAutoBlessings") then return false end
  if Me:IsCastingOrChanneling() then return false end
  if Spell:IsGCDActive() then return false end
  if os.clock() - blessing_cast_at < 5 then return false end

  -- Trust window: if we cast recently and aura detection is unreliable,
  -- don't re-cast for 60 seconds
  if blessing_active then
    if os.clock() - blessing_cast_at > 60 then
      blessing_active = false
    else
      return false
    end
  end

  local kings_known = Spell.BlessingOfKings and Spell.BlessingOfKings.IsKnown
  local might_known = Spell.BlessingOfMight and Spell.BlessingOfMight.IsKnown
  if not kings_known and not might_known then return false end

  -- Check what's currently active
  local kings_aura = GetBlessingAura(BLESSING_OF_KINGS_AURA_ID, "Blessing of Kings")
  local might_aura = GetBlessingAura(BLESSING_OF_MIGHT_AURA_ID, "Blessing of Might")
  local has_motw   = Me:HasAura("Mark of the Wild")
  local has_legacy = Me:HasAura("Legacy of the Emperor")

  local kings_remaining = AuraRemaining(kings_aura)
  local might_remaining = AuraRemaining(might_aura)

  -- If we already have a blessing with plenty of time left, do nothing
  if kings_remaining > BLESSING_REFRESH_SEC then return false end
  if might_remaining > BLESSING_REFRESH_SEC then return false end

  -- Need to cast or refresh a blessing. Decide which one:
  local cast_spell = nil

  if has_motw or has_legacy then
    -- Stats already covered by druid/monk → give Might
    if might_known then
      cast_spell = Spell.BlessingOfMight
    elseif kings_known then
      cast_spell = Spell.BlessingOfKings
    end
  else
    -- No external stats buff → Kings (higher priority)
    if kings_known then
      cast_spell = Spell.BlessingOfKings
    elseif might_known then
      cast_spell = Spell.BlessingOfMight
    end
  end

  if not cast_spell then return false end

  if CastNoTarget(cast_spell) then
    blessing_cast_at = os.clock()
    blessing_active  = true
    blessing_cast_id = cast_spell.Id
    return true
  end
  return false
end

-- ── Sacred Shield ─────────────────────────────────────────────────
-- Maintain on self when taking damage (in combat).
-- 20925 = the 30s buff we cast and maintain
-- 65148 = the absorb proc that fires every 6s (ignore this one)

local sacred_shield_cast_at = 0
local SacredShieldSpell = nil

local function GetSacredShieldSpell()
  if not SacredShieldSpell then
    SacredShieldSpell = Spell:ById(SACRED_SHIELD_ID)
  end
  return SacredShieldSpell
end

local function MaintainSacredShield()
  local ss_spell = GetSacredShieldSpell()
  if not ss_spell or not ss_spell.IsKnown then return false end
  if os.clock() - sacred_shield_cast_at < 5 then return false end

  -- Only check 20925 by ID — never by name (avoids matching the 65148 proc)
  local ss = Me:GetAuraByMe(SACRED_SHIELD_ID)
  if not ss then
    ss = Me:GetAura(SACRED_SHIELD_ID)
  end
  if ss and ss.remaining and ss.remaining > 4 then return false end

  if ss_spell:CastEx(Me, { skipFacing = true }) then
    sacred_shield_cast_at = os.clock()
    return true
  end
  return false
end

-- ── Seal Management ──────────────────────────────────────────────
-- Maintain Seal of Truth (default for Ret)

local seal_cast_at = 0
local seal_active  = false   -- trust our own cast; HasAura may not see seals

local function MaintainSeal()
  if Me:IsCastingOrChanneling() then return false end
  if Spell:IsGCDActive() then return false end
  if os.clock() - seal_cast_at < 5 then return false end
  -- Check by ID first, then name — covers localization and snapshot gaps
  if Me:HasAura(SEAL_OF_TRUTH_ID) or Me:HasAura("Seal of Truth") then
    seal_active = true
    return false
  end
  if Me:HasAura(SEAL_OF_RIGHTEOUSNESS_ID) or Me:HasAura("Seal of Righteousness") then
    seal_active = true
    return false
  end
  -- If we already cast it and the suppress window hasn't expired, trust it
  if seal_active then return false end
  if Spell.SealOfTruth and Spell.SealOfTruth.IsKnown then
    if CastNoTarget(Spell.SealOfTruth) then
      seal_cast_at = os.clock()
      seal_active  = true
      return true
    end
  end
  return false
end

-- ── Defensives ─────────────────────────────────────────────────────

local function UseDefensives()
  local hp = Me.HealthPct

  -- Sacred Shield maintenance (in combat, taking damage)
  if Me.InCombat and MaintainSacredShield() then return true end

  -- Word of Glory (emergency self-heal, uses Holy Power)
  if hp < V("RetWordOfGloryHP", 30) and GetHolyPower() >= 3 then
    if Spell.WordOfGlory and Spell.WordOfGlory.IsKnown then
      if Spell.WordOfGlory:CastEx(Me, { skipFacing = true }) then return true end
    end
  end

  -- Divine Protection (50% magic damage reduction)
  if hp < V("RetDivineProtectionHP", 50) then
    if Spell.DivineProtection and Spell.DivineProtection.IsKnown then
      if CastNoTarget(Spell.DivineProtection) then return true end
    end
  end

  -- Divine Shield (emergency bubble — check Forbearance)
  if hp < V("RetDivineShieldHP", 15) then
    if not Me:HasAura(FORBEARANCE_ID) then
      if Spell.DivineShield and Spell.DivineShield.IsKnown then
        if CastNoTarget(Spell.DivineShield) then return true end
      end
    end
  end

  return false
end

-- ── Hand of Freedom (self) ───────────────────────────────────────
-- Runs at high priority so it's not gated behind Heal.PriorityList.
-- Uses multiple detection methods since speed-based checks can miss
-- some root effects.

local function IsRootedOrSnared()
  -- Method 1: speed-based (existing Unit methods)
  if Me:IsSlowed() or Me:IsRooted() then return true end

  -- Method 2: Loss of Control events (most reliable for the local player)
  local events = Me:GetLossOfControlEvents()
  for _, ev in ipairs(events) do
    local t = ev.locType
    if t == "ROOT" or t == "SNARE" or t == "SLOW" then
      return true
    end
  end

  -- Method 3: check for common root/snare aura IDs as a fallback
  local root_auras = {
    339,    -- Entangling Roots
    122,    -- Frost Nova
    45334,  -- Frostbolt (root proc)
    116706, -- Disable (root)
    114404, -- Void Tendrils
    64695,  -- Earthgrab
    63685,  -- Freeze (Water Elemental)
    33395,  -- Freeze
    87194,  -- Glyph of Mind Blast (root)
    105771, -- Charge (root)
  }
  for _, id in ipairs(root_auras) do
    if Me:HasAura(id) then return true end
  end

  return false
end

local function TryHandOfFreedomSelf()
  if not S("RetUseHandOfFreedomSelf") then return false end
  if not Spell.HandOfFreedom or not Spell.HandOfFreedom.IsKnown then return false end
  if not Spell.HandOfFreedom:IsReady() then return false end
  if Me:HasAura(HAND_OF_FREEDOM_ID) or Me:HasAura("Hand of Freedom") then return false end
  if not IsRootedOrSnared() then return false end
  if Spell.HandOfFreedom:CastEx(Me, { skipFacing = true }) then return true end
  return false
end

-- ── Party Utility ─────────────────────────────────────────────────
-- Hand of Sacrifice, Lay on Hands, Hand of Protection, Cleanse, Freedom

local function PartyUtility()
  if not Heal or not Heal.PriorityList then return false end

  local sac_hp  = V("RetSacrificeHP", 30)
  local loh_hp  = V("RetLayOnHandsHP", 15)
  local bop_hp  = V("RetBopHP", 15)

  for _, entry in ipairs(Heal.PriorityList) do
    local u = entry.Unit
    if not u or u.IsDead then goto next_ally end
    if u.Guid == Me.Guid then goto next_ally end -- skip self for external CDs

    local ally_hp = u.HealthPct

    -- Lay on Hands (emergency full heal, check Forbearance)
    if ally_hp < loh_hp then
      if Spell.LayOnHands and Spell.LayOnHands.IsKnown then
        if not u:HasAura(FORBEARANCE_ID) then
          if Spell.LayOnHands:CastEx(u, { skipFacing = true }) then return true end
        end
      end
    end

    -- Hand of Sacrifice (redirect damage to us, only if we're healthy)
    if ally_hp < sac_hp and Me.HealthPct > 50 then
      if Spell.HandOfSacrifice and Spell.HandOfSacrifice.IsKnown then
        if not u:HasAura("Hand of Sacrifice") then
          if Spell.HandOfSacrifice:CastEx(u, { skipFacing = true }) then return true end
        end
      end
    end

    -- Hand of Protection (physical immunity, opt-in, don't BoP tanks)
    if S("RetUseHandOfProtection") and ally_hp < bop_hp then
      if Spell.HandOfProtection and Spell.HandOfProtection.IsKnown then
        if not u:HasAura(FORBEARANCE_ID) then
          if not u:IsTank() then
            if Spell.HandOfProtection:CastEx(u, { skipFacing = true }) then return true end
          end
        end
      end
    end

    ::next_ally::
  end

  -- Cleanse poison/disease
  -- NOTE: selfOnly/partyOnly options are passed but the framework's Dispel
  -- implementation does not currently filter on them — both scopes will
  -- dispel any friendly in range. This is a known framework limitation.
  local cleanse_off = PallasSettings.RetUseCleanse == false
  local want_cleanse_self = not cleanse_off and S("RetUseCleanseSelf")
  local want_cleanse_party = not cleanse_off and S("RetUseCleanseParty")
  if Spell.Cleanse and Spell.Cleanse.IsKnown then
    local types = { DispelType.Poison, DispelType.Disease }
    if want_cleanse_self and want_cleanse_party then
      if Spell.Cleanse:Dispel(true, types) then return true end
    elseif want_cleanse_self then
      if Spell.Cleanse:Dispel(true, types, { selfOnly = true }) then return true end
    elseif want_cleanse_party then
      if Spell.Cleanse:Dispel(true, types, { partyOnly = true }) then return true end
    end
  end

  -- Hand of Freedom (slow/root; party only — self is handled separately)
  if Spell.HandOfFreedom and Spell.HandOfFreedom.IsKnown and Spell.HandOfFreedom:IsReady() then
    if S("RetUseHandOfFreedomParty") then
      for _, entry in ipairs(Heal.PriorityList) do
        local u = entry.Unit
        if u and not u.IsDead and u.Guid ~= Me.Guid then
          if u:IsSlowed() or u:IsRooted() then
            if Spell.HandOfFreedom:CastEx(u, { skipFacing = true }) then return true end
          end
        end
      end
    end
  end

  return false
end

-- ── Offensive Cooldowns ──────────────────────────────────────────
-- CDs fire freely on cooldown. Hold non-AW CDs if AW is coming
-- off cooldown within 5 seconds so they line up naturally.
-- Use hold-to-pause (core feature) for manual CD timing.

local AW_HOLD_THRESHOLD = 5 -- seconds — hold other CDs if AW is this close

--- Returns true if AW is coming off CD within AW_HOLD_THRESHOLD seconds
local function AwComingSoon()
  if not Spell.AvengingWrath or not Spell.AvengingWrath.IsKnown then return false end
  local cd = Spell.AvengingWrath:GetCooldown()
  if not cd or not cd.on_cooldown then return false end -- AW is ready, no need to hold
  if cd.remaining and cd.remaining <= AW_HOLD_THRESHOLD then return true end
  return false
end

local function UseCooldowns(enemies)
  if not S("RetUseCooldowns") then return false end

  local target = MeleeTarget(enemies) or RangedTarget(enemies)
  if not target then return false end

  local aw_soon = AwComingSoon()

  -- Avenging Wrath — always fire first (other CDs sync to it)
  if Spell.AvengingWrath and Spell.AvengingWrath.IsKnown then
    if CastNoTarget(Spell.AvengingWrath) then return true end
  end

  -- Hold remaining CDs if AW is about to come off CD (sync them)
  if aw_soon then return false end

  -- Guardian of Ancient Kings
  if Spell.GuardianOfAncientKings and Spell.GuardianOfAncientKings.IsKnown then
    if CastNoTarget(Spell.GuardianOfAncientKings) then return true end
  end

  -- Holy Avenger (T5 talent)
  if Spell.HolyAvenger and Spell.HolyAvenger.IsKnown then
    if CastNoTarget(Spell.HolyAvenger) then return true end
  end

  -- Execution Sentence / Light's Hammer / Holy Prism (T6 talent)
  -- Only use on targets that will live long enough to get full value.
  -- TTD returns 999 when data is insufficient (boss, fresh pull) — that's
  -- fine, we treat unknown TTD as "worth using".
  local min_ttd = V("RetT6MinTTD", 10)
  local ttd = TTD and TTD.Get(target) or 999

  if ttd >= min_ttd then
    -- Execution Sentence (single-target, 30yd range)
    if Spell.ExecutionSentence and Spell.ExecutionSentence.IsKnown then
      local ranged = RangedTarget(enemies)
      if ranged then
        local rtd = TTD and TTD.Get(ranged) or 999
        if rtd >= min_ttd and Spell.ExecutionSentence:CastEx(ranged) then return true end
      end
    end

    -- Light's Hammer (ground AoE)
    if Spell.LightsHammer and Spell.LightsHammer.IsKnown then
      local melee = MeleeTarget(enemies)
      if melee and Spell.LightsHammer:CastAtPos(melee) then return true end
    end

    -- Holy Prism (T6 alternative)
    if Spell.HolyPrism and Spell.HolyPrism.IsKnown then
      local ranged = RangedTarget(enemies)
      if ranged and Spell.HolyPrism:CastEx(ranged) then return true end
    end
  end

  -- Synapse Springs (engineering gloves) — fire with other CDs
  local gloves = Item and Item.Hands
  if gloves and gloves:IsValid() and gloves:IsReady() then
    if gloves:Use() then return true end
  end

  return false
end

-- ── Inquisition ──────────────────────────────────────────────────

local function InquisitionRemaining()
  local a = Me:GetAuraByMe("Inquisition") or Me:GetAura("Inquisition")
  if not a then return 0 end
  local r = a.remaining
  if type(r) == "number" and r > 0 then return r end
  if a.expire_time and game and game.game_time then
    local ok, now = pcall(game.game_time)
    if ok and type(now) == "number" then
      local rem = (a.expire_time or 0) - now
      return rem > 0 and rem or 0
    end
  end
  return 0
end

local function NeedsInquisition()
  if not Spell.Inquisition or not Spell.Inquisition.IsKnown then return false end
  if GetHolyPower() < INQ_MIN_HP then return false end
  local rem = InquisitionRemaining()
  if rem < 0.1 then return true end
  return rem <= INQ_REFRESH_SEC
end

-- ── Single-Target Rotation ────────────────────────────────────────

local function SingleTarget(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local hp     = GetHolyPower()
  local has_dp = Me:HasAura(DIVINE_PURPOSE_ID)

  -- 1. Inquisition — only when missing / <= INQ_REFRESH_SEC remaining (3 real HP)
  if (melee or ranged) and NeedsInquisition() then
    if CastNoTarget(Spell.Inquisition) then return true end
  end

  -- 2. Hammer of Wrath (<20% or during Avenging Wrath)
  if ranged then
    local can_how = ranged.HealthPct < 20 or Me:HasAura(AVENGING_WRATH_ID)
    if can_how and Spell.HammerOfWrath and Spell.HammerOfWrath.IsKnown then
      if Spell.HammerOfWrath:CastEx(ranged) then return true end
    end
  end

  -- 3. Templar's Verdict at 5 HP or Divine Purpose proc
  if melee and (hp >= 5 or has_dp) then
    if Spell.TemplarsVerdict and Spell.TemplarsVerdict.IsKnown then
      if Spell.TemplarsVerdict:CastEx(melee) then return true end
    end
  end

  -- 4. Exorcism (always instant for Ret in MoP)
  if ranged and Spell.Exorcism and Spell.Exorcism.IsKnown then
    if Spell.Exorcism:CastEx(ranged) then return true end
  end

  -- 5. Crusader Strike (primary HP generator)
  if melee and Spell.CrusaderStrike and Spell.CrusaderStrike.IsKnown then
    if Spell.CrusaderStrike:CastEx(melee) then return true end
  end

  -- 6. Judgment (HP generator; Glyph of Double Jeopardy — swap targets)
  if ranged and CastJudgment(enemies, ranged) then return true end

  -- 7. Templar's Verdict at 3+ HP (dump before capping)
  if melee and hp >= 3 then
    if Spell.TemplarsVerdict and Spell.TemplarsVerdict.IsKnown then
      if Spell.TemplarsVerdict:CastEx(melee) then return true end
    end
  end

  return false
end

-- ── AoE Rotation ──────────────────────────────────────────────────

local function AoERotation(enemies)
  local melee  = MeleeTarget(enemies)
  local ranged = RangedTarget(enemies)
  local hp     = GetHolyPower()
  local has_dp = Me:HasAura(DIVINE_PURPOSE_ID)

  -- 1. Inquisition — only when missing / <= INQ_REFRESH_SEC remaining (3 real HP)
  if (melee or ranged) and NeedsInquisition() then
    if CastNoTarget(Spell.Inquisition) then return true end
  end

  -- 2. Divine Storm at 5 HP or Divine Purpose proc
  if melee and (hp >= 5 or has_dp) then
    if Spell.DivineStorm and Spell.DivineStorm.IsKnown then
      if Spell.DivineStorm:CastEx(melee) then return true end
    end
  end

  -- 3. Hammer of Wrath (<20% or during AW) — higher priority than HotR
  if ranged then
    local can_how = ranged.HealthPct < 20 or Me:HasAura(AVENGING_WRATH_ID)
    if can_how and Spell.HammerOfWrath and Spell.HammerOfWrath.IsKnown then
      if Spell.HammerOfWrath:CastEx(ranged) then return true end
    end
  end

  -- 4. Hammer of the Righteous (AoE HP generator, replaces CS)
  if melee and Spell.HammerOfTheRighteous and Spell.HammerOfTheRighteous.IsKnown then
    if Spell.HammerOfTheRighteous:CastEx(melee) then return true end
  end

  -- 5. Exorcism (always instant for Ret in MoP)
  if ranged and Spell.Exorcism and Spell.Exorcism.IsKnown then
    if Spell.Exorcism:CastEx(ranged) then return true end
  end

  -- 6. Judgment (HP generator; Double Jeopardy swap)
  if ranged and CastJudgment(enemies, ranged) then return true end

  -- 7. Divine Storm at 3+ HP
  if melee and hp >= 3 then
    if Spell.DivineStorm and Spell.DivineStorm.IsKnown then
      if Spell.DivineStorm:CastEx(melee) then return true end
    end
  end

  -- 8. Consecration (filler AoE — placed at player's feet)
  if melee and Spell.Consecration and Spell.Consecration.IsKnown then
    if Spell.Consecration:CastAtPos(Me) then return true end
  end

  return false
end

-- ── Main Combat Function ──────────────────────────────────────────

local was_in_combat = false

local function RetPaladinCombat()
  if Me.IsMounted then return end
  if Me.IsDead then
    -- Death clears all buffs — reset trust flags so we rebuff on resurrect
    seal_active = false
    blessing_active = false
    return
  end

  -- Out of combat maintenance
  if not Me.InCombat then
    if was_in_combat then
      was_in_combat = false
      last_judgment_guid = nil
      -- NOTE: seal_active and blessing_active are NOT reset here.
      -- Seals and blessings are permanent buffs that persist through combat.
      if TTD then TTD.Reset() end
    end

    -- Maintain Blessing of Kings out of combat
    if MaintainBlessings() then return end

    -- Maintain seal out of combat
    if MaintainSeal() then return end

    -- If we have a valid attackable target (training dummy / AttackOOC), run rotation
    local tgt = Me.Target
    if not tgt or tgt.IsDead then return end
    local tok, attackable = pcall(game.unit_is_attackable, tgt.obj_ptr)
    if not tok or not attackable then return end

    -- Fall through to rotation below
  end

  -- Track combat entry
  if Me.InCombat and not was_in_combat then
    was_in_combat = true
  end

  -- Use the method version which also checks live game state as fallback
  if Me:IsCastingOrChanneling() then return end
  if Spell:IsGCDActive() then return end

  -- Self-buffs (highest priority in combat)
  if MaintainSeal() then return end
  if MaintainBlessings() then return end

  -- Defensives (self, only in combat)
  if Me.InCombat then
    if UseDefensives() then return end
  end

  -- Hand of Freedom (self) — high priority, works in and out of combat
  if TryHandOfFreedomSelf() then return end

  -- Party utility (Sac, LoH, BoP, Cleanse — only in combat)
  if Me.InCombat then
    if PartyUtility() then return end
  end

  local enemies = GetCombatEnemies()
  if #enemies == 0 then return end

  -- Ensure auto-attack is running on a melee target
  local melee_tgt = MeleeTarget(enemies)
  if melee_tgt and not Me:IsAutoAttacking() then
    Me:StartAttack(melee_tgt)
  end

  -- Clear Double Jeopardy tracking when the buff falls off
  if last_judgment_guid and not HasDoubleJeopardyProc() then
    last_judgment_guid = nil
  end

  -- Interrupts (Rebuke → HoJ → Blinding Light)
  if TryInterrupt(enemies) then return end

  -- Offensive cooldowns (fire freely; hold-to-pause for manual timing)
  if UseCooldowns(enemies) then return end

  -- Determine rotation: AoE vs Single-Target
  local nearby = EnemiesInRange(enemies, AOE_RANGE)
  local use_aoe = nearby >= 3

  if use_aoe then
    if not AoERotation(enemies) then
      SingleTarget(enemies)
    end
  else
    SingleTarget(enemies)
  end

  -- Throttle when we've fallen through the entire priority list without
  -- casting anything (everything on CD, out of range, etc.)
  Pallas._tick_throttled = true
end

-- ── Heal Behavior (party support) ────────────────────────────────
-- Runs in the Heal tick to maintain Sacred Shield on self

local function RetPaladinHeal()
  if Me.IsMounted or Me.IsDead then return end
  if not Me.InCombat then return end
  if Me:IsCastingOrChanneling() then return end

  -- Sacred Shield on self (also checked in defensives, but heal tick
  -- runs at a different cadence)
  MaintainSacredShield()
end

-- ── Export ───────────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = RetPaladinCombat,
  [BehaviorType.Heal]   = RetPaladinHeal,
}

return { Options = options, Behaviors = behaviors }
-- ═══════════════════════════════════════════════════════════════════
-- Behavior template — copy this file to create a new spec behavior.
--
-- File location:
--   behaviors/<class>/<spec>.lua
--   e.g.  behaviors/warrior/fury.lua
--        behaviors/paladin/holy.lua
--
-- Class names (directory):  warrior, paladin, hunter, rogue, priest,
--   deathknight, shaman, mage, warlock, monk, druid
--
-- Spec names (filename, lowercase, no spaces):  e.g. fury, arms,
--   protection, holy, retribution, beastmastery, ...
--
-- The core auto-detects your spec from the game via:
--   Me.SpecId      1-based index (1-4), 0 = unknown
--   Me.SpecName    e.g. "Fury", "Holy", "Restoration"
--   Me.ClassName   e.g. "Warrior", "Druid"
--   Me.ClassId     numeric class ID (1-11)
--
-- Behavior files are loaded from:
--   behaviors/<ClassName:lower():nospaces>/<SpecName:lower():nospaces>.lua
-- ═══════════════════════════════════════════════════════════════════

-- ── Menu options shown in the Pallas window ─────────────────────

local options = {
  Name = "Class (Spec)",   -- shown as collapsing header

  Widgets = {
    -- { type = "text", text = "=== Offensive ===" },
    -- { type = "checkbox", uid = "MySpecAoe",     text = "Use AoE",            default = true },
    -- { type = "slider",   uid = "MySpecPool",    text = "Pool resource %",    default = 30, min = 0, max = 100 },
    -- { type = "combobox", uid = "MySpecInterrupt", text = "Interrupt mode",
    --     default = 0, options = { "Disabled", "Any", "Whitelist" } },
  },
}

-- ── Behavior functions ──────────────────────────────────────────

-- Combat rotation — called every tick while the combat system runs.
-- Use Combat.BestTarget, Spell.XXX:CastEx(target), Me, etc.
--
-- Items:
--   Item.Trinket1:Use()                   -- equipped slot alias
--   Item.Healthstone:Use()                -- by name (PascalCase)
--   Item:ById(76097):Use()                -- by item database ID
--   Item:BySlot(13):IsReady()             -- equipped slot number
--   item:IsReady() / :IsOnCooldown() / :CooldownRemaining()
--
-- Casting info (available on all units in snapshot):
--   target.IsCasting / target.IsChanneling / target.NotInterruptible
--   target.CastingSpellId / target.CastStart / target.CastEnd
--
-- Aura helpers:
--   target:GetAuraByMe("Rend")            -- only auras cast by you
--   aura.is_from_player                   -- true if cast by any player
local function DoCombat()
  local target = Combat.BestTarget
  if not target then return end
  if not Me:InMeleeRange(target) then return end

  -- Example priority:
  -- if Spell.MortalStrike:CastEx(target) then return end
  -- if Spell.Slam:CastEx(target) then return end
  -- if Me.HealthPct < 40 and Item.Healthstone:Use() then return end
  -- if Item.Trinket1:IsReady() then Item.Trinket1:Use() end
end

-- Heal logic (optional) — called every tick while the heal system runs.
-- local function DoHeal()
--   local lowest = Heal:GetLowestMember()
--   if not lowest then return end
--   -- if lowest.HealthPct < 60 and Spell.FlashHeal:CastEx(lowest) then return end
-- end

-- Tank logic (optional) — called every tick while the tank system runs.
-- local function DoTank()
--   local target = Tank.BestTarget
--   if not target then return end
-- end

-- ── Export ───────────────────────────────────────────────────────

local behaviors = {
  [BehaviorType.Combat] = DoCombat,
  -- [BehaviorType.Heal] = DoHeal,
  -- [BehaviorType.Tank] = DoTank,
}

return { Options = options, Behaviors = behaviors }

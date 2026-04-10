--- ═══════════════════════════════════════════════════════════════════
--- Pallas Core — Pet module
---
--- Provides pet detection, status, and entity lookup for any spec.
--- Backed by game.pet_info() (C++ reads pet system globals) and
--- game.active_pets() (matches pet GUIDs against entity cache).
---
--- "UI pets" (pet bar): backed by pet system globals.
--- "All summons"      : backed by owner GUID descriptors (sub_2657C60).
---
--- Usage from behavior scripts:
---   -- UI pets (pet bar) --
---   Pet.HasPet()                → bool (any active pet?)
---   Pet.HasPetOfFamily(id)      → bool (pet with creature family ID?)
---   Pet.HasPetNamed(pattern)    → bool (pet matching name pattern?)
---   Pet.FindByName(pattern)     → Unit or nil
---   Pet.FindByFamily(id)        → raw entity table or nil
---   Pet.GetPrimaryFamily()      → int creature family ID (0 = none)
---   Pet.Count()                 → number
---   Pet.IsPermanent()           → bool (permanent vs timed pet)
---   Pet.TimeRemaining()         → seconds or nil
---   Pet.GetPrimary()            → Unit or nil
---   Pet.GetAll()                → { Unit, ... }
---   Pet.PrimaryGuid()           → guid_lo, guid_hi (raw)
---
---   -- All summons (owner GUID match) --
---   Pet.GetAllSummons()         → { entity, ... } (raw entity tables)
---   Pet.HasSummonOfFamily(id)   → bool
---   Pet.FindSummonByFamily(id)  → raw entity table or nil
---   Pet.HasSummonNamed(pattern) → bool
---   Pet.SummonCount()           → number
---
---   -- Individual ownership queries (any unit) --
---   Pet.OwnerOf(cgunit)         → guid_lo, guid_hi (first populated)
---   Pet.CharmedBy(cgunit)       → guid_lo, guid_hi (+0x11BA0)
---   Pet.SummonedBy(cgunit)      → guid_lo, guid_hi (+0x11BC0)
---   Pet.CreatedBy(cgunit)       → guid_lo, guid_hi (+0x11BB0)
---   Pet.IsOwnedByPlayer(cgunit) → bool
---
---   -- Pet control (bar-position independent) --
---   Pet.Attack()                → bool (command pet to attack target)
---   Pet.Follow()                → bool (command pet to follow player)
---   Pet.Assist()                → bool (set assist stance)
---   Pet.Defensive()             → bool (set defensive stance)
---   Pet.Passive()               → bool (set passive stance)
---   Pet.Dismiss()               → bool (dismiss the pet)
---   Pet.MoveTo(x, y, z)         → bool (move pet to world position)
---   Pet.CastBarSlot(slot)       → bool (fire pet bar slot 1–10)
--- ═══════════════════════════════════════════════════════════════════

local Pet = {}

-- Well-known creature family IDs (CreatureFamily.dbc).
-- Verify via OM Explorer Pet tab if any seem wrong.
Pet.FAMILY_GHOUL    = 40   -- CreatureFamily.dbc ID 40 = "Ghoul"

--- Cached per-tick to avoid multiple game calls.
local _cache = nil
local _cache_tick = -1

local function refresh()
  local tick = Pallas._last_tick or os.clock()
  if _cache and _cache_tick == tick then return _cache end

  local ok, info = pcall(game.pet_info)
  _cache = (ok and info) or { count = 0 }
  _cache_tick = tick
  return _cache
end

--- Returns true if the player has at least one active pet.
function Pet.HasPet()
  local info = refresh()
  return info.count and info.count > 0
end

--- Number of active controlled pets (usually 0 or 1).
function Pet.Count()
  local info = refresh()
  return info.count or 0
end

--- True if the primary pet is permanent (no expiration timer).
--- Returns false if no pet is active.
function Pet.IsPermanent()
  local info = refresh()
  if not info.count or info.count == 0 then return false end
  return info.is_permanent == true
end

--- Remaining duration in seconds for temporary pets, or nil for
--- permanent pets / no pet.
function Pet.TimeRemaining()
  local info = refresh()
  if not info.count or info.count == 0 then return nil end
  if info.is_permanent then return nil end
  local ms = info.time_remaining_ms
  if not ms then return nil end
  return ms / 1000.0
end

--- Raw GUID of the primary pet.  Returns guid_lo, guid_hi or nil.
function Pet.PrimaryGuid()
  local info = refresh()
  if not info.count or info.count == 0 then return nil end
  return info.guid_lo, info.guid_hi
end

--- Cached active_pets entity list (per-tick, same as pet_info).
local _pets_cache = nil
local _pets_cache_tick = -1

local function refresh_active()
  local tick = Pallas._last_tick or os.clock()
  if _pets_cache and _pets_cache_tick == tick then return _pets_cache end

  if not Pet.HasPet() then
    _pets_cache = {}
    _pets_cache_tick = tick
    return _pets_cache
  end

  local ok, pets = pcall(game.active_pets)
  _pets_cache = (ok and pets) or {}
  _pets_cache_tick = tick
  return _pets_cache
end

--- Returns true if any active pet's name contains `pattern` (case-insensitive
--- Lua pattern match).  Use plain substrings or Lua patterns.
---   Pet.HasPetNamed("Ghoul")       -- matches "Risen Ghoul", "Ghoul"
---   Pet.HasPetNamed("Ebon Gargoyle")
function Pet.HasPetNamed(pattern)
  local pets = refresh_active()
  local lp = pattern:lower()
  for i = 1, #pets do
    local n = pets[i].name
    if n and n:lower():find(lp, 1, true) then return true end
  end
  return false
end

--- Returns true if any active UI pet has the given creature family ID.
--- Use creature family constants (e.g., Pet.FAMILY_GHOUL = 40).
function Pet.HasPetOfFamily(family_id)
  local pets = refresh_active()
  for i = 1, #pets do
    if pets[i].creature_family == family_id then return true end
  end
  return false
end

--- Returns the raw entity table of the first pet with the given creature
--- family ID, or nil if none match.
function Pet.FindByFamily(family_id)
  local pets = refresh_active()
  for i = 1, #pets do
    if pets[i].creature_family == family_id then return pets[i] end
  end
  return nil
end

--- Returns the creature family ID of the primary pet, or 0 if no pet.
function Pet.GetPrimaryFamily()
  local pets = refresh_active()
  if #pets == 0 then return 0 end
  return pets[1].creature_family or 0
end

--- Returns the first active pet whose name contains `pattern` as a Unit,
--- or nil if none match.
function Pet.FindByName(pattern)
  if not Unit then return nil end
  local pets = refresh_active()
  local lp = pattern:lower()
  for i = 1, #pets do
    local n = pets[i].name
    if n and n:lower():find(lp, 1, true) then
      return Unit:New(pets[i])
    end
  end
  return nil
end

--- Returns the primary pet as a Unit object (matched from entity cache),
--- or nil if no pet is active or the entity wasn't found.
function Pet.GetPrimary()
  if not Unit then return nil end
  local pets = refresh_active()
  if #pets == 0 then return nil end
  return Unit:New(pets[1])
end

--- Returns all active pets as an array of Unit objects.
function Pet.GetAll()
  local result = {}
  if not Unit then return result end
  local pets = refresh_active()
  for i = 1, #pets do
    local u = Unit:New(pets[i])
    if u then result[#result + 1] = u end
  end
  return result
end

-- ═══════════════════════════════════════════════════════════════════
-- All-summons API (UNIT_FIELD_SUMMONEDBY match against local player)
-- Covers guardians, totems, Army of the Dead, Gargoyles, etc.
-- ═══════════════════════════════════════════════════════════════════

local _summons_cache = nil
local _summons_cache_tick = -1

local function refresh_summons()
  local tick = Pallas._last_tick or os.clock()
  if _summons_cache and _summons_cache_tick == tick then return _summons_cache end

  local ok, list = pcall(game.player_summons)
  _summons_cache = (ok and list) or {}
  _summons_cache_tick = tick
  return _summons_cache
end

--- Returns all entities summoned by the local player (raw entity tables).
--- Includes guardians, totems, pets — anything with matching summoned_by GUID.
function Pet.GetAllSummons()
  return refresh_summons()
end

--- Number of all player-owned summons in the world.
function Pet.SummonCount()
  return #refresh_summons()
end

--- Returns true if any player summon has the given creature family ID.
function Pet.HasSummonOfFamily(family_id)
  local list = refresh_summons()
  for i = 1, #list do
    if list[i].creature_family == family_id then return true end
  end
  return false
end

--- Returns the raw entity table of the first player summon with the given
--- creature family ID, or nil.
function Pet.FindSummonByFamily(family_id)
  local list = refresh_summons()
  for i = 1, #list do
    if list[i].creature_family == family_id then return list[i] end
  end
  return nil
end

--- Returns true if any player summon's name contains `pattern`
--- (case-insensitive substring match).
function Pet.HasSummonNamed(pattern)
  local list = refresh_summons()
  local lp = pattern:lower()
  for i = 1, #list do
    local n = list[i].name
    if n and n:lower():find(lp, 1, true) then return true end
  end
  return false
end

-- ═══════════════════════════════════════════════════════════════════
-- Individual ownership queries (any unit, not just player's summons)
-- RE: sub_2657C60 — three 128-bit GUID fields on every CGUnit.
-- ═══════════════════════════════════════════════════════════════════

--- Returns the first populated owner GUID (charmed > summoned > created).
--- @param cgunit number  CGUnit pointer
--- @return number, number  guid_lo, guid_hi (both 0 if no owner)
function Pet.OwnerOf(cgunit)
  return game.unit_owner(cgunit)
end

--- Returns the CHARMEDBY GUID (+0x11BA0, primary ownership).
function Pet.CharmedBy(cgunit)
  return game.unit_charmed_by(cgunit)
end

--- Returns the SUMMONEDBY GUID (+0x11BC0).
function Pet.SummonedBy(cgunit)
  return game.unit_summoned_by(cgunit)
end

--- Returns the CREATEDBY GUID (+0x11BB0).
function Pet.CreatedBy(cgunit)
  return game.unit_created_by(cgunit)
end

--- Returns true if any ownership field on the unit matches the local player.
function Pet.IsOwnedByPlayer(cgunit)
  local lp = game.local_player()
  if not lp then return false end
  local lo, hi = game.unit_owner(cgunit)
  return lo ~= 0 and lo == lp.guid_lo and hi == lp.guid_hi
end

--- Invalidate all caches (called at the start of each tick if needed).
function Pet.InvalidateCache()
  _cache = nil
  _pets_cache = nil
  _summons_cache = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Pet Control (bar-position independent, synthetic action data)
--
-- These use the game's own PetAttack/PetFollow/etc. action values,
-- so they work regardless of how the player has arranged their pet bar.
-- ═══════════════════════════════════════════════════════════════════

--- Command the pet to attack the current target.
--- @return boolean  true if the command was queued.
function Pet.Attack()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "attack")
  return ok and r == true
end

--- Command the pet to follow the player.
function Pet.Follow()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "follow")
  return ok and r == true
end

--- Set the pet to Assist stance.
function Pet.Assist()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "assist")
  return ok and r == true
end

--- Set the pet to Defensive stance.
function Pet.Defensive()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "defensive")
  return ok and r == true
end

--- Set the pet to Passive stance.
function Pet.Passive()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "passive")
  return ok and r == true
end

--- Dismiss the pet.
function Pet.Dismiss()
  if type(game.pet_action) ~= "function" then return false end
  local ok, r = pcall(game.pet_action, "dismiss")
  return ok and r == true
end

--- Move the pet to a world position (Y = vertical in WoW).
--- Bypasses the targeting cursor; sends the command directly.
--- @param x number  world X
--- @param y number  world Y (vertical)
--- @param z number  world Z
--- @return boolean  true if the command was queued.
function Pet.MoveTo(x, y, z)
  if type(game.pet_move_to) ~= "function" then return false end
  local ok, r = pcall(game.pet_move_to, x, y, z)
  return ok and r == true
end

--- Fire a pet action bar slot by 1-based index (for abilities).
--- Use this for pet spellbook abilities that live in specific bar slots.
--- @param slot number  1–10 (CastPetAction convention)
--- @return boolean  true if the command was queued.
function Pet.CastBarSlot(slot)
  if type(game.cast_pet_bar_slot) ~= "function" then return false end
  local ok, r = pcall(game.cast_pet_bar_slot, slot)
  return ok and r == true
end

return Pet

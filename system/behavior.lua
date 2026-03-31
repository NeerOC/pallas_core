-- Behavior manager (mirrors Pallas system/behavior.lua).
--
-- Loads a behavior file matching the player's class + spec, then dispatches
-- registered behavior functions each tick in BehaviorType order.

---@enum BehaviorType
BehaviorType = {
  Heal   = 1,
  Tank   = 2,
  Combat = 3,
  Rest   = 4,
  Extra  = 5,
}

-- Ordered list for deterministic iteration (Heal -> Tank -> Combat -> Rest -> Extra)
local BEHAVIOR_ORDER = {
  BehaviorType.Heal,
  BehaviorType.Tank,
  BehaviorType.Combat,
  BehaviorType.Rest,
  BehaviorType.Extra,
}

Behavior = Behavior or {}
Behavior.LoadedClass = ""
Behavior.LoadedSpec  = ""

function Behavior:Initialize()
  if not Me then return end

  local class_key = Me._class_key or ""

  -- Prefer the live spec from the OM (Me.SpecName), fall back to the
  -- manual dropdown selection in PallasSettings.
  local spec_name = Me.SpecName
  if not spec_name or spec_name == "" then
    spec_name = PallasSettings.PallasSpecName or ""
  end
  if spec_name == "" then
    print("[Pallas] No specialization detected — open the Pallas menu to select one")
    return
  end

  -- Skip reload if same class+spec
  if self.LoadedClass == class_key and self.LoadedSpec == spec_name then
    return
  end

  print("[Pallas] Initialize Behaviors")

  -- Clear existing behavior slots and draw hook (previous spec may have set one)
  for _, v in ipairs(BEHAVIOR_ORDER) do
    self[v] = {}
  end
  Pallas._behavior_draw = nil

  -- Build path: behaviors/<class>/<spec>.lua
  local spec_file = spec_name:gsub("%s+", ""):lower()
  local rel_path  = "behaviors/" .. class_key .. "/" .. spec_file .. ".lua"
  local behavior  = Pallas.include(rel_path)

  if not behavior then
    print(string.format("[Pallas] No behavior file found: %s", rel_path))
    self.LoadedClass = ""
    self.LoadedSpec  = ""
    return
  end

  if behavior.Options then
    Menu:AddOptionMenu(behavior.Options)
  end

  self:AddBehaviorFunction(behavior.Behaviors, BehaviorType.Heal)
  self:AddBehaviorFunction(behavior.Behaviors, BehaviorType.Combat)
  self:AddBehaviorFunction(behavior.Behaviors, BehaviorType.Tank)
  self:AddBehaviorFunction(behavior.Behaviors, BehaviorType.Rest)
  self:AddBehaviorFunction(behavior.Behaviors, BehaviorType.Extra)

  local loaded = 0
  for _, v in ipairs(BEHAVIOR_ORDER) do
    if self[v] and #self[v] > 0 then
      loaded = loaded + #self[v]
    end
  end

  self.LoadedClass = class_key
  self.LoadedSpec  = spec_name
  print(string.format("[Pallas] Loaded %d behaviors for %s %s",
    loaded, Me._class_name or "?", spec_name))
end

function Behavior:Update()
  -- Don't run behaviors if paused
  if PallasSettings.PallasPaused then
    return
  end
  
  for _, k in ipairs(BEHAVIOR_ORDER) do
    if not self[k] then goto continue end
    for _, fn in ipairs(self[k]) do
      local ok, err = pcall(fn)
      if not ok then
        print("[Pallas] Behavior error: " .. tostring(err))
      end
    end
    ::continue::
  end
end

function Behavior:HasBehavior(btype)
  if not self[btype] then return false end
  return #self[btype] > 0
end

function Behavior:AddBehaviorFunction(tbl, btype)
  if not tbl or not tbl[btype] then return end
  if not self[btype] then self[btype] = {} end
  table.insert(self[btype], tbl[btype])
end

return Behavior

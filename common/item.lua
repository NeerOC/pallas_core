-- Item cache and wrapper (mirrors Spell wrapper pattern).
--
-- Usage in behaviors:
--   if Item.Trinket1:Use() then return end
--   if Item.Healthstone:IsReady() then ... end
--   local trinket = Item:BySlot(13)   -- equipped trinket 1
--   local stone = Item:ByName("Healthstone")
--   local pot = Item:ById(76097)      -- Master Healing Potion
--
-- ── Lookup methods (on the Item global) ────────────────────────────
--
--   Item.XXX           Auto-resolve by name (PascalCase key, e.g.
--                      Item.Healthstone, Item.MasterHealingPotion).
--
--   Item:BySlot(slot)  Get an ItemWrapper for an equipped slot (1-19).
--                      Uses game.EQUIP_SLOT constants.
--
--   Item:ById(id)      Get an ItemWrapper for an item by database ID.
--                      Searches equipped items first, then bags.
--
--   Item:ByName(name)  Get an ItemWrapper by display name (case-insensitive
--                      substring match). Searches equipped first, then bags.
--
-- ── ItemWrapper ────────────────────────────────────────────────────

local USE_THROTTLE = 1.0

local ItemWrapper = {}
ItemWrapper.__index = ItemWrapper

function ItemWrapper:new(info, equip_slot, bag, bag_slot)
  return setmetatable({
    Id         = info and info.id or 0,
    Name       = info and info.name or "",
    Count      = info and info.count or 0,
    Quality    = info and info.quality or -1,
    ItemLevel  = info and info.item_level or 0,
    ObjPtr     = info and info.obj_ptr or nil,
    EquipSlot  = equip_slot or 0,  -- >0 = equipped slot (1-19)
    BagIndex   = bag,              -- nil=equipped, 0=backpack, 1-4=bags
    BagSlot    = bag_slot,         -- 0-based slot within bag
    _use_until = 0,
  }, ItemWrapper)
end

function ItemWrapper:IsValid()
  return self.Id > 0
end

function ItemWrapper:IsEquipped()
  return self.EquipSlot > 0
end

function ItemWrapper:IsInBag()
  return self.BagIndex ~= nil
end

function ItemWrapper:GetCooldown()
  if not self:IsValid() then return nil end
  if self:IsEquipped() then
    local ok, start, dur, enabled = pcall(game.item_cooldown, self.EquipSlot)
    if ok and start then
      return { start = start, duration = dur, enabled = enabled }
    end
  elseif self:IsInBag() then
    local ok, start, dur, enabled = pcall(game.bag_item_cooldown, self.BagIndex, self.BagSlot)
    if ok and start then
      return { start = start, duration = dur, enabled = enabled }
    end
  end
  return nil
end

function ItemWrapper:IsOnCooldown()
  local cd = self:GetCooldown()
  if not cd or cd.duration <= 0 then return false end
  local now = game.game_time() * 0.001
  local elapsed = now - cd.start * 0.001
  return elapsed < cd.duration * 0.001
end

function ItemWrapper:IsReady()
  if not self:IsValid() then return false end
  local now = os.clock()
  if now < self._use_until then return false end
  return not self:IsOnCooldown()
end

function ItemWrapper:CooldownRemaining()
  local cd = self:GetCooldown()
  if not cd or cd.duration <= 0 then return 0 end
  local now = game.game_time() * 0.001
  local elapsed = now - cd.start * 0.001
  local remaining = cd.duration * 0.001 - elapsed
  return remaining > 0 and remaining or 0
end

function ItemWrapper:Use()
  if not self:IsValid() then return false end
  local now = os.clock()
  if now < self._use_until then return false end

  local ok, result
  if self:IsEquipped() then
    ok, result = pcall(game.use_item, self.EquipSlot)
  elseif self:IsInBag() then
    ok, result = pcall(game.use_bag_item, self.BagIndex, self.BagSlot)
  else
    return false
  end

  if ok and result then
    self._use_until = now + USE_THROTTLE
    return true
  end
  return false
end

-- ── NullItem ───────────────────────────────────────────────────────

local NullItem = ItemWrapper:new(nil)

-- ── Helpers ────────────────────────────────────────────────────────

local function fmtItemKey(name)
  local function tchelper(first, rest)
    return first:upper() .. rest:lower()
  end
  return name:gsub("(%a)([%w_'-]*)", tchelper):gsub("[%s_'%-:(),]+", "")
end

local function lower_trim(s)
  return s:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Named slot aliases for Item.Trinket1 / Item.MainHand / etc.
local SLOT_ALIASES = {
  Head = 1, Neck = 2, Shoulder = 3, Shirt = 4, Chest = 5,
  Waist = 6, Legs = 7, Feet = 8, Wrist = 9, Hands = 10,
  Finger1 = 11, Finger2 = 12, Trinket1 = 13, Trinket2 = 14,
  Back = 15, MainHand = 16, OffHand = 17, Ranged = 18, Tabard = 19,
}

-- ── Snapshot scan ──────────────────────────────────────────────────

local function scan_inventory()
  local ok, inv = pcall(game.inventory)
  if not ok or not inv then return nil, nil end

  local equipped = {}   -- slot → info
  local bag_items = {}  -- flat array of {info=..., bag=..., slot=...}

  if inv.equipped then
    for slot = 1, 19 do
      local info = inv.equipped[slot]
      if info and info.id and info.id > 0 then
        equipped[slot] = info
      end
    end
  end

  if inv.bags then
    for b = 1, #inv.bags do
      local bag = inv.bags[b]
      if bag and bag.items then
        local game_bag = bag.bag_index  -- -1=backpack, 0-3=bags
        local c_bag = game_bag          -- for game.use_bag_item / bag_item_cooldown
        if game_bag == -1 then c_bag = 0
        elseif game_bag >= 0 then c_bag = game_bag + 1
        end
        for s = 1, (bag.num_slots or 0) do
          local info = bag.items[s]
          if info and info.id and info.id > 0 then
            bag_items[#bag_items + 1] = { info = info, bag = c_bag, slot = s - 1 }
          end
        end
      end
    end
  end

  return equipped, bag_items
end

-- ── Item global ────────────────────────────────────────────────────

local ItemCache = {}  -- key → ItemWrapper (name-based cache)

Item = setmetatable({
  Cache = ItemCache,
  NullItem = NullItem,
  Wrapper = ItemWrapper,
}, {
  __index = function(tbl, key)
    -- Check named slot aliases first (Item.Trinket1, Item.MainHand, etc.)
    local alias_slot = SLOT_ALIASES[key]
    if alias_slot then
      return Item:BySlot(alias_slot)
    end

    -- Check name cache
    if ItemCache[key] then
      local w = ItemCache[key]
      if w:IsValid() then return w end
    end

    -- Try to find by formatted name
    local found = Item:ByName(key)
    if found:IsValid() then
      ItemCache[key] = found
      return found
    end

    return NullItem
  end,
})

--- Get an ItemWrapper for an equipped slot.
--- @param slot number Equipment slot (1-19), use game.EQUIP_SLOT constants.
--- @return ItemWrapper
function Item:BySlot(slot)
  if not slot or slot < 1 or slot > 19 then return NullItem end
  local equipped, _ = scan_inventory()
  if not equipped then return NullItem end
  local info = equipped[slot]
  if not info then return NullItem end
  return ItemWrapper:new(info, slot, nil, nil)
end

--- Get an ItemWrapper for an item by database ID.
--- Searches equipped items first, then bags. Returns the first match.
--- @param id number Item database entry ID.
--- @return ItemWrapper
function Item:ById(id)
  if not id or id <= 0 then return NullItem end
  local equipped, bag_items = scan_inventory()
  if not equipped and not bag_items then return NullItem end

  -- Search equipped
  if equipped then
    for slot, info in pairs(equipped) do
      if info.id == id then
        return ItemWrapper:new(info, slot, nil, nil)
      end
    end
  end

  -- Search bags
  if bag_items then
    for _, entry in ipairs(bag_items) do
      if entry.info.id == id then
        return ItemWrapper:new(entry.info, 0, entry.bag, entry.slot)
      end
    end
  end

  return NullItem
end

--- Get an ItemWrapper by display name.
--- Case-insensitive match. Tries exact match first, then substring.
--- Searches equipped first, then bags.
--- @param name string Item display name (or PascalCase key like "MasterHealingPotion").
--- @return ItemWrapper
function Item:ByName(name)
  if not name or name == "" then return NullItem end

  -- Expand PascalCase to spaced form for matching:
  -- "MasterHealingPotion" → "master healing potion"
  local search = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", " %1%2")
  search = lower_trim(search)

  local equipped, bag_items = scan_inventory()
  if not equipped and not bag_items then return NullItem end

  -- Exact match pass (case-insensitive)
  if equipped then
    for slot, info in pairs(equipped) do
      if info.name and lower_trim(info.name) == search then
        return ItemWrapper:new(info, slot, nil, nil)
      end
    end
  end
  if bag_items then
    for _, entry in ipairs(bag_items) do
      if entry.info.name and lower_trim(entry.info.name) == search then
        return ItemWrapper:new(entry.info, 0, entry.bag, entry.slot)
      end
    end
  end

  -- Substring match pass
  if equipped then
    for slot, info in pairs(equipped) do
      if info.name and lower_trim(info.name):find(search, 1, true) then
        return ItemWrapper:new(info, slot, nil, nil)
      end
    end
  end
  if bag_items then
    for _, entry in ipairs(bag_items) do
      if entry.info.name and lower_trim(entry.info.name):find(search, 1, true) then
        return ItemWrapper:new(entry.info, 0, entry.bag, entry.slot)
      end
    end
  end

  return NullItem
end

--- Get all items matching a given item ID (e.g. multiple stacks).
--- @param id number Item database entry ID.
--- @return ItemWrapper[] Array of matching ItemWrappers.
function Item:AllById(id)
  if not id or id <= 0 then return {} end
  local equipped, bag_items = scan_inventory()
  local results = {}

  if equipped then
    for slot, info in pairs(equipped) do
      if info.id == id then
        results[#results + 1] = ItemWrapper:new(info, slot, nil, nil)
      end
    end
  end

  if bag_items then
    for _, entry in ipairs(bag_items) do
      if entry.info.id == id then
        results[#results + 1] = ItemWrapper:new(entry.info, 0, entry.bag, entry.slot)
      end
    end
  end

  return results
end

--- Get total count of an item across all bags + equipped.
--- @param id number Item database entry ID.
--- @return number Total stack count.
function Item:TotalCount(id)
  if not id or id <= 0 then return 0 end
  local total = 0
  local equipped, bag_items = scan_inventory()

  if equipped then
    for _, info in pairs(equipped) do
      if info.id == id then total = total + (info.count or 1) end
    end
  end

  if bag_items then
    for _, entry in ipairs(bag_items) do
      if entry.info.id == id then total = total + (entry.info.count or 1) end
    end
  end

  return total
end

return Item

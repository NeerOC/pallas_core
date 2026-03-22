local bit = require("bit")
local settings = require("settings")

local Plugin = {}
Plugin.name = "Radar"
Plugin.description = "Neer's AIO Radar"
Plugin.author = "Neer"

-- ---------------------------------------------------------------------------
-- Options / Widgets (placeholders for now)
-- ---------------------------------------------------------------------------

local DEFAULTS = {
    ExtraRadar = true,
    ExtraRadarTrackHerbs = false,
    ExtraRadarTrackOres = false,
    ExtraRadarTrackQuests = true,
    ExtraRadarTrackQuestUnits = true,
    ExtraRadarTrackRareQuestUnits = true,
    ExtraRadarTrackRares = true,
    ExtraRadarTrackChests = true,
    ExtraRadarInteractQuests = false,
    ExtraRadarInteractGatherables = false,
    ExtraRadarDrawLines = true,
    ExtraRadarDrawLinesClosest = false,
    ExtraRadarDrawDistance = false,
    ExtraRadarLoadDistance = 200
}

local cfg = settings.load("radar", DEFAULTS)
local function save_cfg() settings.save("radar", cfg) end

-- ---------------------------------------------------------------------------
-- Colors / type mapping (basic placeholders)
-- ---------------------------------------------------------------------------

local colors = {
    green = imgui.color_u32(0.2, 0.9, 0.2, 1.0),
    orange = imgui.color_u32(1.0, 0.6, 0.2, 1.0),
    brown = imgui.color_u32(0.6, 0.35, 0.1, 1.0),
    silver = imgui.color_u32(0.8, 0.8, 0.9, 1.0),
    purple = imgui.color_u32(0.7, 0.3, 1.0, 1.0),
    white = imgui.color_u32(1.0, 1.0, 1.0, 1.0),
    pink = imgui.color_u32(1.0, 0.5, 0.8, 1.0),
    teal = imgui.color_u32(0.2, 0.9, 0.9, 1.0),
    yellow = imgui.color_u32(1.0, 0.9, 0.2, 1.0),
    chartreuse = imgui.color_u32(0.6, 1.0, 0.0, 1.0)
}

local objectColors = {
    H = colors.green,
    V = colors.orange,
    Q = colors.yellow,
    QU = colors.yellow,
    R = colors.pink,
    C = colors.purple
}

local LINE_THICKNESS = 1.5

-- ---------------------------------------------------------------------------
-- Gatherable type mapping by lock_id (GO descriptor property 0x04)
-- ---------------------------------------------------------------------------

-- Lock IDs are singular per gatherable type. Using named constants keeps
-- the intent clear instead of bare numbers in the logic below.
local HERB_LOCK_ID = 29
local ORE_LOCK_ID = 38
local CHEST_LOCK_ID = 57

local function get_go_lock_id(e)
    -- Prefer cached descriptor field from OM if present.
    if e.go_lock_id and e.go_lock_id > 0 then return e.go_lock_id end
    -- Fallback to C++ helper that reads property 0x04 (lockId) from GO data.
    if e.obj_ptr then
        local ok, lock_id = pcall(game.go_data, e.obj_ptr, 0x04)
        if ok and lock_id and lock_id > 0 then return lock_id end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Quest Tracking Helpers
-- ---------------------------------------------------------------------------

local quest_cache = {}
local target_cache = {}
local quest_id_map = {}
local name_match_cache = {}

-- Returns the (visible_idx)-th non-hidden objective in quest q.
-- Hidden objectives (flags & 0x08) are not exposed by C++ in target_cache,
-- so obj_idx counts only visible objectives — not raw Lua array positions.
local function get_visible_objective(q, visible_idx)
    if not q or not q.objectives then return nil end
    local count = 0
    for _, o in ipairs(q.objectives) do
        if bit.band(o.flags or 0, 0x08) == 0 then
            if count == visible_idx then return o end
            count = count + 1
        end
    end
    return nil
end

--- Returns true if the (obj_idx)-th visible objective of quest_id is complete.
--- obj_idx is 0-based and counts only non-hidden (flags & 0x08 == 0) objectives,
--- matching the numbering used by game.quest_targets().
local function is_obj_complete(quest_id, obj_idx)
    local qi_idx = quest_id_map[quest_id]
    if not qi_idx then return false end
    local q = quest_cache[qi_idx]
    local o = get_visible_objective(q, obj_idx)
    if not o then return false end
    local cur = o.progress or 0
    local req = o.required or 0
    return req > 0 and cur >= req
end

local function is_quest_target(entity, map)
    if entity.entry_id and entity.entry_id > 0 and map then
        local list = map[entity.entry_id]
        if list then
            for _, m in ipairs(list) do
                if m.obj_idx >= 0 and m.required > 0 then
                    if not is_obj_complete(m.quest_id, m.obj_idx) then
                        return true
                    end
                end
            end
        end
    end

    local ename = entity.name
    if (not ename or ename == "") and entity.unit then
        ename = entity.unit.name
    end
    if ename and ename ~= "" then
        local ename_lower = ename:lower()
        for _, nm in ipairs(name_match_cache) do
            if nm.desc_lower:find(ename_lower, 1, true) then
                return true
            end
            -- Reverse check: any significant word from the description in the entity name.
            -- Catches cases like "forest wolf" (desc) matching "Gray Forest Wolf" (entity).
            for word in nm.desc_lower:gmatch("%a+") do
                if #word >= 4 and ename_lower:find(word, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Screen lists and helpers
-- ---------------------------------------------------------------------------

local player = nil
local onscreen = {}
local offscreen = {}

local function is_offscreen(e)
    if not e.position then return true end
    local sx, sy = game.world_to_screen(e.position.x, e.position.y,
                                        e.position.z + 2.0)
    return not sx
end

local function add_to_screen_list(e, types)
    if type(types) == "string" then types = {types} end
    local list = is_offscreen(e) and offscreen or onscreen
    list[#list + 1] = {entity = e, types = types}
end

local function dist2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

-- Auto-interact timing
local last_quest_interact_time = 0
local last_gatherable_interact_time = 0
local INTERACT_COOLDOWN = 0.2 -- seconds between interacts per type

-- ---------------------------------------------------------------------------
-- Collect visuals and cache objects for interaction
-- ---------------------------------------------------------------------------

local cached_objects = {}

local function collect_visuals()
    onscreen = {}
    offscreen = {}
    cached_objects = {}

    if not game.is_logged_in() then
        player = nil
        return
    end

    player = game.local_player()
    if not player or not player.position then return end

    quest_cache = game.quest_log() or {}
    target_cache = game.quest_targets() or {}
    quest_id_map = {}
    name_match_cache = {}

    for i, q in ipairs(quest_cache) do
        quest_id_map[q.quest_id] = i
        local visible_idx = 0
        for _, o in ipairs(q.objectives or {}) do
            if bit.band(o.flags or 0, 0x08) == 0 then
                if o.description and o.description ~= "" and o.required and
                    o.required > 0 then
                    if not is_obj_complete(q.quest_id, visible_idx) then
                        name_match_cache[#name_match_cache + 1] = {
                            desc_lower = o.description:lower()
                        }
                    end
                end
                visible_idx = visible_idx + 1
            end
        end
    end

    local load_range = cfg.ExtraRadarLoadDistance or 200
    local max_dist2 = load_range * load_range

    local objects = game.objects("GameObject") or {}
    for _, e in ipairs(objects) do
        if e.position then
            local d2 = dist2(player.position, e.position)
            if d2 <= max_dist2 then
                local is_interactable = e.dynamic_flags and
                                            bit.band(e.dynamic_flags, 0x04) ~= 0
                local t = nil

                if e.go_state and e.go_state == 1 then
                    local lock_id = get_go_lock_id(e)
                    if lock_id == HERB_LOCK_ID then
                        t = "H"
                    elseif lock_id == ORE_LOCK_ID then
                        t = "V"
                    elseif lock_id == CHEST_LOCK_ID then
                        t = "C"
                    elseif is_quest_target(e, target_cache.objects) then
                        t = "Q"
                    elseif is_interactable then
                        t = "Q"
                    end
                end

                if t then
                    table.insert(cached_objects,
                                 {entity = e, type = t, dist2 = d2})

                    if (t == "Q" and cfg.ExtraRadarTrackQuests) or
                        (t == "H" and cfg.ExtraRadarTrackHerbs) or
                        (t == "V" and cfg.ExtraRadarTrackOres) or
                        (t == "C" and cfg.ExtraRadarTrackChests) then
                        add_to_screen_list(e, t)
                    end
                end
            end
        end
    end

    local units = game.objects("Unit") or {}
    for _, e in ipairs(units) do
        local u = e.unit or {}
        local is_dead = u.is_dead or false
        local is_lootable = e.is_lootable or u.is_lootable or false

        if is_lootable or not is_dead then
            if e.position then
                local d2 = dist2(player.position, e.position)
                if d2 <= max_dist2 then
                    local is_rare  = e.classification and
                                     (e.classification == 2 or e.classification == 4)
                    local is_quest = is_quest_target(e, target_cache.creatures)

                    if is_rare or is_quest then
                        local display_types = {}

                        if is_rare and cfg.ExtraRadarTrackRares then
                            display_types[#display_types + 1] = "R"
                        end

                        if is_quest and cfg.ExtraRadarTrackQuestUnits then
                            if not is_rare or cfg.ExtraRadarTrackRareQuestUnits then
                                display_types[#display_types + 1] = "QU"
                            end
                        end

                        if #display_types > 0 then
                            add_to_screen_list(e, display_types)
                        end
                    end
                end
            end
        end
    end

    if cfg.ExtraRadarDrawLinesClosest and #onscreen > 1 and player and
        player.position then
        table.sort(onscreen, function(a, b)
            return dist2(player.position, a.entity.position) <
                       dist2(player.position, b.entity.position)
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------

local function draw_colored_lines()
    if not cfg.ExtraRadarDrawLines then return end
    if not player or not player.position then return end

    local sx_p, sy_p = game.world_to_screen(player.position.x,
                                            player.position.y, player.position.z)
    if not sx_p then return end

    if cfg.ExtraRadarDrawLinesClosest then
        local first = onscreen[1]
        if not first or not first.entity.position then return end
        local e = first.entity
        local t = first.types[1]
        local sx, sy = game.world_to_screen(e.position.x, e.position.y,
                                            e.position.z)
        if not sx then return end
        local col = objectColors[t] or colors.white
        imgui.draw_line(sx_p, sy_p, sx, sy, col, LINE_THICKNESS)
        return
    end

    for _, item in ipairs(onscreen) do
        local e = item.entity
        if e.position then
            local sx, sy = game.world_to_screen(e.position.x, e.position.y,
                                                e.position.z)
            if sx then
                local col = objectColors[item.types[1]] or colors.white
                imgui.draw_line(sx_p, sy_p, sx, sy, col, LINE_THICKNESS)
            end
        end
    end
end

local function draw_colored_text()
    if not player or not player.position then return end

    local px, py = game.world_to_screen(player.position.x, player.position.y,
                                        player.position.z + 1.0)
    if px then
        local count = #offscreen
        if count > 0 then
            imgui.draw_text(px, py + 20, colors.teal,
                            string.format("Offscreen: %d", count))
        end
    end

    for _, item in ipairs(onscreen) do
        local e = item.entity
        if e.position then
            local sx, sy = game.world_to_screen(e.position.x, e.position.y,
                                                e.position.z + 2.0)
            if sx then
                local name = e.name or "Object"
                local suffix = name

                if cfg.ExtraRadarDrawDistance then
                    local d = math.sqrt(dist2(player.position, e.position))
                    suffix = suffix .. string.format(" (%.0f yd)", d)
                end

                -- Draw each type tag; name rendered alongside the first tag only.
                local y_off = 0
                for i, t in ipairs(item.types) do
                    local type_col = objectColors[t] or colors.white
                    local prefix = "[" .. t .. "] "
                    imgui.draw_text(sx, sy + y_off, type_col, prefix)
                    if i == 1 then
                        imgui.draw_text(sx + 20, sy + y_off, colors.white, suffix)
                    end
                    y_off = y_off + 14
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Main radar dispatcher
-- ---------------------------------------------------------------------------

local function run_radar()
    if not cfg.ExtraRadar then return end

    if not game.is_logged_in() then
        player = nil
        return
    end

    player = game.local_player()

    collect_visuals()

    -- Optional: interact with nearby GameObjects.
    if player and player.position then
        local now = game.game_time()

        local best_quest, bq_d2 = nil, nil
        local best_gather, bg_d2 = nil, nil

        for _, obj in ipairs(cached_objects) do
            if obj.entity and obj.entity.obj_ptr and obj.dist2 and obj.dist2 < 49 then
                if obj.type == "Q" and cfg.ExtraRadarInteractQuests then
                    if not best_quest or obj.dist2 < bq_d2 then
                        best_quest, bq_d2 = obj.entity, obj.dist2
                    end
                elseif (obj.type == "H" or obj.type == "V") and
                    cfg.ExtraRadarInteractGatherables then
                    if not best_gather or obj.dist2 < bg_d2 then
                        best_gather, bg_d2 = obj.entity, obj.dist2
                    end
                end
            end
        end

        if best_quest and (now - last_quest_interact_time) >= INTERACT_COOLDOWN then
            if best_quest.dynamic_flags and
                (bit.band(best_quest.dynamic_flags, 0x04) ~= 0 or
                    bit.band(best_quest.dynamic_flags, 0x4000) ~= 0) then
                if game.interact(best_quest.obj_ptr) then
                    last_quest_interact_time = now
                end
            end
        end

        if best_gather and (now - last_gatherable_interact_time) >=
            INTERACT_COOLDOWN then
            local can_interact = false
            if best_gather.dynamic_flags and
                (bit.band(best_gather.dynamic_flags, 0x04) ~= 0 or
                    bit.band(best_gather.dynamic_flags, 0x4000) ~= 0) then
                can_interact = true
            elseif best_gather.go_state and best_gather.go_state == 1 then
                local lock_id = get_go_lock_id(best_gather)
                if lock_id == HERB_LOCK_ID or lock_id == ORE_LOCK_ID then
                    can_interact = true
                end
            end

            if can_interact then
                if game.interact(best_gather.obj_ptr) then
                    last_gatherable_interact_time = now
                end
            end
        end
    end

    draw_colored_text()
    draw_colored_lines()
end

-- ---------------------------------------------------------------------------
-- Settings UI (widgets)
-- ---------------------------------------------------------------------------

local function draw_settings()
    local changed, value

    changed, value = imgui.checkbox("Enable Radar", cfg.ExtraRadar)
    if changed then
        cfg.ExtraRadar = value;
        save_cfg()
    end

    imgui.separator()
    imgui.text_colored(0.6, 0.85, 1.0, 0.9, "Quests")

    changed, value = imgui.checkbox("Track Quest Objects",
                                    cfg.ExtraRadarTrackQuests)
    if changed then
        cfg.ExtraRadarTrackQuests = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Track Quest Units",
                                    cfg.ExtraRadarTrackQuestUnits)
    if changed then
        cfg.ExtraRadarTrackQuestUnits = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Show Rare Quest Units as Quest Too",
                                    cfg.ExtraRadarTrackRareQuestUnits)
    if changed then
        cfg.ExtraRadarTrackRareQuestUnits = value; save_cfg()
    end

    changed, value = imgui.checkbox("Interact With Nearby Quest Objects",
                                    cfg.ExtraRadarInteractQuests)
    if changed then
        cfg.ExtraRadarInteractQuests = value;
        save_cfg()
    end

    imgui.separator()
    imgui.text_colored(0.6, 0.85, 1.0, 0.9, "Gathering")

    changed, value = imgui.checkbox("Track Herbs", cfg.ExtraRadarTrackHerbs)
    if changed then
        cfg.ExtraRadarTrackHerbs = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Track Ores", cfg.ExtraRadarTrackOres)
    if changed then
        cfg.ExtraRadarTrackOres = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Interact With Nearby Gatherables",
                                    cfg.ExtraRadarInteractGatherables)
    if changed then
        cfg.ExtraRadarInteractGatherables = value;
        save_cfg()
    end

    imgui.separator()
    imgui.text_colored(0.6, 0.85, 1.0, 0.9, "Specials")

    changed, value = imgui.checkbox("Track Rares", cfg.ExtraRadarTrackRares)
    if changed then
        cfg.ExtraRadarTrackRares = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Track Treasure Chests",
                                    cfg.ExtraRadarTrackChests)
    if changed then
        cfg.ExtraRadarTrackChests = value;
        save_cfg()
    end

    imgui.separator()
    imgui.text_colored(0.6, 0.85, 1.0, 0.9, "Drawing")

    changed, value = imgui.checkbox("Draw Lines", cfg.ExtraRadarDrawLines)
    if changed then
        cfg.ExtraRadarDrawLines = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Draw Closest Only",
                                    cfg.ExtraRadarDrawLinesClosest)
    if changed then
        cfg.ExtraRadarDrawLinesClosest = value;
        save_cfg()
    end

    changed, value = imgui.checkbox("Draw Distance", cfg.ExtraRadarDrawDistance)
    if changed then
        cfg.ExtraRadarDrawDistance = value;
        save_cfg()
    end

    imgui.separator()
    changed, value = imgui.slider_int("Radar Load Distance",
                                      cfg.ExtraRadarLoadDistance, 1, 200)
    if changed then
        cfg.ExtraRadarLoadDistance = value;
        save_cfg()
    end
end

-- ---------------------------------------------------------------------------
-- Plugin interface
-- ---------------------------------------------------------------------------

function Plugin.onEnable() console.log("[Radar] Enabled") end

function Plugin.onDisable() console.log("[Radar] Disabled") end

function Plugin.onTick() end

function Plugin.onDraw()
    run_radar()

    local visible = imgui.begin_window("Radar")
    if not visible then
        imgui.end_window()
        return
    end

    draw_settings()
    imgui.end_window()
end

return Plugin

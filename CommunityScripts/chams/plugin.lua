local settings = require("settings")

local Plugin = {}
Plugin.name = "Chams"
Plugin.description = "Highlights nearby entities with outline glow."
Plugin.author = "Community"

local DEFAULTS = {
    enabled = true,
    show_hostile = true,
    show_friendly = false,
    show_neutral = false,
    show_players = false,
    show_rares = true,
    show_quest = true,
    max_range = 40,
    max_highlights = 5,
}

local cfg = {}
local debug_info = {
    total_units = 0,
    in_range = 0,
    candidates = 0,
    slots_written = 0,
    type_counts = {},
    last_error = nil,
    outline_results = {},
}

function Plugin.onEnable()
    cfg = settings.load("CommunityScripts\\chams", DEFAULTS)
end

function Plugin.onDisable()
    for i = 0, 4 do
        game.outline_clear(i)
    end
    settings.save("CommunityScripts\\chams", cfg)
end

local function dist_sq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function classify_entity(entity, quest_creatures)
    local u = entity.unit
    if not u or u.is_dead then return nil end

    if u.is_player then return "players" end

    local cls = u.classification
    if cls == "rare" or cls == "rareelite" then return "rares" end

    if quest_creatures and entity.entry_id and quest_creatures[entity.entry_id] then
        return "quest"
    end

    if game.unit_is_enemy(entity.obj_ptr) then return "hostile" end

    local reaction = game.unit_reaction(entity.obj_ptr)
    if reaction == 4 then return "neutral" end

    if game.unit_is_friend(entity.obj_ptr) then return "friendly" end

    return nil
end

local TYPE_SETTINGS = {
    hostile  = "show_hostile",
    neutral  = "show_neutral",
    friendly = "show_friendly",
    players  = "show_players",
    rares    = "show_rares",
    quest    = "show_quest",
}

function Plugin.onTick()
    if not cfg.enabled then
        for i = 0, 4 do game.outline_clear(i) end
        return
    end

    local player = game.local_player()
    if not player or not player.position then
        return
    end

    local pos = player.position
    local max_dist_sq = cfg.max_range * cfg.max_range

    local quest_creatures = nil
    if cfg.show_quest then
        local qt = game.quest_targets()
        if qt then quest_creatures = qt.creatures end
    end

    local candidates = {}
    local type_counts = {}
    local total_units = 0
    local in_range = 0

    for _, entity in ipairs(game.objects("Unit")) do
        total_units = total_units + 1
        if entity.position then
            local d2 = dist_sq(pos, entity.position)
            if d2 <= max_dist_sq then
                in_range = in_range + 1
                local etype = classify_entity(entity, quest_creatures)
                if etype then
                    type_counts[etype] = (type_counts[etype] or 0) + 1
                    if cfg[TYPE_SETTINGS[etype]] then
                        candidates[#candidates + 1] = { obj_ptr = entity.obj_ptr, dist2 = d2, name = entity.name }
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.dist2 < b.dist2 end)

    local n = math.min(#candidates, cfg.max_highlights)
    local outline_results = {}
    for i = 1, n do
        local slot = 5 - i
        local ok = game.outline_write(candidates[i].obj_ptr, slot)
        outline_results[#outline_results + 1] = {
            slot = slot,
            name = candidates[i].name or "?",
            dist = math.sqrt(candidates[i].dist2),
            ok = ok,
        }
    end

    -- e.g. if n=3, slots 4,3,2 are used; clear slots 1 and 0
    local lowest_used = 5 - n
    for slot = lowest_used - 1, 0, -1 do
        game.outline_clear(slot)
    end

    debug_info.total_units = total_units
    debug_info.in_range = in_range
    debug_info.candidates = #candidates
    debug_info.slots_written = n
    debug_info.type_counts = type_counts
    debug_info.outline_results = outline_results
end

function Plugin.onDraw()
    if not next(cfg) then return end

    local vis, open = imgui.begin_window("Chams", 0)
    if not vis or not open then
        imgui.end_window()
        return
    end

    local dirty = false
    local changed, val

    changed, val = imgui.checkbox("Enabled", cfg.enabled)
    if changed then cfg.enabled = val; dirty = true end

    imgui.separator()
    imgui.text("Entity Types")

    changed, val = imgui.checkbox("Hostile", cfg.show_hostile)
    if changed then cfg.show_hostile = val; dirty = true end

    changed, val = imgui.checkbox("Neutral", cfg.show_neutral)
    if changed then cfg.show_neutral = val; dirty = true end

    changed, val = imgui.checkbox("Friendly", cfg.show_friendly)
    if changed then cfg.show_friendly = val; dirty = true end

    changed, val = imgui.checkbox("Players", cfg.show_players)
    if changed then cfg.show_players = val; dirty = true end

    changed, val = imgui.checkbox("Rares", cfg.show_rares)
    if changed then cfg.show_rares = val; dirty = true end

    changed, val = imgui.checkbox("Quest Mobs", cfg.show_quest)
    if changed then cfg.show_quest = val; dirty = true end

    imgui.separator()
    imgui.text("Settings")

    changed, val = imgui.slider_int("Max Range", cfg.max_range, 1, 100)
    if changed then cfg.max_range = val; dirty = true end

    changed, val = imgui.slider_int("Max Highlights", cfg.max_highlights, 1, 5)
    if changed then cfg.max_highlights = val; dirty = true end

    if dirty then settings.save("CommunityScripts\\chams", cfg) end

    imgui.separator()
    imgui.text("Debug")
    imgui.text(string.format("Total units: %d", debug_info.total_units))
    imgui.text(string.format("In range: %d", debug_info.in_range))
    imgui.text(string.format("Candidates (enabled types): %d", debug_info.candidates))
    imgui.text(string.format("Slots written: %d", debug_info.slots_written))

    if next(debug_info.type_counts) then
        imgui.text("Types found in range:")
        for etype, count in pairs(debug_info.type_counts) do
            local enabled = cfg[TYPE_SETTINGS[etype]] and "ON" or "OFF"
            imgui.text(string.format("  %s: %d [%s]", etype, count, enabled))
        end
    end

    if #debug_info.outline_results > 0 then
        imgui.text("Outline slots:")
        for _, r in ipairs(debug_info.outline_results) do
            imgui.text(string.format("  slot %d: %s (%.1fyd) %s",
                r.slot, r.name, r.dist, r.ok and "OK" or "FAIL"))
        end
    end

    imgui.end_window()
end

return Plugin

local options = {
    Name = "Shaman (Restoration)", -- shown as collapsing header

    Widgets = {
        { type = "header",   text = "General" },
        { type = "slider",   uid = "RestoShamanDPSAboveHP",        text = "DPS Above Health %",              default = 80,  min = 0,                                         max = 100 },

        { type = "header",   text = "Single Target Healing" },
        { type = "slider",   uid = "RestoShamanHealingSurge",      text = "Healing Surge %",                 default = 65,  min = 0,                                         max = 100 },
        { type = "slider",   uid = "RestoShamanHealingWave",       text = "Healing Wave %",                  default = 80,  min = 0,                                         max = 100 },
        { type = "slider",   uid = "RestoShamanRiptide",           text = "Riptide %",                       default = 90,  min = 0,                                         max = 100 },

        { type = "header",   text = "AoE Healing" },
        { type = "slider",   uid = "RestoShamanChainHealCount",    text = "Chain Heal - Nearby Members",     default = 3,   min = 1,                                         max = 5 },
        { type = "slider",   uid = "RestoShamanChainHealHealth",   text = "Chain Heal - Health %",           default = 75,  min = 0,                                         max = 100 },
        { type = "slider",   uid = "RestoShamanHSTCount",          text = "Healing Stream Totem - Members",  default = 3,   min = 1,                                         max = 5 },
        { type = "slider",   uid = "RestoShamanHSTHealth",         text = "Healing Stream Totem - Health %", default = 80,  min = 0,                                         max = 100 },

        { type = "header",   text = "Utility" },
        { type = "combobox", uid = "RestoShamanEarthShieldTarget", text = "Earth Shield",                    default = 0,   options = { "Tank 1", "Tank 2", "Off" } },
        { type = "combobox", uid = "RestoShamanWeaponImbue",       text = "Weapon Imbue",                    default = 0,   options = { "Flametongue", "Earthliving" } },
        { type = "combobox", uid = "RestoShamanShieldBuff",        text = "Shield Buff",                     default = 0,   options = { "Water Shield", "Lightning Shield" } },
    },
}

-- Find a player-owned summon entity by name substring (case-insensitive).
-- Returns the raw entity table (with .position) or nil.
local function find_my_summon(name_pattern)
    local summons = Pet.GetAllSummons()
    local lp = name_pattern:lower()
    for _, s in ipairs(summons) do
        local n = s.name
        if n and n:lower():find(lp, 1, true) then return s end
    end
    return nil
end

-- Distance between two position tables {x, y, z}.
local function pos_distance(a, b)
    if not a or not b then return 999 end
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function DoRotation()
    if Me.IsMounted then return end
    if Me:IsDisabled() then return end

    local lowest = Heal:GetLowestMember()

    -- ── Stop Casting: cancel heals that are no longer needed ───────
    -- cast_target_lo isn't populated for friendly heal casts in the OM,
    -- so we check lowest member — if they don't need it, nobody does.
    local surge_pct = PallasSettings.RestoShamanHealingSurge or 65
    local wave_pct  = PallasSettings.RestoShamanHealingWave or 80

    if Me.CastingSpellId == Spell.HealingSurge.Id and (not lowest or lowest.HealthPct > surge_pct) then
        Me:StopCasting()
    elseif Me.CastingSpellId == Spell.HealingWave.Id and (not lowest or lowest.HealthPct > wave_pct) then
        Me:StopCasting()
        end

    if Me:IsCastingOrChanneling() then
        return
    end

    -- ── Off-GCD: Interrupt ─────────────────────────────────────────
    if Spell.WindShear:Interrupt() then
        return
    end

    -- ── Off-GCD: Astral Shift (defensive when multiple enemies on us)
    local enemies_on_me = 0
    for _, u in ipairs(Combat.Targets or {}) do
        local t = u:GetTarget()
        if t and t.Guid == Me.Guid then
            enemies_on_me = enemies_on_me + 1
        end
    end
    if enemies_on_me > 1 and not Me:HasAura("Astral Shift") and Spell.AstralShift:CastEx(Me) then
        return
    end

    if Spell:IsGCDActive() then
        return
    end

    -- ── Pre-compute shared healing state ───────────────────────────
    local all_friends = Heal.Friends and Heal.Friends.All or {}
    local riptide_pct = PallasSettings.RestoShamanRiptide or 90
    local ch_count    = PallasSettings.RestoShamanChainHealCount or 3
    local ch_health   = PallasSettings.RestoShamanChainHealHealth or 75
    local hst_count   = PallasSettings.RestoShamanHSTCount or 3
    local hst_health  = PallasSettings.RestoShamanHSTHealth or 80

    -- Single pass: count members below each threshold
    local members_below_ch  = {}
    local members_below_hst = 0
    for _, f in ipairs(all_friends) do
        if f.HealthPct < ch_health then
            members_below_ch[#members_below_ch + 1] = f
        end
        if f.HealthPct < hst_health then
            members_below_hst = members_below_hst + 1
        end
    end

    -- ── Emergency Single Target ──────────────────────────────────
    if lowest then
        if lowest.HealthPct < surge_pct and Spell.HealingSurge:CastEx(lowest, { skipFacing = true }) then
            return
        end
    end

    -- ── AoE Healing ────────────────────────────────────────────────
    if #members_below_ch >= ch_count then
        for _, member in ipairs(members_below_ch) do
            local nearby = Heal:GetMembersAround(member, 30, ch_health)
            if nearby > ch_count and Spell.ChainHeal:CastEx(member, { skipFacing = true }) then
                return
            end
        end
    end

    if members_below_hst >= hst_count and Spell.HealingStreamTotem:CastEx(Me, { skipFacing = true }) then
        return
    end

    -- Totemic Projection: relocate Healing Stream Totem to lowest member
    -- if the totem is >30 yd from any healing target
    if lowest then
        local hst_entity = find_my_summon("Healing Stream Totem")
        if hst_entity and hst_entity.position then
            local too_far = true
            for _, f in ipairs(all_friends) do
                if f.Position and pos_distance(hst_entity.position, f.Position) <= 30 then
                    too_far = false
                    break
                end
            end
            if too_far and lowest.Position then
                if Spell.TotemicProjection:CastAtPos(lowest) then
                    return
                end
            end
        end
    end

    -- ── Single Target Healing (continued) ──────────────────────────
    if lowest then
        if lowest.HealthPct < wave_pct and Spell.HealingWave:CastEx(lowest, { skipFacing = true }) then
            return
        end

        if lowest.HealthPct < riptide_pct and Spell.Riptide:CastEx(lowest, { skipFacing = true }) then
            return
        end
    end

    -- ── Utility ────────────────────────────────────────────────────
    local es_choice = PallasSettings.RestoShamanEarthShieldTarget or 0
    if es_choice ~= 2 then                             -- not "Off"
        local tank = Heal.Friends.Tanks[es_choice + 1] -- 0=Tank1, 1=Tank2
        if tank and not tank:HasAura("Earth Shield") and Spell.EarthShield:CastEx(tank) then
            return
        end
    end

    if Spell.PurifySpirit:Dispel(true, { DispelType.Magic, DispelType.Curse }) then
        return
    end

    -- Resurrect current target if dead
    local myTarget = Me.Target
    if myTarget and myTarget.IsDead and myTarget.IsPlayer and Spell.AncestralSpirit:CastEx(myTarget) then
        return
    end

    -- ── Damage (only when healing is comfortable) ──────────────────
    local dps_above_hp = PallasSettings.RestoShamanDPSAboveHP or 80
    if lowest and (lowest.HealthPct < dps_above_hp or Me.PowerPct < 60) then
        return
    end

    -- Self-buffs: weapon imbue
    local imbue_choice = PallasSettings.RestoShamanWeaponImbue or 0
    if imbue_choice == 0 then
        if not Me:HasAura("Flametongue Weapon (Passive)") and Spell.FlametongueWeapon:CastEx(Me) then
            return
        end
    else
        if not Me:HasAura("Earthliving Weapon (Passive)") and Spell.EarthlivingWeapon:CastEx(Me) then
            return
        end
    end

    -- Self-buffs: shield
    local shield_choice = PallasSettings.RestoShamanShieldBuff or 0
    if shield_choice == 0 then
        if not Me:HasAura("Water Shield") and Spell.WaterShield:CastEx(Me) then
            return
        end
    else
        if not Me:HasAura("Lightning Shield") and Spell.LightningShield:CastEx(Me) then
            return
        end
    end

    local target = Combat.BestTarget
    if not target then
        return
    end

    -- Magma Totem: big AoE packs (skip if already active)
    if Combat:GetEnemiesWithinDistance(10) > 8 and not Pet.HasSummonNamed("Magma Totem") and Spell.MagmaTotem:CastEx(Me) then
        return
    end

    -- Lava Burst: highest damage priority, cast on any target with our Flame Shock
    if target:GetAuraByMe("Flame Shock") and Spell.LavaBurst:CastEx(target) then
        return
    end

    for _, u in ipairs(Combat.Targets or {}) do
        if u.Guid ~= target.Guid and u:GetAuraByMe("Flame Shock") and Spell.LavaBurst:CastEx(u) then
            return
        end
    end

    if Combat:GetTargetsAround(target, 12) >= 2 and Spell.ChainLightning:CastEx(target) then
        return
    end

    -- Flame Shock spread: best target first, then other combat targets
    if not target:HasAura("Flame Shock") and Spell.FlameShock:CastEx(target) then
        return
    end

    for _, u in ipairs(Combat.Targets or {}) do
        if u.Guid ~= target.Guid and not u:HasAura("Flame Shock") and Spell.FlameShock:CastEx(u) then
            return
        end
    end

    if Spell.LightningBolt:CastEx(target, { skipMoving = true }) then
        return
    end
end

local behaviors = {
    [BehaviorType.Heal] = DoRotation,
    [BehaviorType.Combat] = DoRotation,
}

return { Options = options, Behaviors = behaviors }

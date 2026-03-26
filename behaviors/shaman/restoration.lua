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
        { type = "slider",   uid = "RestoShamanHSTCount",          text = "Healing Stream Totem - Members",  default = 3,   min = 1,                                         max = 5 },
        { type = "slider",   uid = "RestoShamanHSTHealth",         text = "Healing Stream Totem - Health %", default = 80,  min = 0,                                         max = 100 },

        { type = "header",   text = "Utility" },
        { type = "combobox", uid = "RestoShamanEarthShieldTarget", text = "Earth Shield",                    default = 0,   options = { "Tank 1", "Tank 2", "Off" } },
        { type = "checkbox", uid = "RestoShamanPurifySpirit",      text = "Purify Spirit",                   default = true },
        { type = "combobox", uid = "RestoShamanWeaponImbue",       text = "Weapon Imbue",                    default = 0,   options = { "Flametongue", "Earthliving" } },
        { type = "combobox", uid = "RestoShamanShieldBuff",        text = "Shield Buff",                     default = 0,   options = { "Water Shield", "Lightning Shield" } },
    },
}

local function DoRotation()
    local lowest = Heal:GetLowestMember()

    -- Cancel Healing Surge if nobody needs healing
    local surge_pct = PallasSettings.RestoShamanHealingSurge or 65
    if (Me.CastingSpellId == Spell.HealingSurge.Id) and (not lowest or lowest.HealthPct > surge_pct) then
        Me:StopCasting()
    end

    if Me:IsCastingOrChanneling() then
        return
    end

    if Spell.WindShear:Interrupt() then
        return
    end

    if Spell:IsGCDActive() then
        return
    end

    -- Single Target Healing
    if lowest then
        if lowest.HealthPct < surge_pct and Spell.HealingSurge:CastEx(lowest) then
            return
        end
    end

    -- AoE Healing
    local hst_count = PallasSettings.RestoShamanHSTCount or 3
    local hst_health = PallasSettings.RestoShamanHSTHealth or 80
    local _, members_below = Heal:GetMembersBelow(hst_health)
    if members_below >= hst_count and Spell.HealingStreamTotem:CastEx(Me) then
        return
    end

    -- Single Target Healing (continued)
    if lowest then
        local wave_pct = PallasSettings.RestoShamanHealingWave or 80
        local riptide_pct = PallasSettings.RestoShamanRiptide or 90

        if lowest.HealthPct < wave_pct and Spell.HealingWave:CastEx(lowest) then
            return
        end

        if lowest.HealthPct < riptide_pct and Spell.Riptide:CastEx(lowest) then
            return
        end
    end

    -- Utility
    local es_choice = PallasSettings.RestoShamanEarthShieldTarget or 0
    if es_choice ~= 2 then                             -- not "Off"
        local tank = Heal.Friends.Tanks[es_choice + 1] -- 0=Tank1, 1=Tank2
        if tank and not tank:HasAura("Earth Shield") and Spell.EarthShield:CastEx(tank) then
            return
        end
    end

    if PallasSettings.RestoShamanPurifySpirit ~= false then
        if Spell.PurifySpirit:Dispel(true, { DispelType.Magic, DispelType.Curse }) then
            return
        end
    end

    -- Resurrect current target if dead
    local myTarget = Me.Target
    if myTarget and myTarget.IsDead and myTarget.isPlayer and Spell.AncestralSpirit:CastEx(myTarget) then
        return
    end

    -- Damage (only when healing is comfortable)
    local dps_above_hp = PallasSettings.RestoShamanDPSAboveHP or 80
    if lowest and (lowest.HealthPct < dps_above_hp or Me.PowerPct < 60) then
        return
    end

    -- Weapon imbue
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

    -- Shield buff
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

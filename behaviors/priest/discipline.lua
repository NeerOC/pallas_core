local options = {
    Name = "Priest (Discipline)", -- shown as collapsing header

    Widgets = {
        { type = "header",   text = "General" },
        { type = "slider",   uid = "DiscDPSAboveHP",        text = "DPS Above Health %",           default = 90,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscDPSManaFloor",      text = "DPS Mana Floor %",             default = 30,  min = 0,                                                max = 100 },

        { type = "header",   text = "Single Target Healing" },
        { type = "slider",   uid = "DiscPenanceHP",         text = "Penance %",                    default = 60,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscFlashHealHP",       text = "Flash Heal %",                 default = 50,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscGreaterHealHP",     text = "Greater Heal %",               default = 45,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscHealHP",            text = "Heal %",                       default = 75,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscBindingHealHP",     text = "Binding Heal %",               default = 40,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscBindingHealSelfHP", text = "Binding Heal Self %",          default = 70,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscRenewHP",           text = "Renew (moving only) %",        default = 50,  min = 0,                                                max = 100 },

        { type = "header",   text = "Shielding" },
        { type = "checkbox", uid = "DiscPWSOnTargeted",     text = "PW:S allies being targeted",   default = true },
        { type = "checkbox", uid = "DiscPWSTank",           text = "PW:S tanks always",            default = true },
        { type = "slider",   uid = "DiscPWSHP",             text = "PW:S Below Health %",          default = 75,  min = 0,                                                max = 100 },

        { type = "header",   text = "AoE Healing" },
        { type = "slider",   uid = "DiscPoHCount",          text = "Prayer of Healing - Members",  default = 3,   min = 1,                                                max = 5 },
        { type = "slider",   uid = "DiscPoHHP",             text = "Prayer of Healing - Health %", default = 75,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscPoMHP",             text = "Prayer of Mending - Health %", default = 85,  min = 0,                                                max = 100 },

        { type = "header",   text = "Cooldowns" },
        { type = "slider",   uid = "DiscPainSuppressionHP", text = "Pain Suppression %",           default = 25,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscDesperatePrayerHP", text = "Desperate Prayer %",           default = 35,  min = 0,                                                max = 100 },
        { type = "slider",   uid = "DiscVoidShiftHP",       text = "Void Shift target %",          default = 20,  min = 0,                                                max = 100 },
        { type = "checkbox", uid = "DiscUseSpiritShell",    text = "Use Spirit Shell",             default = true },
        { type = "checkbox", uid = "DiscUsePowerInfusion",  text = "Use Power Infusion",           default = true },
        { type = "checkbox", uid = "DiscUseShadowfiend",    text = "Use Shadowfiend/Mindbender",   default = true },

        { type = "header",   text = "Utility" },
        { type = "checkbox", uid = "DiscStopCasting",       text = "Cancel overheals",             default = true },
        { type = "checkbox", uid = "DiscPWFort",             text = "Power Word: Fortitude",        default = true },
        { type = "checkbox", uid = "DiscAngelicFeather",   text = "Angelic Feather",              default = true },
        { type = "slider",   uid = "DiscFeatherDelay",     text = "Feather after moving (sec)",   default = 2,   min = 0,                                                max = 10 },
        { type = "combobox", uid = "DiscInnerBuff",         text = "Inner Buff",                   default = 0,   options = { "Inner Fire", "Inner Will", "Auto (mana)" } },
    },
}

local auras = {
    evangelism           = 81661,
    spirit_shell         = 109964,
    spirit_shell_absorb  = 114908,  -- Spirit Shell (absorb)
    power_word_fortitude = 21562,
    from_darkness        = 114255,  -- From Darkness, Comes Light (free Flash Heal)
    weakened_soul        = 6788,
    prayer_of_mending    = 41635,
    inner_fire           = 588,
    inner_will           = 73413,
    inner_focus          = 89485,
    angelic_feather      = 121557,
    altered_form         = 97709,
}

local SPIRIT_SHELL_KEY = 550 -- ImGuiKey E
local spirit_shell_queued = false
local spirit_shell_key_down = false
local moving_since = 0

-- Find the friend unit we're currently casting on
local function get_cast_target()
    local lo = Me.CastTargetLo
    if not lo or lo == 0 then return nil end
    for _, f in ipairs(Heal.Friends and Heal.Friends.All or {}) do
        if f.guid_lo == lo then return f end
    end
    return nil
end

local function DoRotation()
    -- Spirit Shell keybind: debounced toggle
    local key_now = imgui.is_key_pressed(SPIRIT_SHELL_KEY)
    if key_now and not spirit_shell_key_down then
        spirit_shell_queued = not spirit_shell_queued
        print("[Pallas] Spirit Shell " .. (spirit_shell_queued and "QUEUED" or "CANCELLED"))
    end
    spirit_shell_key_down = key_now

    if Me.IsMounted then return end
    if Me:IsDisabled() then return end

    local lowest = Heal:GetLowestMember()

    -- ── Stop Casting: cancel heals on targets that recovered ─────────
    if PallasSettings.DiscStopCasting ~= false and Me:IsCastingOrChanneling() then
        -- Don't cancel during Spirit Shell (absorbs are never wasted)
        if not Me:HasAura(auras.spirit_shell) then
            local ct = get_cast_target()
            if ct then
                local spell_id = Me.CastingSpellId
                if spell_id == Spell.Heal.Id and ct.HealthPct > 95 then
                    Me:StopCasting()
                elseif spell_id == Spell.GreaterHeal.Id and ct.HealthPct > 90 then
                    Me:StopCasting()
                elseif spell_id == Spell.FlashHeal.Id and ct.HealthPct > 92 then
                    Me:StopCasting()
                elseif spell_id == Spell.PrayerOfHealing.Id then
                    local poh_hp = PallasSettings.DiscPoHHP or 75
                    local poh_count = PallasSettings.DiscPoHCount or 3
                    local _, below = Heal:GetMembersBelow(poh_hp)
                    if below < poh_count and ct.HealthPct > 90 then
                        Me:StopCasting()
                    end
                end
            end
        end
    end

    -- Track movement duration
    local now = game.game_time()
    if Me:IsMoving() then
        if moving_since == 0 then moving_since = now end
    else
        moving_since = 0
    end

    if Me:IsCastingOrChanneling() then
        return
    end

    -- ── Off-GCD abilities ────────────────────────────────────────────

    -- Angelic Feather: speed boost after moving for X seconds
    if PallasSettings.DiscAngelicFeather ~= false and Me:IsMoving()
        and not Me:HasAura(auras.angelic_feather)
        and moving_since > 0 and (now - moving_since) >= (PallasSettings.DiscFeatherDelay or 2) then
        Spell.AngelicFeather:CastAtPos(Me)
    end

    -- Fade: drop threat if any mob is targeting us
    for _, e in ipairs(Combat.Targets or {}) do
        local tgt = e:GetTarget()
        if tgt and tgt.Guid == Me.Guid then
            Spell.Fade:CastEx(Me)
            break
        end
    end

    if Spell:IsGCDActive() then
        return
    end

    -- ── Emergency cooldowns ──────────────────────────────────────────

    -- Desperate Prayer: self emergency
    local dp_pct = PallasSettings.DiscDesperatePrayerHP or 35
    if Me.HealthPct < dp_pct and Spell.DesperatePrayer:CastEx(Me) then
        return
    end

    -- Pain Suppression: emergency single target
    if lowest then
        local ps_pct = PallasSettings.DiscPainSuppressionHP or 25
        if lowest.HealthPct < ps_pct and Spell.PainSuppression:CastEx(lowest) then
            return
        end
    end

    -- Void Shift: swap HP with critically low ally (self must be healthy)
    if lowest then
        local vs_pct = PallasSettings.DiscVoidShiftHP or 20
        if lowest.HealthPct < vs_pct and Me.HealthPct > 90
            and lowest.Guid ~= Me.Guid
            and Spell.VoidShift:CastEx(lowest) then
            return
        end
    end

    -- From Darkness Comes Light: free instant Flash Heal proc
    if lowest and Me:HasAura(auras.from_darkness) and Spell.FlashHeal:CastEx(lowest, { skipFacing = true }) then
        return
    end

    -- ── Spirit Shell window ──────────────────────────────────────────
    if PallasSettings.DiscUseSpiritShell ~= false then
        local ss_aura = Me:GetAura(auras.spirit_shell)
        if ss_aura then
            local now = game.game_time()
            local remaining = (ss_aura.expire_time or 0) - now
            local _, poh_info = pcall(game.get_spell_info, Spell.PrayerOfHealing.Id)
            local poh_cast_sec = ((poh_info and poh_info.cast_time) or 2500) / 1000
            if remaining > poh_cast_sec then
                -- Target members who don't already have Spirit Shell absorb
                local all_friends = Heal.Friends and Heal.Friends.All or {}
                for _, f in ipairs(all_friends) do
                    if not f:HasAura(auras.spirit_shell_absorb) then
                        if Spell.PrayerOfHealing:CastEx(f, { skipFacing = true }) then
                            return
                        end
                    end
                end
                -- Fallback: cast on anyone if all have absorbs
                if #all_friends > 0 then
                    if Spell.PrayerOfHealing:CastEx(all_friends[1], { skipFacing = true }) then
                        return
                    end
                end
            end
        end
    end

    -- ── PW:Shield on tanks always ────────────────────────────────────
    if PallasSettings.DiscPWSTank ~= false then
        local tanks = Heal.Friends and Heal.Friends.Tanks or {}
        for _, tank in ipairs(tanks) do
            if not tank:HasAura("Power Word: Shield")
                and not tank:HasAura(auras.weakened_soul) then
                if Spell.PowerWordShield:CastEx(tank) then
                    return
                end
            end
        end
    end

    -- PW:Shield on allies being targeted by mobs
    if PallasSettings.DiscPWSOnTargeted ~= false then
        local pws_hp = PallasSettings.DiscPWSHP or 90
        local friend_set = {}
        for _, ally in ipairs(Heal.Friends.All) do
            friend_set[ally.Guid] = ally
        end
        for _, enemy in ipairs(Combat.Targets or {}) do
            local tgt = enemy:GetTarget()
            if tgt then
                local ally = friend_set[tgt.Guid]
                if ally and ally.HealthPct < pws_hp
                    and not ally:HasAura("Power Word: Shield")
                    and not ally:HasAura(auras.weakened_soul) then
                    if Spell.PowerWordShield:CastEx(ally) then
                        return
                    end
                end
            end
        end
    end

    -- ── Single Target Healing ────────────────────────────────────────
    if lowest then
        -- Penance (heal)
        local penance_pct = PallasSettings.DiscPenanceHP or 60
        if lowest.HealthPct < penance_pct and Spell.Penance:CastEx(lowest, { skipMoving = true }) then
            return
        end

        -- Inner Focus + Greater Heal combo (save Inner Focus for the big heal)
        local gheal_pct = PallasSettings.DiscGreaterHealHP or 45
        if lowest.HealthPct < gheal_pct then
            if not Me:HasAura(auras.inner_focus) and Spell.InnerFocus:CastEx(Me) then
                return
            end
            if Spell.GreaterHeal:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end

        -- Flash Heal (expensive, no Inner Focus — use only for urgent healing)
        local flash_pct = PallasSettings.DiscFlashHealHP or 50
        if lowest.HealthPct < flash_pct then
            if Spell.FlashHeal:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── Binding Heal ─────────────────────────────────────────────────
    if lowest and lowest.Guid ~= Me.Guid then
        local bh_pct = PallasSettings.DiscBindingHealHP or 40
        local bh_self = PallasSettings.DiscBindingHealSelfHP or 70
        if lowest.HealthPct < bh_pct and Me.HealthPct < bh_self then
            if Spell.BindingHeal:CastEx(lowest, { skipFacing = true }) then
                return
            end
        end
    end

    -- ── AoE Healing ──────────────────────────────────────────────────
    local poh_hp = PallasSettings.DiscPoHHP or 75
    local poh_count = PallasSettings.DiscPoHCount or 3
    local members_below_poh, _ = Heal:GetMembersBelow(poh_hp)
    if #members_below_poh >= poh_count then
        if Spell.PrayerOfHealing:CastEx(members_below_poh[1], { skipFacing = true }) then
            return
        end
    end

    -- Prayer of Mending: only if no friend already has it
    if lowest then
        local pom_hp = PallasSettings.DiscPoMHP or 85
        if lowest.HealthPct < pom_hp then
            local pom_exists = false
            for _, f in ipairs(Heal.Friends and Heal.Friends.All or {}) do
                if f:HasAura(auras.prayer_of_mending) then
                    pom_exists = true
                    break
                end
            end
            if not pom_exists and Spell.PrayerOfMending:CastEx(lowest) then
                return
            end
        end
    end

    -- ── Heal (light filler) ──────────────────────────────────────────
    if lowest then
        local heal_pct = PallasSettings.DiscHealHP or 85
        if lowest.HealthPct < heal_pct and Spell.Heal:CastEx(lowest, { skipFacing = true }) then
            return
        end
    end

    -- ── Renew: movement-only instant filler ──────────────────────────
    if lowest and Me:IsMoving() then
        local renew_pct = PallasSettings.DiscRenewHP or 50
        if lowest.HealthPct < renew_pct and not lowest:HasAura("Renew") then
            if Spell.Renew:CastEx(lowest) then
                return
            end
        end
    end

    -- ── Purify ───────────────────────────────────────────────────────
    if Spell.Purify:Dispel(true, { DispelType.Magic, DispelType.Disease }) then
        return
    end

    -- Resurrect current target if dead
    local myTarget = Me.Target
    if myTarget and myTarget.IsDead and myTarget.IsPlayer and Spell.Resurrection:CastEx(myTarget) then
        return
    end

    -- ── Two Forms: revert Altered Form ────────────────────────────────
    if not Me.InCombat and Me:HasAura(auras.altered_form) and Spell.TwoForms:CastEx(Me) then
        return
    end

    -- ── Buffs (out of combat) ────────────────────────────────────────
    if not Me.InCombat and PallasSettings.DiscPWFort ~= false then
        for _, f in ipairs(Heal.Friends and Heal.Friends.All or {}) do
            if not f:HasAura(auras.power_word_fortitude) and Spell.PowerWordFortitude:CastEx(f) then
                return
            end
        end
    end

    -- ── Mana cooldowns (before DPS gate so they always fire) ──────────

    -- Shadowfiend / Mindbender for mana
    if PallasSettings.DiscUseShadowfiend ~= false and Me.PowerPct < 80 then
        local target = Combat.BestTarget
        if target then
            if Spell.Mindbender and Spell.Mindbender.IsKnown and Spell.Mindbender:CastEx(target) then
                return
            end
            if Spell.Shadowfiend:CastEx(target) then
                return
            end
        end
    end

    -- ── Damage / Atonement (only when healing is comfortable) ────────
    local dps_above_hp = PallasSettings.DiscDPSAboveHP or 90
    if lowest and (lowest.HealthPct < dps_above_hp) then
        return
    end

    -- Stop DPSing if mana is too low
    local mana_floor = PallasSettings.DiscDPSManaFloor or 30
    if Me.PowerPct < mana_floor then
        return
    end

    -- Inner buff maintenance (Auto mode: Inner Fire > 80% mana, Inner Will < 70%)
    local inner_choice = PallasSettings.DiscInnerBuff or 0
    if inner_choice == 0 then
        if not Me:HasAura(auras.inner_fire) and Spell.InnerFire:CastEx(Me) then
            return
        end
    elseif inner_choice == 1 then
        if not Me:HasAura(auras.inner_will) and Spell.InnerWill:CastEx(Me) then
            return
        end
    else -- Auto
        if Me.PowerPct > 80 and not Me:HasAura(auras.inner_fire) then
            if Spell.InnerFire:CastEx(Me) then return end
        elseif Me.PowerPct < 70 and not Me:HasAura(auras.inner_will) then
            if Spell.InnerWill:CastEx(Me) then return end
        end
    end

    -- Spirit Shell: activate when queued via keybind (E)
    if spirit_shell_queued and PallasSettings.DiscUseSpiritShell ~= false
        and not Me:HasAura(auras.spirit_shell) and Spell.SpiritShell:IsReady() then
        if Spell.InnerFocus:CastEx(Me) then
            return
        end
        if PallasSettings.DiscUsePowerInfusion ~= false and Spell.PowerInfusion:CastEx(Me) then
            return
        end
        if Spell.Archangel:CastEx(Me) then
            return
        end
        if Spell.SpiritShell:CastEx(Me) then
            spirit_shell_queued = false
            return
        end
    end

    -- Archangel: consume 5 Evangelism stacks for healing boost (outside Spirit Shell)
    if not Me:HasAura(auras.spirit_shell) and lowest then
        local evang_aura = Me:GetAura(auras.evangelism)
        local evang_stacks = evang_aura and evang_aura.stacks or 0
        if evang_stacks >= 5 and lowest.HealthPct < 70 and Spell.Archangel:CastEx(Me) then
            return
        end
    end

    local target = Combat.BestTarget
    if not target then
        return
    end

    -- Shadow Word: Death execute (< 20% HP)
    if target.HealthPct <= 20 and Spell.ShadowWordDeath:CastEx(target) then
        return
    end

    -- Atonement: Penance (offensive)
    if Spell.Penance:CastEx(target, { skipMoving = true }) then
        return
    end

    -- Power Word: Solace (talent) or Holy Fire
    if Spell.PowerWordSolace and Spell.PowerWordSolace.IsKnown then
        if Spell.PowerWordSolace:CastEx(target) then
            return
        end
    else
        if Spell.HolyFire:CastEx(target) then
            return
        end
    end

    -- Shadow Word: Pain maintenance
    if not target:HasAura("Shadow Word: Pain") and Spell.ShadowWordPain:CastEx(target) then
        return
    end

    -- Smite: filler (builds/maintains Evangelism stacks)
    if Spell.Smite:CastEx(target) then
        return
    end
end

local behaviors = {
    [BehaviorType.Heal] = DoRotation,
    [BehaviorType.Combat] = DoRotation,
}

return { Options = options, Behaviors = behaviors }

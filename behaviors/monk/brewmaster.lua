local options = {
    Name = "Monk (Brewmaster)",

    Widgets = {
        { type = "header",   text = "Mitigation" },
        { type = "slider",   uid = "BMGuardHP",            text = "Guard %",                    default = 70,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "BMFortifyingBrewHP",   text = "Fortifying Brew %",          default = 35,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "BMDampenHarmHP",       text = "Dampen Harm %",              default = 30,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "BMDiffuseMagicHP",     text = "Diffuse Magic %",            default = 30,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "BMElusiveBrewStacks",  text = "Elusive Brew Min Stacks",    default = 10,  min = 1,                                            max = 15 },

        { type = "header",   text = "Stagger" },
        { type = "checkbox", uid = "BMPurifyHeavy",        text = "Purify Heavy Stagger",       default = true },
        { type = "checkbox", uid = "BMPurifyModerate",     text = "Purify Moderate Stagger",    default = true },
        { type = "slider",   uid = "BMPurifyModerateHP",   text = "Moderate Purify Below HP %", default = 80,  min = 0,                                            max = 100 },

        { type = "header",   text = "Self Healing" },
        { type = "slider",   uid = "BMExpelHarmHP",        text = "Expel Harm %",               default = 85,  min = 0,                                            max = 100 },
        { type = "slider",   uid = "BMChiWaveHP",          text = "Chi Wave / Zen Sphere %",    default = 85,  min = 0,                                            max = 100 },

        { type = "header",   text = "AoE" },
        { type = "slider",   uid = "BMAoECount",           text = "AoE - Enemy Count",          default = 3,   min = 2,                                            max = 10 },
        { type = "checkbox", uid = "BMUseBreathOfFire",    text = "Use Breath of Fire",         default = true },

        { type = "header",   text = "Utility" },
        { type = "checkbox", uid = "BMUseLegacyOfEmperor", text = "Legacy of the Emperor",      default = true },
        { type = "combobox", uid = "BMTalentTier4",        text = "Tier 4 Talent",              default = 0,   options = { "Chi Wave", "Zen Sphere", "Chi Burst" } },
    },
}

local auras = {
    shuffle           = 115307,
    tiger_power       = 125359,
    elusive_brew_buff = 115308, -- active dodge buff
    elusive_brew_stk  = 128939, -- stacking buff (from crits)
    heavy_stagger     = 124273,
    moderate_stagger  = 124274,
    light_stagger     = 124275,
    power_guard       = 118636, -- Guard absorb buff
    fortifying_brew   = 120954,
    legacy_of_emperor = 117666,
    zen_sphere        = 124081,
}

local BLACK_OX_KEY = 541 -- ImGuiKey LeftCtrl

-- Get remaining seconds on an aura, 0 if missing
local function aura_remaining(unit, aura_id)
    local a = unit:GetAura(aura_id)
    if not a then return 0 end
    local remaining = (a.expire_time or 0) - game.game_time()
    return remaining > 0 and remaining or 0
end

local function DoCombat()
    if Me.IsMounted then return end
    if Me:IsDisabled() then return end

    -- ── Black Ox Statue: hold Left Ctrl to place at player position ──
    if imgui.is_key_pressed(BLACK_OX_KEY) and Spell.SummonBlackOxStatue then
        Spell.SummonBlackOxStatue:CastAtPos(Me)
    end

    if Me:IsCastingOrChanneling() then return end

    -- ── Off-GCD: Interrupt ──────────────────────────────────────────
    if Spell.SpearHandStrike:Interrupt() then
        return
    end

    -- ── Off-GCD: Elusive Brew (consume stacks for dodge) ────────────
    local eb_min = PallasSettings.BMElusiveBrewStacks or 10
    local eb_stacks_aura = Me:GetAura(auras.elusive_brew_stk)
    local eb_stacks = eb_stacks_aura and eb_stacks_aura.stacks or 0
    local eb_remaining = aura_remaining(Me, auras.elusive_brew_stk)
    -- Consume at threshold OR if stacks are about to expire
    if not Me:HasAura(auras.elusive_brew_buff) then
        if eb_stacks >= eb_min or (eb_stacks >= 2 and eb_remaining < 4) then
            if Spell.ElusiveBrew:CastEx(Me) then
                return
            end
        end
    end

    -- ── Off-GCD: Fortifying Brew (emergency) ────────────────────────
    local fb_pct = PallasSettings.BMFortifyingBrewHP or 35
    if Me.HealthPct < fb_pct and Spell.FortifyingBrew:CastEx(Me) then
        return
    end

    -- ── Off-GCD: Dampen Harm ────────────────────────────────────────
    local dh_pct = PallasSettings.BMDampenHarmHP or 30
    if Me.HealthPct < dh_pct and Spell.DampenHarm then
        if Spell.DampenHarm:CastEx(Me) then
            return
        end
    end

    -- ── Off-GCD: Diffuse Magic ──────────────────────────────────────
    local dm_pct = PallasSettings.BMDiffuseMagicHP or 30
    if Me.HealthPct < dm_pct and Spell.DiffuseMagic then
        if Spell.DiffuseMagic:CastEx(Me) then
            return
        end
    end

    if Spell:IsGCDActive() then
        return
    end

    local target = Combat.BestTarget
    if not target then return end

    if not Me:IsAutoAttacking() and Me:StartAttack(target) then
        return
    end

    local shuffle_remaining = aura_remaining(Me, auras.shuffle)
    local nearby_enemies = Combat:GetEnemiesWithinDistance(8)

    -- ── Purifying Brew: stagger management ──────────────────────────
    if PallasSettings.BMPurifyHeavy ~= false and Me:HasAura(auras.heavy_stagger) then
        if Spell.PurifyingBrew:CastEx(Me) then
            return
        end
    end

    if PallasSettings.BMPurifyModerate ~= false and Me:HasAura(auras.moderate_stagger) then
        local purify_hp = PallasSettings.BMPurifyModerateHP or 80
        if Me.HealthPct < purify_hp and shuffle_remaining >= 2 then
            if Spell.PurifyingBrew:CastEx(Me) then
                return
            end
        end
    end

    -- ── Guard: absorb shield ────────────────────────────────────────
    local guard_pct = PallasSettings.BMGuardHP or 70
    if Me.HealthPct < guard_pct and shuffle_remaining > 3 then
        if Spell.Guard:CastEx(Me) then
            return
        end
    end

    -- ── Shuffle maintenance: Blackout Kick ──────────────────────────
    if shuffle_remaining <= 2 and Spell.BlackoutKick:CastEx(target) then
        return
    end

    -- ── Chi generation: Keg Smash (highest priority, generates 2 Chi)
    if Spell.KegSmash:CastEx(target) then
        return
    end

    -- ── Expel Harm: Chi gen + self heal ─────────────────────────────
    local eh_pct = PallasSettings.BMExpelHarmHP or 85
    if Me.HealthPct < eh_pct and Spell.ExpelHarm:CastEx(Me) then
        return
    end

    -- ── Tiger Palm: maintain Tiger Power buff (free, no Chi cost) ───
    if not Me:HasAura(auras.tiger_power) and Spell.TigerPalm:CastEx(target) then
        return
    end

    -- ── Breath of Fire: only with Shuffle safety buffer ─────────────
    if PallasSettings.BMUseBreathOfFire ~= false and shuffle_remaining >= 3 then
        if Spell.BreathOfFire:CastEx(target) then
            return
        end
    end

    -- ── Tier 4 Talent: Chi Wave / Zen Sphere / Chi Burst ────────────
    local talent_choice = PallasSettings.BMTalentTier4 or 0
    local chi_heal_pct = PallasSettings.BMChiWaveHP or 85

    if talent_choice == 0 then
        if Me.HealthPct < chi_heal_pct and Spell.ChiWave:CastEx(target) then
            return
        end
    elseif talent_choice == 1 then
        if Me.HealthPct < chi_heal_pct and not Me:HasAura(auras.zen_sphere) then
            if Spell.ZenSphere:CastEx(Me) then
                return
            end
        end
    else
        if Spell.ChiBurst then
            if Spell.ChiBurst:CastEx(Me) then
                return
            end
        end
    end

    -- ── AoE: Spinning Crane Kick ──────────────────────────────────────
    local aoe_count = PallasSettings.BMAoECount or 3
    if nearby_enemies >= aoe_count and Spell.SpinningCraneKick:CastEx(Me) then
        return
    end

    -- ── Blackout Kick: dump excess Chi (Shuffle already healthy) ────
    if shuffle_remaining > 6 and Spell.BlackoutKick:CastEx(target) then
        return
    end

    -- ── Jab: Chi filler when Keg Smash on CD ───────────────────────
    if Spell.Jab:CastEx(target) then
        return
    end

    -- ── Tiger Palm: energy dump filler ──────────────────────────────
    if Spell.TigerPalm:CastEx(target) then
        return
    end

    -- ── Legacy of the Emperor (out of combat buff) ──────────────────
    if not Me.InCombat and PallasSettings.BMUseLegacyOfEmperor ~= false then
        local all_friends = Heal.Friends and Heal.Friends.All or {}
        for _, f in ipairs(all_friends) do
            if not f:HasAura(auras.legacy_of_emperor) and Spell.LegacyOfTheEmperor:CastEx(f, { skipFacing = true }) then
                return
            end
        end
    end
end

local behaviors = {
    [BehaviorType.Combat] = DoCombat,
}

return { Options = options, Behaviors = behaviors }

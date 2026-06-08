local PlayerConfig = {}

PlayerConfig.Default = {
    -- Gameplay scripts read only semantic names. Physical device mapping lives in C++
    -- Lua Input bindings: WASD/LeftStick -> Move, LMB/X -> Attack, Shift/RT -> Dash, Q/Y -> Ultimate.
    Input = {
        MoveAxis = "Move",
        LookAxis = "Look",
        JumpAction = "Jump",
        DashAction = "Dash",
        AttackAction = "Attack",
        UltimateAction = "Ultimate",
        SecondaryDashAction = "SecondaryDash",
    },

    Action = {
        DashDistance = 8.0,
        DashDuration = 0.15,
        DashCooldown = 0.5,
        -- Input buffer windows. Tune per animation feel.
        AttackInputBufferTime = 0.25,
        DashInputBufferTime = 0.20,
        ComboInputBufferTime = 0.30,
        DashChargingHoldThreshold = 0.4,
        DashChargingTurnSpeed = 12.0,
        DashChargingTargetTurnSpeed = 12.0,
        DashChargeDamage = {
            FullChargeTime = 1.25,
            MaxMultiplier = 2.0,
        },

        -- PGR Crimson Weave style follow-up: after a normal dash, basic attack
        -- enters a short sword-wave stance and alternates two diagonal slash motions.
        PostDashAttack = {
            Enabled = true,
            WindowDuration = 0.75,
            MaxAttacks = 3,
            VariantCount = 2,
            StepForwardDistances = {
                0.5,
                0.5,
            },
            StepForwardDurations = {
                0.12,
                0.12,
            },
            SpawnFlyingSlashOnAttackStart = false,
        },

        AttackStepForwardDistance = 1.5,
        AttackStepForwardDuration = 0.12,
        -- Keep normal/basic attack step-forward from tunneling into the target origin.
        -- DashChargeAttack intentionally bypasses this so it can still pierce through.
        AttackStepForwardControl = {
            Enabled = true,
            MinDistance = 3.6,
            ScaleStartDistance = 7.0,
            ForwardDotMin = 0.15,
            PushoutEnabled = true,
            PushoutDistance = 3.6,
            PushoutStrength = 0.35,
            MaxPushoutPerFrame = 0.45,
        },
        AttackStepForwardDistances = {
            3,
            3,
            3,
            3,
            5,
            3,
            7,
        },
        AttackStepForwardDurations = {
            0.12,
            0.12,
            0.12,
            0.12,
            0.12,
            0.12,
            0.12,
        },
        DashChargeAttackStepForwardDistance = 10.0,
        DashChargeAttackStepForwardDuration = 0.12,
        AttackTurnSpeed = 12.0,
        HitKnockbackDistance = 2.5,
        HitKnockbackDuration = 0.16,

        FlyingSlash = {
            Speed = 90.0,
            Life = 1,
            MaxDistance = 90.0,
            Radius = 10,
            SpawnForwardOffset = 2.0,
            SpawnRightOffset = 0.0,
            SpawnUpOffset = 1.2,
            Scale = Vector(1.0, 1.0, 1.0),
            Pierce = true,
            FlattenDirection = true,
            Debug = false,
        },
    },

    -- Attack-time soft lock-on.
    -- Attack: only yaw assist. Dash/DashChargeAttack: lock the initial dash
    -- direction to the target and keep moving straight through the target.
    Targeting = {
        Enabled = true,
        TargetTags = {
            "HitTarget",
            "Enemy",
            "Boss",
        },
        StickyTime = 0.45,
        StickyScoreBonus = 0.15,

        Attack = {
            Enabled = true,
            Range = 50.0,
            ConeDeg = 360.0,
            TurnDuration = 0.08,
            TurnSpeed = 54.0,
            LockDirection = false,
        },

        Dash = {
            -- 이건 끄고 사용자 의도를 중시하는게 나을듯
            Enabled = false,
            Range = 8.5,
            ConeDeg = 120.0,
            TurnDuration = 0.06,
            TurnSpeed = 36.0,
            LockDirection = true,
        },

        DashChargeAttack = {
            Enabled = true,
            Range = 50.0,
            ConeDeg = 360.0,
            TurnDuration = 0.08,
            TurnSpeed = 36.0,
            LockDirection = true,
        },

        Ultimate = {
            Enabled = true,
            Range = 120.0,
            ConeDeg = 360.0,
            TurnDuration = 0.0,
            TurnSpeed = 999.0,
            LockDirection = true,
        },
    },

    Combat = {
        MaxHP = 100,
        MaxUltimateGauge = 100,

        -- Player -> Enemy damage. AttackIndex 1~7 uses AttackDamages.
        AttackDamage = 10,
        AttackDamages = {
            8,
            10,
            12,
            14,
            18,
            20,
            24,
        },
        DashChargeAttackDamage = 30,
        FlyingSlashDamage = 20,
        FlyingSlashGaugeDelta = 8,
        FlyingSlashHitStopDuration = 0.03,
        UltimateDamage = 100,
        UltimateRange = 42.0,
        UltimateHitStopDuration = 0.08,
        UltimateDuplicateHitLifetime = 1.2,

        -- Multi-hit policy for AttackHitWindow.
        -- C++ notify-state Hit Count/Interval are edit-only hot overrides; keep
        -- persistent defaults here to avoid changing existing AnimSequence binary payloads.
        AttackHitCounts = {
            2,
            3,
            2,
            3,
            4,
            5,
            3,
        },
        AttackHitIntervals = {
            0.06,
            0.06,
            0.06,
            0.06,
            0.06,
            0.06,
            0.06,
        },
        DashChargeAttackHitCount = 1,
        DashChargeAttackHitInterval = 0.06,
        UltimateHitCount = 1,
        UltimateHitInterval = 0.06,

        -- Gauge/anti-duplicate policy.
        AttackHitGaugeDelta = 10,
        AttackGaugeGain = 10,
        AttackComboGain = 1,
        DashChargeAttackGaugeDelta = 15,
        PerfectDodgeGaugeDelta = 20,
        DuplicateHitLifetime = 1.0,

        -- Player defense / perfect dodge.
        HitInvincibleDuration = 0.5,
        DashPerfectDodgeDuration = 0.2,
        PerfectDodgeGraceAfterDash = 0.05,
        PerfectDodgeSlomoDuration = 5.0,
        PerfectDodgeSlomoScale = 0.1,
        -- World is slowed by SlomoScale. PlayerSpeedScale is the player's final speed
        -- relative to real/raw time while TimeRush is active. 1.0 = normal, 1.2 = 20% faster.
        PerfectDodgePlayerSpeedScale = 1.5,
        -- Extra AI/cooldown scale on top of global slomo. Keep 1.0 to avoid double slomo.
        PerfectDodgeEnemyBrainScale = 1.0,

        -- Lua-triggered hit feedback. Player attack hitstop is still primarily
        -- driven by AnimNotifyState_AttackHitWindow, but these values are used
        -- by boss->player hits and non-notify based hit windows.
        HitStopDuration = 0.05,
        EnemyHitStopDuration = 0.04,
    },

    Feedback = {
        KatanaMeshPath = "Content/Mesh/Katana/source/red cyber katana_StaticMesh.uasset",
        KatanaSocketName = "WeaponR",
        TrailParticlePath = "Content/Data/SwordTrail2.uasset",

        DashCharge = {
            CameraShakeEnabled = true,
            CameraShakeInterval = 0.16,
            CameraShakeMinScale = 0.08,
            CameraShakeMaxScale = 0.16,

            -- 플레이어 주변에 생긴 입자가 중앙으로 빨려 들어오는 레이어.
            -- ParticlePath는 프로젝트에 맞는 sprite/mesh particle system으로 교체하면 된다.
            InwardParticlePath = "Content/Data/PS_DashChargeInward.uasset",
            InwardMaterialPath = "None",
            InwardSpawnInterval = 0.055,
            InwardMinRadius = 2.2,
            InwardMaxRadius = 4.8,
            InwardHeight = 0.75,
            InwardTargetHeight = 1.05,
            InwardLife = 0.32,
            InwardMinScale = 0.35,
            InwardMaxScale = 1.15,

            -- 차징 시작/완료 상태를 읽기 쉽게 해주는 지속형 링/완료 버스트.
            GroundRingPath = "Content/Data/PS_DashChargeGroundRing.uasset",
            GroundRingMaterialPath = "None",
            GroundRingScale = 1.25,
            ReadyBurstPath = "Content/Data/PS_DashChargeReadyBurst.uasset",
            ReadyBurstMaterialPath = "None",
            ReadyBurstScale = 1.6,
        },

        FlyingSlash = {
            ParticlePath = "Content/Data/PS_FlyingSlashMesh.uasset",
            MaterialPath = "Content/Material/VFX/M_SwordTrail_Color.mat",
            AutoDestroyDelay = 0.8,
        },

        PerfectDodge = {
            CameraShakeScale = 0.5,
            PostProcessIntensity = 1.0,
            FocusHighlightStrength = 1.25,
        },

        AttackHit = {
            CameraShakeScale = 0.25,
            Sound = {
                Enabled = true,
                Key = "PlayerAttackHit",
                Path = "Player Whoosh/whoosh_swish_high_fast_01.wav",
                Volume = 1.0,
                Pitch = 1.0,
            },
        },

        DamageText = {
            Enabled = true,
            FontName = "Default",
            FontSize = 2.0,
            Duration = 0.65,
            ZOffset = 0,
            HitLocationZOffset = 1.0,
            RiseDistance = 3,
            HorizontalJitter = 1.0,
            DriftDistance = 0.25,
            Color = { R = 1.0, G = 0.78, B = 0.10, A = 1.0  },
        },

        -- Screen-edge vignette feedback. These are named camera-manager layers, so low HP,
        -- hit flash, dash, and ultimate pulses can overlap without overwriting each other.
        Vignette = {
            Enabled = true,

            LowHP = {
                Enabled = true,
                StartRatio = 0.45,
                CriticalRatio = 0.18,
                MinIntensity = 0.08,
                MaxIntensity = 0.62,
                Radius = 0.66,
                Softness = 0.42,
                BlendOut = 0.35,
                R = 0.62,
                G = 0.0,
                B = 0.0,
                A = 1.0,
            },

            HitReact = {
                Intensity = 0.62,
                Radius = 0.56,
                Softness = 0.38,
                Duration = 0.44,
                BlendIn = 0.02,
                BlendOut = 0.34,
                R = 0.85,
                G = 0.02,
                B = 0.0,
                A = 1.0,
            },

            Dash = {
                Intensity = 0.18,
                Radius = 0.9,
                Softness = 0.36,
                BlendOut = 0.18,
                R = 0.18,
                G = 0.02,
                B = 0.02,
                A = 1.0,
            },

            DashCharging = {
                Intensity = 0.25,
                Radius = 0.68,
                Softness = 0.38,
                BlendOut = 0.20,
                R = 0.02,
                G = 0.10,
                B = 0.20,
                A = 1.0,
            },

            DashChargeAttack = {
                Intensity = 0.0,
                Radius = 0.62,
                Softness = 0.36,
                BlendOut = 0.24,
                R = 0.12,
                G = 0.02,
                B = 0.02,
                A = 1.0,
            },

            AttackHit = {
                Intensity = 0.10,
                Radius = 0.70,
                Softness = 0.36,
                Duration = 0.16,
                BlendIn = 0.01,
                BlendOut = 0.11,
                R = 0.18,
                G = 0.02,
                B = 0.02,
                A = 1.0,
            },

            PerfectDodge = {
                Intensity = 0.22,
                Radius = 0.68,
                Softness = 0.40,
                Duration = 0.62,
                BlendIn = 0.04,
                BlendOut = 0.46,
                R = 0.02,
                G = 0.18,
                B = 0.42,
                A = 1.0,
            },

            UltimateStart = {
                Intensity = 0.30,
                Radius = 0.66,
                Softness = 0.42,
                Duration = 0.55,
                BlendIn = 0.06,
                BlendOut = 0.36,
                R = 0.12,
                G = 0.0,
                B = 0.0,
                A = 1.0,
            },

            UltimateImpact = {
                Intensity = 0.52,
                Radius = 0.52,
                Softness = 0.34,
                Duration = 0.38,
                BlendIn = 0.015,
                BlendOut = 0.30,
                R = 0.70,
                G = 0.02,
                B = 0.0,
                A = 1.0,
            },

            UltimateRecover = {
                Intensity = 0.18,
                Radius = 0.72,
                Softness = 0.42,
                Duration = 0.50,
                BlendIn = 0.04,
                BlendOut = 0.34,
                R = 0.02,
                G = 0.02,
                B = 0.02,
                A = 1.0,
            },

            Death = {
                Intensity = 0.80,
                Radius = 0.50,
                Softness = 0.45,
                Duration = 1.25,
                BlendIn = 0.04,
                BlendOut = 0.90,
                R = 0.75,
                G = 0.0,
                B = 0.0,
                A = 1.0,
            },
        },

        -- Transient FOV pulses. DeltaDegrees > 0 widens the view; < 0 pulls in.
        -- These are camera-manager modifiers, so the active camera component's base FOV is not overwritten.
        FOV = {
            Enabled = true,
            Dash = {
                DeltaDegrees = 5.0,
                Duration = 0.80,
                BlendIn = 0.2,
                BlendOut = 0.28,
            },

            DashCharging = {
                DeltaDegrees = 0.0,
                Duration = 30.0,
                BlendIn = 0.10,
                BlendOut = 0.22,
            },

            DashChargeAttack = {
                DeltaDegrees = 0.0,
                Duration = 0.50,
                BlendIn = 0.04,
                BlendOut = 0.34,
            },

            AttackStart = {
                DeltaDegrees = 0,
                Duration = 0.24,
                BlendIn = 0.03,
                BlendOut = 0.17,
            },

            PostDashAttack = {
                DeltaDegrees = 0.0,
                Duration = 0.38,
                BlendIn = 0.04,
                BlendOut = 0.28,
            },

            AttackHit = {
                DeltaDegrees = 0,
                Duration = 0.20,
                BlendIn = 0.02,
                BlendOut = 0.15,
            },

            HitReact = {
                DeltaDegrees = 0,
                Duration = 0.24,
                BlendIn = 0.02,
                BlendOut = 0.18,
            },

            PerfectDodge = {
                DeltaDegrees = 0,
                Duration = 0.70,
                BlendIn = 0.06,
                BlendOut = 0.45,
            },

            UltimateStart = {
                DeltaDegrees = 0,
                Duration = 0.65,
                BlendIn = 0.08,
                BlendOut = 0.42,
            },

            UltimateImpact = {
                DeltaDegrees = 0,
                Duration = 0.48,
                BlendIn = 0.03,
                BlendOut = 0.34,
            },

            UltimateRecover = {
                DeltaDegrees = 0,
                Duration = 0.50,
                BlendIn = 0.04,
                BlendOut = 0.34,
            },
        },

        HitReact = {
            CameraShakeScale = 0.35,
            SquashEnabled = true,
            SquashScale = Vector(1.06, 1.06, 0.94),
            SquashInDuration = 0.035,
            SquashRecoverDuration = 0.09,
            ShakeEnabled = true,
            ShakeAmplitude = 3.0,
            ShakeDuration = 0.08,
            ShakeFrequency = 70.0,
        },

        UltimateCamera = {
            BackDistance = 50.0,
            Height = 13.0,
            SlashCameraDistance = 30.0,
            SlashCameraRightOffset = 15,
            SlashCameraHeightOffset = -5.0,
            PitchSwing = 0.0,
            YawSwing = 0.0,
            RollSwing = 2.0,
            RotationStart = 0.5,
        },

        UltimateVfx = {
            SlashSubUVResource = "SlashTexture",
            SlashFrameRate = 15.0,
            SlashFlashPath = "Content/Data/DirectionalBeam.uasset",
            LightningMaterialPath = "Content/Material/VFX/M_Lightning.mat",
            GroundCrackMaterialPath = "Content/Material/VFX/M_GroundCrack.mat",
        },

        UltimateMove = {
            StartDistance = 100.0,
            EndDistance = 10,
            SideOffset = -10.0,
            ControlSideOffset = 40.0,
            Duration = 0.55,
            FrameStep = 1.0 / 60.0,
            EndRightDistance = 5,
            SlomoDuration = 0.65,
            SlomoScale = 0.7,
            AttackStartDelay = 0.08,
            AttackDamageDelay = 0.10,
            AttackDuration = 0.95,
            RecoverHold = 0.15,
        },
    },

    Animation = {
        Samurai = {
            IdlePath = "Content/Animation/Samurai_Player/SamuraiIdle.uasset",
            WalkPath = "Content/Animation/Samurai_Player/SamuraiWalk.uasset",
            RunPath = "Content/Animation/Samurai_Player/SamuraiSprint.uasset",
            JumpPath = "Content/Animation/Samurai_Player/SamuraiJump.uasset",

            AttackPaths = {
                "Content/Animation/Samurai_Player_Advanced/Combo1.uasset",
                "Content/Animation/Samurai_Player_Advanced/Combo2.uasset",
                "Content/Animation/Samurai_Player_Advanced/Combo3.uasset",
                "Content/Animation/Samurai_Player_Advanced/Combo4.uasset",
                "Content/Animation/Samurai_Player_Advanced/Combo5.uasset",
                "Content/Animation/Samurai_Player/SamuraiAttack3.uasset",
                "Content/Animation/Samurai_Player_Advanced/Combo7.uasset",
            },

            -- Temporary placeholders for the two alternating post-dash diagonal slash
            -- motions. Replace these two paths once the dedicated animations exist.
            PostDashAttackPaths = {
                "Content/Animation/Samurai_Player/SamuraiSlashAttack1.uasset",
                "Content/Animation/Samurai_Player/SamuraiSlashAttack2.uasset",
            },

            DashPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1_Start2.uasset",
            DashChargingPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1_Start2.uasset",
            DashChargeAttackPath = "Content/Animation/Samurai_Player/SamuraiAttackHeavy1.uasset",
            UltimateAttackPath = "Content/Animation/Samurai_Player/SamuraiAttackUltimate.uasset",
            HitReactPaths = {
                Front = "Content/Animation/Samurai_Player/SamuraiHitFront.uasset",
                Left = "Content/Animation/Samurai_Player/SamuraiHitLeft.uasset",
                Right = "Content/Animation/Samurai_Player/SamuraiHitRight.uasset",
                Back = "Content/Animation/Samurai_Player/SamuraiHitBack.uasset",
            },

            WalkThreshold = 0.1,
            RunThreshold = 8.0,
            RunSampleSpeed = 10.0,
            LocomotionSpeedResponse = 12.0,
            JumpLoop = false,

            AttackBlendIn = 0.08,
            AttackBlendOut = 0.15,
            AttackPlayRate = 1.5,
            AttackPlayRates = {
                3,
                2.5,
                3,
                2,
                2,
                2,
                2,
            },

            DashBlendIn = 0.05,
            DashBlendOut = 0.12,
            DashPlayRate = 3.0,
            DashChargingBlendIn = 0.05,
            DashChargingPlayRate = 1.0,
            DashChargingToAttackBlend = 0.03,
            DashChargeAttackBlendOut = 0.12,
            DashChargeAttackPlayRate = 1.4,
            DashChargeAttackFallbackDuration = 0.65,

            UltimateChargeBlendIn = 0.05,
            UltimateChargeBlendOut = 0.08,
            UltimateChargePlayRate = 1.3,
            UltimateAttackBlendIn = 0.05,
            UltimateAttackBlendOut = 0.12,
            UltimateAttackPlayRate = 1.2,

            HitReactBlendIn = 0.03,
            HitReactBlendOut = 0.10,
            HitReactPlayRate = 1.0,
            HitReactFallbackDuration = 0.45,

            JumpBlendIn = 0.1,
            JumpBlendOut = 0.2,
            JumpPlayRate = 1.0,
        }
    }
}

local function CloneTable(source)
    local result = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = CloneTable(value)
        else
            result[key] = value
        end
    end
    return result
end

function PlayerConfig.Create()
    return CloneTable(PlayerConfig.Default)
end

return PlayerConfig

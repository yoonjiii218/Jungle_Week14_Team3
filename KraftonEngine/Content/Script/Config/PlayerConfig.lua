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
        FlyingSlashHitStopDuration = 0.06,
        UltimateDamage = 40,
        UltimateRange = 42.0,
        UltimateHitStopDuration = 0.06,
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
            0.1,
            0.1,
            0.1,
            0.1,
            0.1,
            0.1,
            0.1,
        },
        DashChargeAttackHitCount = 1,
        DashChargeAttackHitInterval = 0.045,
        UltimateHitCount = 5,
        UltimateHitInterval = 0.1,

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
        PerfectDodgeSlomoDuration = 2.5,
        PerfectDodgeSlomoScale = 0.1,
        -- World is slowed by SlomoScale. PlayerSpeedScale is the player's final speed
        -- relative to real/raw time while TimeRush is active. 1.0 = normal, 1.2 = 20% faster.
        PerfectDodgePlayerSpeedScale = 1.5,
        -- Extra AI/cooldown scale on top of global slomo. Keep 1.0 to avoid double slomo.
        PerfectDodgeEnemyBrainScale = 1.0,

        -- Lua-triggered hit feedback. Player attack hitstop is now grouped per
        -- AttackHitWindow below; HitStopDuration remains the default/fallback value.
        HitStopDuration = 0.05,
        EnemyHitStopDuration = 0.04,

        -- 같은 HitIndex에 맞은 모든 대상을 한 박자로 묶는다. 따라서 N회 타격 x M마리여도
        -- 피격음은 최대 N번만 나며, 대상 수는 채널별 강도로 표현한다.
        ImpactGroup = {
            Enabled = true,
            GroupByHitIndex = true,
            -- 같은 HitIndex의 대상 판정이 여러 frame에 걸쳐 들어올 수 있어 잠깐 모은 뒤 배출한다.
            HitAggregationDelay = 0.1,
            MaxCountForScale = 5,
            -- Window end 이벤트를 못 받는 예외 상황을 위한 안전 flush.
            FallbackFlushDelay = 0.12,
            -- Projectile / Ultimate처럼 HitWindowSerial이 없는 공격은 같은 frame Drain 이후 즉시 묶어 처리.
            NoWindowFlushDelay = 0.0,

            AttackerHitStop = {
                Base = 0.0,
                PerTarget = 0.0,
                Max = 0.0,
                MinInterval = 0.06,
            },

            -- 궁극기는 카메라 컷신/슬로모/반복 데미지 자체가 이미 멈춤감을 만든다.
            -- 공격자 hitstop은 기본 비활성화하고, 최종 impact의 shake/sound/vignette로 묵직함을 표현한다.
            UltimateMaxCountForScale = 6,
            UltimateAttackerHitStop = {
                Enabled = false,
                Base = 0.0,
                PerTarget = 0.0,
                Max = 0.0,
                MinInterval = 0.20,
                FinalHitOnly = true,
            },
        },
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
            PostProcessIntensity = 0.45,
            FocusHighlightStrength = 1.25,
            Sound = {
                Enabled = true,
                Key = "PlayerPerfectDodge",
                Path = "PerfectDodge.mp3",
                Volume = 1.0,
                Pitch = 2.0,
            },
        },

        -- Per-target hit feedback. Heavy impact feedback is grouped below as AttackImpact.
        AttackHit = {
        },

        -- One feedback packet per AttackHitWindow / impact group. Multi-target hits scale
        -- different channels independently: hitstop slightly, shake more, VFX/sound most.
        AttackImpact = {
            Enabled = true,
            PulseFirstAndFinalOnly = true,
            CameraShake = {
                Base = 0.08,
                PerTarget = 0.025,
                Max = 0.16,
                SingleHitMultiplier = 1.40,
                FirstHitMultiplier = 1.15,
                MiddleHitMultiplier = 0.80,
                FinalHitMultiplier = 1.75,
            },
            VFX = {
                ParticlePath = "None",
                MaterialPath = "None",
                BaseScale = 1.0,
                PerTargetScale = 0.25,
                MaxScale = 2.0,
                Life = 0.45,
                ZOffset = 0.8,
            },
            Sound = {
                Enabled = true,
                Key = "PlayerAttackImpact",
                Path = "Hit Crash/WEAPSwrd_Sword_Hit_Crash_12.wav",
                MaxInstances = 3,
                MinInterval = 0.1,
                -- MinInterval이 최종 내부 판정에도 적용되도록 강제 재생을 끈다.
                AlwaysPlayFinalHit = false,
                BaseVolume = 0.68,
                PerTargetVolume = 0.08,
                MaxVolume = 0.95,
                SingleHitMultiplier = 1.15,
                FirstHitMultiplier = 1.0,
                MiddleHitMultiplier = 0.88,
                FinalHitMultiplier = 1.18,
                BasePitch = 1.02,
                PerTargetPitch = -0.015,
                SingleHitPitchOffset = -0.04,
                FirstHitPitchOffset = 0.0,
                MiddleHitPitchOffset = 0.03,
                FinalHitPitchOffset = -0.08,
                RandomPitchRange = 0.2,
                MinPitch = 0.80,
                MaxPitch = 1.20,
            },
        },

        -- 궁극기 직접 데미지 / 궁극기 HitWindow에서 발생한 AttackImpact 전용 채널.
        -- 반복 데미지 중간타는 개별 damage text로만 보이고, 큰 shake/sound/vignette는 최종 impact 한 번에 몰아준다.
        UltimateAttackImpact = {
            Enabled = true,
            FinalHitOnly = true,
            CameraShake = {
                Base = 0.0,
                PerTarget = 0.08,
                Max = 0.0,
            },
            VFX = {
                ParticlePath = "None",
                MaterialPath = "None",
                BaseScale = 1.35,
                PerTargetScale = 0.32,
                MaxScale = 2.7,
                Life = 0.55,
                ZOffset = 1.0,
            },
            Sound = {
                Enabled = true,
                Key = "PlayerUltimateAttackImpact",
                Path = "Hit Crash/WEAPSwrd_Sword_Hit_Crash_12.wav",
                MaxInstances = 3,
                MinInterval = 0.1,
                AlwaysPlayFinalHit = false,
                BaseVolume = 1.05,
                PerTargetVolume = 0.10,
                MaxVolume = 1.35,
                BasePitch = 0.94,
                PerTargetPitch = -0.018,
                RandomPitchRange = 0.12,
                MinPitch = 0.86,
                MaxPitch = 1.02,
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
                Radius = 0.9,
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

            AttackImpact = {
                Intensity = 0.12,
                Radius = 0.68,
                Softness = 0.34,
                Duration = 0.18,
                BlendIn = 0.01,
                BlendOut = 0.12,
                R = 0.20,
                G = 0.02,
                B = 0.02,
                A = 1.0,
            },

            UltimateAttackImpact = {
                Intensity = 0.22,
                Radius = 0.58,
                Softness = 0.32,
                Duration = 0.22,
                BlendIn = 0.01,
                BlendOut = 0.16,
                R = 0.42,
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

            AttackImpact = {
                DeltaDegrees = 0,
                Duration = 0.20,
                BlendIn = 0.02,
                BlendOut = 0.15,
            },

            UltimateAttackImpact = {
                DeltaDegrees = 0,
                Duration = 0.24,
                BlendIn = 0.02,
                BlendOut = 0.18,
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
            BackDistance = 70.0,
            Height = 20.0,
            SlashCameraDistance = 30.0,
            SlashCameraRightOffset = 15,
            SlashCameraHeightOffset = -5.0,
            PitchSwing = 0.0,
            YawSwing = 0.0,
            RollSwing = 2.0,
            RotationStart = 0.5,

            -- 궁극기 카메라가 한 위치에 오래 멈춰 있으면 hitstop 없이도 화면이 정지한 것처럼 보인다.
            -- 아래 drift는 컷씬/공격/회복 구간 동안 아주 약하게 dolly/orbit을 유지해 멈춤감을 줄인다.
            MotionEnabled = true,
            IntroHold = 0.12,
            IntroSideDrift = 3.0,
            IntroForwardDrift = 2.0,
            IntroHeightDrift = 0.8,
            IntroPitchDrift = 0.8,
            IntroYawDrift = 1.5,
            MoveSideDrift = 0.0,
            MoveForwardDrift = -4.0,
            MoveHeightDrift = 1.2,
            AttackSideDrift = 0.0,
            AttackForwardDrift = 6.0,
            AttackHeightDrift = 2.0,
            AttackPitchDrift = 1.2,
            AttackYawDrift = 4.0,
            RecoverSideDrift = 0.0,
            RecoverForwardDrift = 3.0,
            RecoverHeightDrift = 1.0,
            RecoverPitchDrift = 0.8,
            RecoverYawDrift = 1.5,
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
            Duration = 0.3,
            FrameStep = 1.0 / 60.0,
            EndRightDistance = 5,
            SlomoDuration = 0.3,
            SlomoScale = 0.6,
            AttackStartDelay = 0.08,
            AttackDamageDelay = 0,
            AttackDuration = 0.3,
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

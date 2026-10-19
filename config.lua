-- Conservative walking and spacing defaults; tune only after live map/rig checks.
return {
    Debug = false,
    AutoStart = false,
    PerceptionInterval = 0.2,
    DecisionInterval = 0.1,
    ReactionDelay = 0.15,
    Arena = { LobbyMinY = 300, LobbyMaxY = 400 },
    Portal = {
        Enabled = true, Path = { "Lobby", "Teleport1" },
        Clearance = 3, WaypointReach = 1.25, GroundProbe = 12,
        StuckTimeout = 3, PathTimeout = 5, EnterTimeout = 4, VerifyTimeout = 2,
        MaxAttempts = 3, RetryDelay = 1.5, FailureCooldown = 8,
    },
    Pursuit = {
        Enabled=true, TargetRadius=220, SelectInterval=.6, TargetHysteresis=.72,
        DesiredDistance=4, HoldMin=3.3, HoldMax=4.5,
        PredictionSeconds=.2, MaxPrediction=2.5,
        TargetReplanDistance=4, StaleTargetDistance=14, MinReplanInterval=.7,
        PlanTimeout=10, RetryDelay=1.2, UnreachableCooldown=5,
        WorkPerFrame=64, BudgetSeconds=.002,
        ScanRadius=190, ScanHeight=65, MaxParts=200, MaxNodes=2000,
        MaxAxisSamples=18, GridSpacing=4, LinkRadius=9, MaxNeighbors=24, MaxExpanded=1600,
        CacheSeconds=4, CacheDistance=25, MaxSegment=35,
        ProbeSpacing=.8, FootRadius=.28, BodyRadius=1, BodyHeight=3.5,
        StepHeight=1, MinNormalY=.7, MaxSlope=.8,
        LookAhead=2, CheckInterval=.08, WaypointReach=.65,
        MaxVerticalSpeed=12, StuckSeconds=2, AttachDistance=5,
    },
    Attack = { Enabled=true, ConservativeRange=4.5, Interval=.8 },
    PathPreview = { MaxSteps=48, Spacing=2, Interval=.1 },
    UI = { Width = 480, Height = 590 },
}


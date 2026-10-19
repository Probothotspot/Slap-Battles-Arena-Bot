-- Lobby portal walking is enabled; automatic combat is still disabled.
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
    UI = { Width = 360, Height = 370 },
}


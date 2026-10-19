local Gui = {}

function Gui.mount(context)
    local player = game:GetService("Players").LocalPlayer
    assert(player, "Client player is unavailable")
    local inputService = game:GetService("UserInputService")
    local cleanup = context.Cleanup
    local gui = Instance.new("ScreenGui")
    gui.Name = "SlapBattlesArenaBotGUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 100
    cleanup:add(gui)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(context.Config.UI.Width, context.Config.UI.Height)
    frame.Position = UDim2.new(0.5, -context.Config.UI.Width / 2, 0.3, 0)
    frame.BackgroundColor3 = Color3.fromRGB(29, 26, 42)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -64, 0, 44)
    title.Position = UDim2.fromOffset(14, 0)
    title.BackgroundTransparency = 1
    title.Text = "ARENA BOT  |  " .. context.Manifest.version
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Active = true
    title.Parent = frame

    local body = Instance.new("TextLabel")
    body.Name = "StateBody"
    body.Size = UDim2.new(1, -28, 1, -60)
    body.Position = UDim2.fromOffset(14, 50)
    body.BackgroundTransparency = 1
    body.Font = Enum.Font.Gotham
    body.TextSize = 14
    body.TextColor3 = Color3.fromRGB(220, 213, 240)
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.Text = "Подключение базы перчаток..."
    body.Parent = frame

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(32, 30)
    close.Position = UDim2.new(1, -40, 0, 7)
    close.BackgroundColor3 = Color3.fromRGB(105, 65, 180)
    close.Text = "X"
    close.TextColor3 = Color3.new(1, 1, 1)
    close.Parent = frame
    cleanup:add(close.Activated:Connect(function() context.App:Destroy() end))

    local activeInput, start, origin
    cleanup:add(title.InputBegan:Connect(function(input)
        if activeInput then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            activeInput, start, origin = input, input.Position, frame.Position
        end
    end))
    cleanup:add(inputService.InputChanged:Connect(function(input)
        if not activeInput then return end
        if activeInput.UserInputType == Enum.UserInputType.Touch then
            if input ~= activeInput then return end
        elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - start
        frame.Position = UDim2.new(origin.X.Scale, origin.X.Offset + delta.X,
            origin.Y.Scale, origin.Y.Offset + delta.Y)
    end))
    cleanup:add(inputService.InputEnded:Connect(function(input)
        if input == activeInput then activeInput = nil end
    end))
    cleanup:add(inputService.WindowFocusReleased:Connect(function() activeInput = nil end))
    cleanup:add(gui.Destroying:Connect(function() context.App:Destroy() end))
    gui.Parent = player:WaitForChild("PlayerGui")
    return gui
end

function Gui.update(gui, app)
    local body = gui:FindFirstChild("StateBody", true)
    if not body then return end
    local snapshot, glove, plan = app.Snapshot, app.Glove, app.Plan
    local states = { arena = "арена", lobby = "лобби", waiting = "ожидание" }
    body.Text = table.concat({
        "Состояние: " .. (states[snapshot.ArenaState] or "ожидание"),
        "Высота Y: " .. (snapshot.HeightY and string.format("%.2f", snapshot.HeightY) or "—"),
        "Портал: " .. (app.NavigationStatus and app.NavigationStatus.Message or "ожидание"),
        "Перчатка: " .. (snapshot.GloveName or (snapshot.AmbiguousTools and "выбери инструмент" or "нет")),
        "Профиль: " .. (glove and (glove.Known and glove.Policy or "базовый (новая перчатка)") or "—"),
        "Каталог: " .. app.CatalogStats.Total .. " записей; особых профилей: " .. app.CatalogStats.Specialized,
        "", glove and glove.Hint or "Ожидание инструмента в инвентаре или руке.",
        "", "План: " .. plan.Reason,
        "Вход в портал включён. Бой ещё не подключён.",
    }, "\n")
end

return Gui


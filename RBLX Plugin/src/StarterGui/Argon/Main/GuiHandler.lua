local StudioService = game:GetService('StudioService')
local TweenService = game:GetService('TweenService')
local RunService = game:GetService('RunService')

local HttpHandler = require(script.Parent.HttpHandler)
local FileHandler = require(script.Parent.FileHandler)
local Data = require(script.Parent.Data)

local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local SETTINGS_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local LOADING_TWEEN_INFO = TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)

local LIGHT_BLACK = Color3.fromRGB(50, 50, 50)
local LIGHT_WHITE = Color3.fromRGB(240, 240, 240)

local ROBLOX_BLACK = Color3.fromRGB(46, 46, 46)
local ROBLOX_WHITE = Color3.fromRGB(255, 255, 255)

local LOADING_ICON = 'rbxassetid://11234420895'
local START_ICON = 'rbxassetid://11272872815'

local AUTO_RECONNECT_DELAY = 3

local background = script.Parent.Parent.ArgonGui.Root.Background
local overlay = background.Overlay

local mainPage = background.Main
local settingsPage = background.Settings
local toolsPage = background.Tools

local versionLabel = mainPage.Header.Version
local inputFrame = mainPage.Body.Input
local previewFrame = mainPage.Body.Preview

local connectButton = mainPage.Body.Connect
local hostInput = inputFrame.Host
local portInput = inputFrame.Port
local settingsButton = mainPage.Body.Settings
local toolsButton = mainPage.Body.Tools

local infoLabel = previewFrame.Info
local loadingImage = connectButton.Loading
local actionLabel = connectButton.Action

local settingsBack = settingsPage.Header.Back
local toolsBack = toolsPage.Header.Back

local autoReconnectButton = settingsPage.Body.AutoReconnect.Button
local autoRunButton = settingsPage.Body.AutoRun.Button
local syncedDirectoriesButton = settingsPage.Body.SyncedDirectories.Button
local classFilteringButton = settingsPage.Body.ClassFiltering.Button

local syncedDirectoriesFrame = settingsPage.SyncedDirectories
local classFilteringFrame = settingsPage.ClassFiltering

local portToVSButton = toolsPage.Body.PortToVS.Button
local portToRobloxButton = toolsPage.Body.PortToRoblox.Button

local plugin = nil
local connections = {}
local subConnections = {}
local themeConnection = nil
local expandedSetting = nil
local lastTheme = 'Dark'
local isPorting = false
local debounce = false
local stopped = false
local state = 0
local connect

local guiHandler = {}

local function fail(response)
    actionLabel.Text = 'PROCEED'
    infoLabel.Text = response
    state = 2
    debounce = false
    stopped = false

    if Data.autoReconnect then
        task.wait(AUTO_RECONNECT_DELAY)

        if not stopped then
            state = 0
            connect()
        end
    end
end

function connect()
    if not debounce then
        debounce = true

        if state == 0 then
            infoLabel.Text = 'Connecting...'
            inputFrame.Visible = false
            previewFrame.Visible = true
            actionLabel.Visible = false
            loadingImage.Visible = true

            local tween = TweenService:Create(loadingImage, LOADING_TWEEN_INFO, {Rotation = -360})
            tween:Play()

            local success, response = HttpHandler.connect(fail)

            actionLabel.Visible = true
            loadingImage.Visible = false
            loadingImage.Rotation = 0
            tween:Cancel()

            if success then
                actionLabel.Text = 'STOP'
                infoLabel.Text = Data.host..':'..Data.port
                state = 1
            else
                fail(response)
            end
        else
            if state == 1 then
                HttpHandler.stop()
            end

            stopped = true
            actionLabel.Text = 'CONNECT'
            infoLabel.Text = 'Connecting...'
            inputFrame.Visible = true
            previewFrame.Visible = false
            state = 0
        end

        debounce = false
    end
end

local function filterInput(input)
    if input == 0 then
        hostInput.Text = hostInput.Text:gsub('[^%a]', '')
    elseif input == 1 then
        portInput.Text = portInput.Text:gsub('[^%d]', '')

        if #portInput.Text > 5 then
            portInput.Text = portInput.Text:sub(0, -2)
        end
    else
        classFilteringFrame.Input.Text = classFilteringFrame.Input.Text:gsub('[^%a%, ]', '')
    end
end

local function setAddress(input, isHost)
    if isHost then
        Data.host = input.Text

        if Data.host == '' then
            Data.host = 'localhost'
        end

        plugin:SetSetting('Host', Data.host)
    else
        Data.port = input.Text

        if Data.port == '' then
            Data.port =  '8000'
        end

        plugin:SetSetting('Port', Data.port)
    end
end

local function changePage(position, page1, page2)
    if not expandedSetting then
        if page1 then
            page1.ZIndex = 1
            page2.ZIndex = 0
        end

        guiHandler.runPage(page1 or mainPage)

        TweenService:Create(mainPage, TWEEN_INFO, {Position = UDim2.fromScale(position, 0)}):Play()
    else
        TweenService:Create(settingsPage[expandedSetting], TWEEN_INFO, {Position = UDim2.fromScale(1.05, 0)}):Play()
        TweenService:Create(settingsPage.Body, TWEEN_INFO, {Position = UDim2.fromScale(0, 0)}):Play()
        expandedSetting = nil

        for _, v in pairs(subConnections) do
            v:Disconnect()
        end

        subConnections = {}
    end
end

local function toggleSetting(setting, data)
    if setting == 0 then
        Data.autoRun = not Data.autoRun
        plugin:SetSetting('AutoRun', Data.autoRun)

        if Data.autoRun then
            TweenService:Create(autoRunButton.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 0}):Play()
        else
            TweenService:Create(autoRunButton.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 1}):Play()
        end
    elseif setting == 1 then
        Data.autoReconnect = not Data.autoReconnect
        plugin:SetSetting('AutoReconnect', Data.autoReconnect)

        if Data.autoReconnect then
            TweenService:Create(autoReconnectButton.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 0}):Play()
        else
            TweenService:Create(autoReconnectButton.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 1}):Play()
        end
    elseif setting == 2 then
        data = data:gsub(' ', '')
        data = string.split(data, ',')

        Data.filteredClasses = data
        plugin:SetSetting('FilteredClasses', data)
    elseif setting == 3 then
        Data.filteringMode = not Data.filteringMode
        plugin:SetSetting('FilteringMode', Data.filteringMode)

        if Data.filteringMode then
            TweenService:Create(data.Selector, SETTINGS_TWEEN_INFO, {Position = UDim2.fromScale(0.5, 0)}):Play()
        else
            TweenService:Create(data.Selector, SETTINGS_TWEEN_INFO, {Position = UDim2.fromScale(0, 0)}):Play()
        end
    else
        local syncState = not Data.syncedDirectories[setting]
        Data.syncedDirectories[setting] = syncState
        plugin:SetSetting('SyncedDirectories', Data.syncedDirectories)

        if syncState then
            TweenService:Create(data.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 0}):Play()
        else
            TweenService:Create(data.OnIcon, SETTINGS_TWEEN_INFO, {ImageTransparency = 1}):Play()
        end
    end
end

local function expandSetting(setting)
    expandedSetting = setting
    TweenService:Create(settingsPage[setting], TWEEN_INFO, {Position = UDim2.fromScale(0, 0)}):Play()
    TweenService:Create(settingsPage.Body, TWEEN_INFO, {Position = UDim2.fromScale(-1.05, 0)}):Play()

    for _, v in ipairs(settingsPage[setting]:GetDescendants()) do
        if v:IsA('ImageButton') then
            if v.Name ~= 'Mode' then
                subConnections[v.Parent.Name] = v.MouseButton1Click:Connect(function()
                    toggleSetting(v.Parent.Name, v)
                end)
            else
                subConnections[v.Parent.Name] = v.MouseButton1Click:Connect(function()
                    toggleSetting(3, v)
                end)
            end
        elseif v:IsA('TextBox') then
            subConnections[v.Parent.Name] = v:GetPropertyChangedSignal('Text'):Connect(function()
                filterInput(2)
            end)
            subConnections[v.Parent.Name..2] = v.FocusLost:Connect(function()
                toggleSetting(2, v.Text)
            end)
        end
    end
end

local function portToVS()
    if not isPorting then
        isPorting = true

        local tween = TweenService:Create(portToVSButton.Icon, LOADING_TWEEN_INFO, {Rotation = -360})
        portToVSButton.Icon.Position = UDim2.fromScale(0.5, 0.5)
        portToVSButton.Icon.Image = LOADING_ICON
        tween:Play()

        local success, response = HttpHandler.portInstances(FileHandler.portInstances())

        if not success then
            warn('Argon: '..response..' (ui1)')
        end

        success, response = HttpHandler.portScripts(FileHandler.portScripts())

        if not success then
            warn('Argon: '..response..' (ui2)')
        end

        tween:Cancel()
        portToVSButton.Icon.Rotation = 0
        portToVSButton.Icon.Position = UDim2.fromScale(0.55, 0.5)
        portToVSButton.Icon.Image = START_ICON

        isPorting = false
    end
end

local function portToRoblox()
    if not isPorting then
        isPorting = true

        local tween = TweenService:Create(portToRobloxButton.Icon, LOADING_TWEEN_INFO, {Rotation = -360})
        portToRobloxButton.Icon.Image = LOADING_ICON
        tween:Play()

        local success, response = HttpHandler.portProject()

        if not success then
            warn('Argon: '..response..' (ui3)')
        end

        tween:Cancel()
        portToRobloxButton.Icon.Rotation = 0
        portToRobloxButton.Icon.Image = START_ICON

        isPorting = false
    end
end

local function updateTheme()
    local theme = settings():GetService('Studio').Theme.Name

    if theme == lastTheme then
        return
    end
    lastTheme = theme

    if theme == 'Dark' then
        for _, v in ipairs(background:GetDescendants()) do
            if v:IsA('Frame') or v:IsA('ImageButton') then
                v.BackgroundColor3 = WHITE
            elseif v:IsA('TextBox') or v:IsA('TextLabel') then
                v.TextColor3 = LIGHT_WHITE
                if v:IsA('TextBox') then
                    v.BackgroundColor3 = WHITE
                end
            elseif v:IsA('ImageLabel') and v.Name ~= 'ClassIcon' and v.Name ~= 'Logo' then
                v.ImageColor3 = LIGHT_WHITE
            elseif v:IsA('ScrollingFrame') then
                v.ScrollBarImageColor3 = WHITE
            end
        end

        background.BackgroundColor3 = ROBLOX_BLACK
        mainPage.BackgroundColor3 = ROBLOX_BLACK
        settingsPage.BackgroundColor3 = ROBLOX_BLACK
        toolsPage.BackgroundColor3 = ROBLOX_BLACK
        overlay.BackgroundColor3 = LIGHT_BLACK
    elseif theme == 'Light' then
        for _, v in ipairs(background:GetDescendants()) do
            if v:IsA('Frame') or v:IsA('ImageButton') then
                v.BackgroundColor3 = BLACK
            elseif v:IsA('TextBox') or v:IsA('TextLabel') then
                v.TextColor3 = LIGHT_BLACK
                if v:IsA('TextBox') then
                    v.BackgroundColor3 = BLACK
                end
            elseif v:IsA('ImageLabel') and v.Name ~= 'ClassIcon' and v.Name ~= 'Logo' then
                v.ImageColor3 = LIGHT_BLACK
            elseif v:IsA('ScrollingFrame') then
                v.ScrollBarImageColor3 = BLACK
            end
        end

        background.BackgroundColor3 = ROBLOX_WHITE
        mainPage.BackgroundColor3 = ROBLOX_WHITE
        settingsPage.BackgroundColor3 = ROBLOX_WHITE
        toolsPage.BackgroundColor3 = ROBLOX_WHITE
        overlay.BackgroundColor3 = LIGHT_WHITE
    end
end

function guiHandler.runPage(page)
    for _, v in pairs(connections) do
        v:Disconnect()
    end
    connections = {}

    if page == mainPage then
        connections['connectButton'] = connectButton.MouseButton1Click:Connect(connect)

        connections['hostInput'] = hostInput:GetPropertyChangedSignal('Text'):Connect(function() filterInput(0) end)
        connections['portInput'] = portInput:GetPropertyChangedSignal('Text'):Connect(function() filterInput(1) end)
        connections['hostInput2'] = hostInput.FocusLost:Connect(function() setAddress(hostInput, true) end)
        connections['portInput2'] = portInput.FocusLost:Connect(function() setAddress(portInput) end)

        connections['settingsButton'] = settingsButton.MouseButton1Click:Connect(function() changePage(-1.05, settingsPage, toolsPage) end)
        connections['toolsButton'] = toolsButton.MouseButton1Click:Connect(function() changePage(1.05, toolsPage, settingsPage) end)
    elseif page == settingsPage then
        connections['settingsBack'] = settingsBack.MouseButton1Click:Connect(function() changePage(0) end)

        connections['autoRunButton'] = autoRunButton.MouseButton1Click:Connect(function() toggleSetting(0) end)
        connections['autoReconnectButton'] = autoReconnectButton.MouseButton1Click:Connect(function() toggleSetting(1) end)
        connections['syncedDirectoriesButton'] = syncedDirectoriesButton.MouseButton1Click:Connect(function() expandSetting('SyncedDirectories') end)
        connections['ClassFilteringButton'] = classFilteringButton.MouseButton1Click:Connect(function() expandSetting('ClassFiltering') end)
    elseif page == toolsPage then
        connections['toolsBack'] = toolsBack.MouseButton1Click:Connect(function() changePage(0) end)

        connections['portToVSButton'] = portToVSButton.MouseButton1Click:Connect(portToVS)
        connections['portToRobloxButton'] = portToRobloxButton.MouseButton1Click:Connect(portToRoblox)
    end
end

function guiHandler.run(newPlugin, autoConnect)
    themeConnection = settings():GetService('Studio').ThemeChanged:Connect(updateTheme)
    versionLabel.Text = Data.argonVersion
    updateTheme()

    if not RunService:IsEdit() then
        overlay.Visible = true
        return
    end

    plugin = newPlugin
    changePage(0)

    local hostSetting = plugin:GetSetting('Host')
    local portSetting = plugin:GetSetting('Port')
    local autoRunSetting = plugin:GetSetting('AutoRun')
    local autoReconnectSetting = plugin:GetSetting('AutoReconnect')
    local syncedDirectoriesSetting = plugin:GetSetting('SyncedDirectories')
    local filteredClassesSetting = plugin:GetSetting('FilteredClasses')
    local filteringMode = plugin:GetSetting('FilteringMode')

    if hostSetting ~= nil then
        hostInput.Text = hostSetting
        Data.host = hostSetting
    end

    if portSetting ~= nil then
        portInput.Text = portSetting
        Data.port = portSetting
    end

    if autoRunSetting ~= nil then
        Data.autoRun = autoRunSetting

        if autoRunSetting then
            autoRunButton.OnIcon.ImageTransparency = 0
        end
    end

    if autoReconnectSetting ~= nil then
        Data.autoReconnect = autoReconnectSetting

        if autoReconnectSetting then
            autoReconnectButton.OnIcon.ImageTransparency = 0
        end
    end

    Data.syncedDirectories = syncedDirectoriesSetting or Data.syncedDirectories
    for i, v in pairs(Data.syncedDirectories) do
        local properties = StudioService:GetClassIcon(i)
        local icon = syncedDirectoriesFrame[i].ClassIcon

        for j, w in pairs(properties) do
            icon[j] = w
        end

        if v then
            syncedDirectoriesFrame[i].Button.OnIcon.ImageTransparency = 0
        end
    end

    Data.filteredClasses = filteredClassesSetting or Data.filteredClasses
    if filteredClassesSetting then
        local text = ''

        for i, v in ipairs(Data.filteredClasses) do
            if i ~= 1 then
                text = text..', '..v
            else
                text = v
            end
        end

        classFilteringFrame.Input.Text = text
    end

    if filteringMode ~= nil then
        Data.filteringMode = filteringMode

        if filteringMode then
            classFilteringFrame.Mode.Selector.Position = UDim2.fromScale(0.5, 0)
        end
    end

    if autoConnect then
        connect()
    end
end

function guiHandler.stop()
    if RunService:IsEdit() then
        for _, v in pairs(connections) do
            v:Disconnect()
        end
        connections = {}
    end

    themeConnection:Disconnect()
    themeConnection = nil
end

return guiHandler
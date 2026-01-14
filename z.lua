loadstring([[
    function LPH_NO_VIRTUALIZE(f) return f end;
]])();

TweenService = game:GetService("TweenService")
UserInputService = game:GetService("UserInputService")
RunService = game:GetService("RunService")
CoreGui = game:GetService("CoreGui")
Players = game:GetService("Players")
HttpService = game:GetService("HttpService")
Lighting = game:GetService("Lighting")
Terrain = workspace:FindFirstChildOfClass("Terrain")
    
local VoraLib = {}
local Connections = {}

-- Performance Optimization: Data Cache System
DataCache = {
    equipped = nil,
    rods = nil,
    inventory = nil,
    enchantStones = nil,
    lastUpdate = 0,
    cacheDuration = 3 -- Increased from 2 to 3 seconds for better performance
}

function DataCache:Get(key)
    if tick() - self.lastUpdate > self.cacheDuration then
        self:Invalidate()
    end
    return self[key]
end

function DataCache:Set(key, value)
    self[key] = value
    self.lastUpdate = tick()
end

function DataCache:Invalidate()
    self.equipped = nil
    self.rods = nil
    self.inventory = nil
    self.enchantStones = nil
end

-- Manual Config System
local ConfigFolder = "VoraHub_Configs"
local ConfigData = {}
local CurrentConfigName = ""
local SaveDebounce = nil
-- Auto-save disabled: config only saves to memory, not file (user must click Save button)
local AutoSaveEnabled = false
local LastSaveTime = 0
local HasUnsavedChanges = false
local HasShownSaveWarning = false

-- Create config folder if not exists
if not isfolder(ConfigFolder) then
	makefolder(ConfigFolder)
    print("Created config folder: " .. ConfigFolder)
end
print("Config Folder Path: " .. ConfigFolder)

local function getConfigList()
	local configs = {}
	local success, files = pcall(function()
		return listfiles(ConfigFolder)
	end)
	
	if success and files then
		for _, file in ipairs(files) do
            -- Handle both slash types and extract just the filename
			local name = file:match("([^/\\]+)%.json$")
			if name then
				table.insert(configs, name)
			end
		end
	end
	return configs
end

local function saveConfigWithName(configName)
	if not configName or configName == "" then
		warn("[Config] Config name cannot be empty")
		return false, "Config name cannot be empty"
	end
	
	-- Sanitize config name (remove invalid characters)
	configName = configName:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
	if configName == "" then
		return false, "Invalid config name"
	end
	
	local success, err = pcall(function()
		-- Create a clean copy of ConfigData to avoid circular references
		local cleanData = {}
		local count = 0
		for key, value in pairs(ConfigData) do
			-- Only save simple types (string, number, boolean, table)
			local valueType = type(value)
			if valueType == "string" or valueType == "number" or valueType == "boolean" then
				cleanData[key] = value
				count = count + 1
			elseif valueType == "table" then
				-- Deep copy tables to avoid references
				local tableCopy = {}
				for k, v in pairs(value) do
					if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
						tableCopy[k] = v
					end
				end
				cleanData[key] = tableCopy
				count = count + 1
			end
		end
		
		-- Warn if saving empty data, but still save
		if count == 0 then
			warn("[Config] Warning: Config data is empty!")
		end
		
		local jsonData = HttpService:JSONEncode(cleanData)
		local filePath = ConfigFolder .. "/" .. configName .. ".json"
		print("[Config] Saving to: " .. filePath) -- Debug print
        
        -- Ensure folder exists again just in case
        if not isfolder(ConfigFolder) then
            makefolder(ConfigFolder)
        end
        
		writefile(filePath, jsonData)
		LastSaveTime = tick()
	end)
	
	if not success then
		warn("[Config] Failed to save config:", err)
		return false, tostring(err)
	end
	
	return true, nil
end

local function loadConfigByName(configName)
	if not configName or configName == "" then
		return false, "Config name cannot be empty"
	end
	
	local filePath = ConfigFolder .. "/" .. configName .. ".json"
	
	if not isfile(filePath) then
		return false, "Config file does not exist"
	end
	
	local success, result = pcall(function()
		local jsonData = readfile(filePath)
		if not jsonData or jsonData == "" then
			return nil
		end
		return HttpService:JSONDecode(jsonData)
	end)
	
	if success and result and type(result) == "table" then
		ConfigData = result
		CurrentConfigName = configName
		return true, nil
	else
		warn("[Config] Failed to load config:", configName, result)
		return false, "Failed to decode config file"
	end
end

local function deleteConfig(configName)
	if not configName or configName == "" then
		return false, "Config name cannot be empty"
	end
	
	local filePath = ConfigFolder .. "/" .. configName .. ".json"
	
	if not isfile(filePath) then
		return false, "Config file does not exist"
	end
	
	local success, err = pcall(function()
		delfile(filePath)
	end)
	
	if not success then
		warn("[Config] Failed to delete config:", err)
		return false, tostring(err)
	end
	
	return true, nil
end

-- Track config changes (called when ConfigData is updated)
local function trackConfigChange()
	HasUnsavedChanges = true
end


-- Debounced save function to prevent excessive writes
local function saveConfig()
	-- Track that changes were made (even if not auto-saving to file)
	trackConfigChange()
	
	if not AutoSaveEnabled then
		return
	end
	
	if not CurrentConfigName or CurrentConfigName == "" then
		return
	end
	
	-- Cancel previous debounce
	if SaveDebounce then
		task.cancel(SaveDebounce)
	end
	
	-- Debounce save by 0.5 seconds
	SaveDebounce = task.delay(0.5, function()
		local success, err = saveConfigWithName(CurrentConfigName)
		if not success then
			warn("[Config] Auto-save failed:", err)
		end
		SaveDebounce = nil
	end)
end




local function MakeDraggable(topbarobject, object)
	local Dragging = nil
	local DragInput = nil
	local DragStart = nil
	local StartPosition = nil

	local function Update(input)
		local Delta = input.Position - DragStart
		local pos = UDim2.new(StartPosition.X.Scale, StartPosition.X.Offset + Delta.X, StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y)
		local Tween = TweenService:Create(object, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = pos})
		Tween:Play()
	end

	table.insert(Connections, topbarobject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Dragging = true
			DragStart = input.Position
			StartPosition = object.Position

			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					Dragging = false
					if connection then connection:Disconnect() end
				end
			end)
		end
	end))

	table.insert(Connections, topbarobject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			DragInput = input
		end
	end))

	table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
		if input == DragInput and Dragging then
			Update(input)
		end
	end))
end

local function Create(className, properties)
	local instance = Instance.new(className)
	for k, v in pairs(properties) do
		instance[k] = v
	end
	return instance
end


local Theme = {
	Background = Color3.fromRGB(10, 12, 25), 
	Sidebar = Color3.fromRGB(15, 18, 32),
	ElementBackground = Color3.fromRGB(25, 30, 50),
	TextColor = Color3.fromRGB(255, 255, 255), 
	TextSecondary = Color3.fromRGB(180, 200, 230), 
	Accent = Color3.fromRGB(0, 190, 255), 
	Hover = Color3.fromRGB(35, 45, 70),
	Outline = Color3.fromRGB(40, 60, 90)
}


function VoraLib:CreateWindow(options)
    
	options = options or {}
	local TitleName = options.Name or "VoraHub"
	local IntroEnabled = options.Intro or false
	
	
	local function GetParent()
		local Success, Parent = pcall(function()
			return (gethui and gethui()) or game:GetService("CoreGui")
		end)
		
		if not Success or not Parent then
			return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		end
		
		return Parent
	end

	local ScreenGui = Create("ScreenGui", {
		Name = "VoraHub",
		Parent = GetParent(),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false
	})
	
	local ViewportSize = workspace.CurrentCamera.ViewportSize
	local IsMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local InitialSize = IsMobile and UDim2.new(0, 500, 0, 320) or UDim2.new(0, 700, 0, 450)
	local InitialPosition = IsMobile and UDim2.new(0.5, -250, 0.5, -160) or UDim2.new(0.5, -350, 0.5, -225)
	
	local MainFrame = Create("Frame", {
		Name = "MainFrame",
		Parent = ScreenGui,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.05, 
		BorderSizePixel = 0,
		Position = InitialPosition,
		Size = InitialSize,
		ClipsDescendants = true
	})
	
	Create("UICorner", {
		CornerRadius = UDim.new(0, 10), 
		Parent = MainFrame
	})
	
	
	local MainStroke = Create("UIStroke", {
		Transparency = 0,
		Thickness = 1,
		Parent = MainFrame
	})
	
	Create("UIGradient", {
		Parent = MainStroke,
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 190, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 18, 32))
		},
		Rotation = 45
	})

	local Header = Create("Frame", {
		Name = "Header",
		Parent = MainFrame,
		BackgroundColor3 = Theme.Sidebar,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 45) 
	})
	
	Create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = Header
	})
	
	
	Create("Frame", {
		Name = "BottomFiller",
		Parent = Header,
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0.5, 0),
		ZIndex = 1
	})
	
	
	Create("Frame", {
		Parent = Header,
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 2
	})

	
	local Logo = Create("ImageLabel", {
		Name = "Logo",
		Parent = Header,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 5),
		Size = UDim2.new(0, 35, 0, 35),
		Image = "rbxassetid://109951475872006",
		ImageColor3 = Theme.Accent,
		ZIndex = 2
	})

	
	local TitleLabel = Create("TextLabel", {
		Name = "Title",
		Parent = Header,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 70, 0, 0),
		Size = UDim2.new(1, -160, 1, 0),
		Font = Enum.Font.GothamBold,
		Text = TitleName,
		TextColor3 = Theme.TextColor,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2
	})
	
	
	if IntroEnabled then
		local StartSize = MainFrame.Size
		MainFrame.Size = UDim2.new(0, 0, 0, 0)
		MainFrame.BackgroundTransparency = 1
		
		TweenService:Create(MainFrame, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = StartSize,
			BackgroundTransparency = 0.05
		}):Play()
	end
	
	
	local Sidebar = Create("Frame", {
		Name = "Sidebar",
		Parent = MainFrame,
		BackgroundColor3 = Theme.Sidebar,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 45),
		Size = UDim2.new(0, 180, 1, -45)
	})
	
	
	Create("Frame", {
		Name = "Separator",
		Parent = Sidebar,
		BackgroundColor3 = Theme.Outline,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -2, 0, 0),
		Size = UDim2.new(0, 2, 1, 0)
	})

	
	local Controls = Create("Frame", {
		Name = "Controls",
		Parent = Header,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -100, 0, 0),
		Size = UDim2.new(0, 100, 1, 0),
		ZIndex = 2
	})
	
	local UIListLayout = Create("UIListLayout", {
		Parent = Controls,
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8)
	})
	
	Create("UIPadding", {
		Parent = Controls,
		PaddingRight = UDim.new(0, 15)
	})

	local IsMinimized = false
	local ToggleButton = Create("ImageButton", {
		Name = "ToggleUI",
		Parent = ScreenGui,
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0.1, 0, 0.1, 0),
		Size = UDim2.new(0, 50, 0, 50),
		Image = "rbxassetid://136076032343357", 
		ImageColor3 = Theme.TextColor,
		Visible = true, 
		Active = true,
		Draggable = true,
		ZIndex = 100
	})
	
	Create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = ToggleButton
	})
	
	Create("UIStroke", {
		Color = Theme.Outline,
		Thickness = 1,
		Parent = ToggleButton
	})

	local function ToggleUI()
		IsMinimized = not IsMinimized
		
		if IsMinimized then
			MainFrame.Visible = false
		else
			MainFrame.Visible = true

			local OriginalSize = IsMobile and UDim2.new(0, 500, 0, 320) or UDim2.new(0, 700, 0, 450)
			MainFrame.Size = UDim2.new(0, 0, 0, 0)
			TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = OriginalSize
			}):Play()
		end
	end
	
	ToggleButton.MouseButton1Click:Connect(ToggleUI)

	local function CreateControlButton(name, icon, layoutOrder, callback)
		local Button = Create("ImageButton", {
			Name = name,
			Parent = Controls,
			BackgroundTransparency = 1,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(0, 20, 0, 20),
			Image = "rbxassetid://" .. icon,
			ImageColor3 = Theme.TextSecondary,
			AutoButtonColor = false
		})
		
		Button.MouseEnter:Connect(function()
			TweenService:Create(Button, TweenInfo.new(0.2), {ImageColor3 = Theme.TextColor}):Play()
		end)
		
		Button.MouseLeave:Connect(function()
			TweenService:Create(Button, TweenInfo.new(0.2), {ImageColor3 = Theme.TextSecondary}):Play()
		end)
		
		Button.MouseButton1Click:Connect(callback)
		return Button
	end

	CreateControlButton("Minimize", "71686683787518", 1, ToggleUI)

	
	local Window = {
		Tabs = {},
		Elements = {},
		Instance = ScreenGui
	}

    Window.Elements = {}

	
	local NotificationHolder = Create("Frame", {
		Name = "NotificationHolder",
		Parent = ScreenGui,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.new(0, 300, 1, -20),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 100
	})

	Create("UIListLayout", {
		Parent = NotificationHolder,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10)
	})

	function Window:Notify(options)
		options = options or {}
		local Title = options.Title or "Notification"
		local Content = options.Content or "Message"
		local Duration = options.Duration or 3
		local Image = options.Image or "rbxassetid://109951475872006"

		local NotifyFrame = Create("Frame", {
			Name = "NotifyFrame",
			Parent = NotificationHolder,
			BackgroundColor3 = Theme.Sidebar,
			BackgroundTransparency = 0.1,
			Size = UDim2.new(1, 0, 0, 0), 
			AutomaticSize = Enum.AutomaticSize.Y,
			ClipsDescendants = true
		})

		Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = NotifyFrame })
		Create("UIStroke", { Color = Theme.Outline, Thickness = 1, Parent = NotifyFrame })

		local ContentFrame = Create("Frame", {
			Parent = NotifyFrame,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 60)
		})

		local Icon = Create("ImageLabel", {
			Parent = ContentFrame,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(0, 36, 0, 36),
			Image = Image,
			ImageColor3 = Theme.Accent
		})
		
		Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Icon })

		local TitleLabel = Create("TextLabel", {
			Parent = ContentFrame,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 58, 0, 10),
			Size = UDim2.new(1, -68, 0, 20),
			Font = Enum.Font.GothamBold,
			Text = Title,
			TextColor3 = Theme.TextColor,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left
		})

		local ContentLabel = Create("TextLabel", {
			Parent = ContentFrame,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 58, 0, 30),
			Size = UDim2.new(1, -68, 0, 20),
			Font = Enum.Font.Gotham,
			Text = Content,
			TextColor3 = Theme.TextSecondary,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true
		})
		
		
		NotifyFrame.Position = UDim2.new(1, 320, 0, 0)
		TweenService:Create(NotifyFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {Position = UDim2.new(0, 0, 0, 0)}):Play()
		
		
		local ProgressBar = Create("Frame", {
			Parent = NotifyFrame,
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -2),
			Size = UDim2.new(1, 0, 0, 2)
		})
		
		TweenService:Create(ProgressBar, TweenInfo.new(Duration, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 2)}):Play()

		task.delay(Duration, function()
			TweenService:Create(NotifyFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Position = UDim2.new(1, 320, 0, 0)}):Play()
			task.wait(0.5)
			NotifyFrame:Destroy()
		end)
	end

	
	local Maximized = false
	local DefaultSize = IsMobile and UDim2.new(0, 500, 0, 320) or UDim2.new(0, 700, 0, 450)
	local MaxSize = IsMobile and UDim2.new(0, 600, 0, 350) or UDim2.new(0, 900, 0, 600)
	local DefaultPos = IsMobile and UDim2.new(0.5, -250, 0.5, -160) or UDim2.new(0.5, -350, 0.5, -225)
	local MaxPos = IsMobile and UDim2.new(0.5, -300, 0.5, -175) or UDim2.new(0.5, -450, 0.5, -300)
	
	CreateControlButton("Maximize", "135582116755237", 2, function()
		Maximized = not Maximized
		if Maximized then
			TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = MaxSize,
				Position = MaxPos
			}):Play()
		else
			TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = DefaultSize,
				Position = DefaultPos
			}):Play()
		end
	end)

	CreateControlButton("Close", "121948938505669", 3, function()
		TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1
		}):Play()
		task.wait(0.3)
		Window:Destroy()
	end)
	
	local ToggleKey = Enum.KeyCode.RightControl
	table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == ToggleKey then
			ScreenGui.Enabled = not ScreenGui.Enabled
		end
	end))

	
	local TabContainer = Create("ScrollingFrame", {
		Name = "TabContainer",
		Parent = Sidebar,
		Active = true,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 15),
		Size = UDim2.new(1, 0, 1, -25),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Accent
	})
	
	local ButtonsHolder = Create("Frame", {
		Name = "ButtonsHolder",
		Parent = TabContainer,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.Y
	})
	
	Create("UIListLayout", {
		Parent = ButtonsHolder,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 5)
	})
	
	Create("UIPadding", {
		Parent = ButtonsHolder,
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10)
	})
	
	local SlidingIndicator = Create("Frame", {
		Name = "SlidingIndicator",
		Parent = TabContainer,
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 3, 0, 20),
		Visible = false,
		ZIndex = 2
	})

	Create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = SlidingIndicator
	})

	
	local ContentContainer = Create("Frame", {
		Name = "ContentContainer",
		Parent = MainFrame,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 180, 0, 45),
		Size = UDim2.new(1, -180, 1, -45)
	})

	MakeDraggable(Header, MainFrame)
	
	function Window:LoadConfig(configName)
		if not configName or configName == "" then
			Window:Notify({ Title = "Error", Content = "No config selected!", Duration = 3 })
			return
		end
		
		local success = loadConfigByName(configName)
		if not success then
			Window:Notify({ Title = "Error", Content = "Failed to load config!", Duration = 3 })
			return
		end
		
		-- Update all registered elements
		for key, element in pairs(Window.Elements) do
			if ConfigData[key] ~= nil then
				pcall(function()
					element.Object:Set(ConfigData[key])
				end)
			end
		end
		
		Window:Notify({
			Title = "Success",
			Content = "Config '" .. configName .. "' loaded successfully!",
			Duration = 4
		})
	end

	function Window:CreateTab(options)
		options = options or {}
		local TabName = options.Name or "Tab"
		local TabIcon = options.Icon or ""
		
		local Tab = {
			Active = false
		}
		
		local TabButton = Create("TextButton", {
			Name = TabName .. "Button",
			Parent = ButtonsHolder,
			BackgroundColor3 = Theme.ElementBackground,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 36),
			AutoButtonColor = false,
			ClipsDescendants = true,
			Text = ""
		})
		
		Create("UICorner", {
			CornerRadius = UDim.new(0, 6),
			Parent = TabButton
		})
		
		local IconImage
		if TabIcon ~= "" then
			IconImage = Create("ImageLabel", {
				Parent = TabButton,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0.5, -10),
				Size = UDim2.new(0, 20, 0, 20),
				Image = TabIcon,
				ImageColor3 = Theme.TextSecondary
			})
		end
		
		local TabLabel = Create("TextLabel", {
			Parent = TabButton,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, TabIcon ~= "" and 40 or 15, 0, 0),
			Size = UDim2.new(1, TabIcon ~= "" and -40 or -15, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = TabName,
			TextColor3 = Theme.TextSecondary,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left
		})
		
		TabButton.MouseEnter:Connect(function()
			if not Tab.Active then
				TweenService:Create(TabButton, TweenInfo.new(0.2), {BackgroundTransparency = 0.9}):Play()
				TweenService:Create(TabLabel, TweenInfo.new(0.2), {TextColor3 = Theme.TextColor}):Play()
				if IconImage then
					TweenService:Create(IconImage, TweenInfo.new(0.2), {ImageColor3 = Theme.TextColor}):Play()
				end
			end
		end)
		
		TabButton.MouseLeave:Connect(function()
			if not Tab.Active then
				TweenService:Create(TabButton, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
				TweenService:Create(TabLabel, TweenInfo.new(0.2), {TextColor3 = Theme.TextSecondary}):Play()
				if IconImage then
					TweenService:Create(IconImage, TweenInfo.new(0.2), {ImageColor3 = Theme.TextSecondary}):Play()
				end
			end
		end)
		
		local TabPage = Create("ScrollingFrame", {
			Name = TabName .. "Page",
			Parent = ContentContainer,
			Active = true,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = Theme.Accent,
			Visible = false
		})
		
		Create("UIListLayout", {
			Parent = TabPage,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8)
		})
		
		Create("UIPadding", {
			Parent = TabPage,
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 15),
			PaddingRight = UDim.new(0, 10)
		})

		function Tab:Activate()
			for _, t in pairs(Window.Tabs) do
				if t ~= Tab then
					TweenService:Create(t.Instance, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
					TweenService:Create(t.Label, TweenInfo.new(0.2), {TextColor3 = Theme.TextSecondary}):Play()
					if t.Icon then
						TweenService:Create(t.Icon, TweenInfo.new(0.2), {ImageColor3 = Theme.TextSecondary}):Play()
					end
					t.Page.Visible = false
					t.Active = false
				end
			end
			
			Tab.Active = true
			TweenService:Create(TabButton, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = 0.85}):Play()
			TweenService:Create(TabLabel, TweenInfo.new(0.3), {TextColor3 = Theme.Accent}):Play() 
			if IconImage then
				TweenService:Create(IconImage, TweenInfo.new(0.3), {ImageColor3 = Theme.Accent}):Play()
			end
			
			TabPage.Visible = true

			if not SlidingIndicator.Visible then
				SlidingIndicator.Visible = true
				SlidingIndicator.Position = UDim2.new(0, 0, 0, TabButton.AbsolutePosition.Y - ButtonsHolder.AbsolutePosition.Y + 8)
			end
			
			local targetY = TabButton.AbsolutePosition.Y - ButtonsHolder.AbsolutePosition.Y + 8
			
			TweenService:Create(SlidingIndicator, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, 0, 0, targetY)
			}):Play()
		end

		TabButton.MouseButton1Click:Connect(function()
			
			task.spawn(function()
				local Mouse = Players.LocalPlayer:GetMouse()
				local Ripple = Create("Frame", {
					Parent = TabButton,
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BackgroundTransparency = 0.8,
					BorderSizePixel = 0,
					Position = UDim2.new(0, Mouse.X - TabButton.AbsolutePosition.X, 0, Mouse.Y - TabButton.AbsolutePosition.Y),
					Size = UDim2.new(0, 0, 0, 0),
					ZIndex = 1
				})
				
				Create("UICorner", {
					CornerRadius = UDim.new(1, 0),
					Parent = Ripple
				})

				local Tween = TweenService:Create(Ripple, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, 150, 0, 150),
					Position = UDim2.new(0, Mouse.X - TabButton.AbsolutePosition.X - 75, 0, Mouse.Y - TabButton.AbsolutePosition.Y - 75),
					BackgroundTransparency = 1
				})
				
				Tween:Play()
				Tween.Completed:Wait()
				Ripple:Destroy()
			end)

			Tab:Activate()
		end)
		
		Tab.Instance = TabButton
		Tab.Label = TabLabel
		Tab.Icon = IconImage
		Tab.Page = TabPage
		table.insert(Window.Tabs, Tab)
		
		if #Window.Tabs == 1 then
			Tab:Activate()
		end

		TabPage.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			TabPage.CanvasSize = UDim2.new(0, 0, 0, TabPage.UIListLayout.AbsoluteContentSize.Y + 20)
		end)

		
		
		function Tab:CreateSection(options)
			options = options or {}
			local SectionName = options.Name or "Section"
			local Icon = options.Icon
			
			local SectionContainer = Create("Frame", {
				Parent = TabPage,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 30)
			})
			
			local ContentLayout = Create("UIListLayout", {
				Parent = SectionContainer,
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder
			})

			if Icon then
				local IconImage = Create("ImageLabel", {
					Parent = SectionContainer,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 18, 0, 18),
					Image = Icon,
					ImageColor3 = Theme.TextColor,
					LayoutOrder = 1
				})
			end

			local SectionLabel = Create("TextLabel", {
				Name = "SectionLabel",
				Parent = SectionContainer,
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = Enum.Font.GothamBold,
				Text = SectionName,
				TextColor3 = Theme.TextColor,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2
			})
			
			
			
			
			
			local LineContainer = Create("Frame", {
				Parent = SectionContainer,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0), 
				LayoutOrder = 3
			})
			
			
			ContentLayout:Destroy()
			if Icon then SectionContainer:FindFirstChild("ImageLabel"):Destroy() end
			SectionLabel:Destroy()
			LineContainer:Destroy()
			
			
			local CurrentX = 0
			
			if Icon then
				Create("ImageLabel", {
					Parent = SectionContainer,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 0, 0.5, -9),
					Size = UDim2.new(0, 18, 0, 18),
					Image = Icon,
					ImageColor3 = Theme.TextColor
				})
				CurrentX = 24
			end
			
			local Label = Create("TextLabel", {
				Name = "SectionLabel",
				Parent = SectionContainer,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, CurrentX, 0, 0),
				Size = UDim2.new(0, 0, 1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = Enum.Font.GothamBold,
				Text = SectionName,
				TextColor3 = Theme.TextColor,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			
			task.delay(0.05, function()
				local TextWidth = Label.TextBounds.X
				local LineX = CurrentX + TextWidth + 10
				
				local Separator = Create("Frame", {
					Parent = SectionContainer,
					BackgroundColor3 = Color3.fromRGB(60, 60, 70), 
					BorderSizePixel = 0,
					Position = UDim2.new(0, LineX, 0.5, 0),
					Size = UDim2.new(1, -LineX, 0, 2) 
				})
			end)
		end

        function Tab:CreateParagraph(options)
            options = options or {}
            local Title = options.Title or "Paragraph"
            local Content = options.Content or "Lorem ipsum dolor sit amet."
            
            local ParagraphFrame = Create("Frame", {
                Name = "ParagraphFrame",
                Parent = TabPage,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 6),
                Parent = ParagraphFrame
            })
            
            Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.6,
                Thickness = 1,
                Parent = ParagraphFrame
            })
            
            local TitleLabel = Create("TextLabel", {
                Parent = ParagraphFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 8),
                Size = UDim2.new(1, -24, 0, 20),
                Font = Enum.Font.GothamBold,
                Text = Title,
                TextColor3 = Theme.TextColor,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left
            })
            
            local ContentLabel = Create("TextLabel", {
                Parent = ParagraphFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 32),
                Size = UDim2.new(1, -24, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Font = Enum.Font.Gotham,
                Text = Content,
                TextColor3 = Theme.TextSecondary,
                TextSize = 13,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                RichText = true
            })
            
            Create("UIPadding", {
                Parent = ParagraphFrame,
                PaddingBottom = UDim.new(0, 12)
            })
            
            local ParagraphObject = {
                Title = Title,
                Desc = Content
            }
            
            function ParagraphObject:SetTitle(newTitle)
                self.Title = newTitle
                TitleLabel.Text = newTitle
            end
            
            function ParagraphObject:SetDesc(newDesc)
                self.Desc = newDesc
                ContentLabel.Text = newDesc
            end
            
            function ParagraphObject:GetTitle()
                return self.Title
            end
            
            function ParagraphObject:GetDesc()
                return self.Desc
            end
            
            return ParagraphObject
        end

		function Tab:CreateLabel(options)
			options = options or {}
			local Text = options.Text or "Label"
			
			local LabelFrame = Create("Frame", {
				Name = "LabelFrame",
				Parent = TabPage,
				BackgroundColor3 = Theme.ElementBackground,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 26)
			})
			
			local Label = Create("TextLabel", {
				Parent = LabelFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 5, 0, 0),
				Size = UDim2.new(1, -10, 1, 0),
				Font = Enum.Font.GothamMedium,
				Text = Text,
				TextColor3 = Theme.TextColor,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			return Label
		end

		function Tab:CreateButton(options)
			options = options or {}
			local ButtonName = options.Name or "Button"
			local SubText = options.SubText
			local Icon = options.Icon
			local Callback = options.Callback or function() end
			
			local ButtonFrame = Create("Frame", {
				Name = "ButtonFrame",
				Parent = TabPage,
				BackgroundColor3 = Theme.ElementBackground,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, SubText and 50 or 38),
				ClipsDescendants = true
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 6),
				Parent = ButtonFrame
			})
			
			local ButtonStroke = Create("UIStroke", {
				Color = Theme.Outline,
				Transparency = 0.5,
				Thickness = 1,
				Parent = ButtonFrame
			})
			
			local Button = Create("TextButton", {
				Name = "Button",
				Parent = ButtonFrame,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Font = Enum.Font.GothamMedium,
				Text = SubText and "" or ButtonName,
				TextColor3 = Theme.TextColor,
				TextSize = 14,
				AutoButtonColor = false,
				ZIndex = 2
			})
			
			if SubText then
				Create("TextLabel", {
					Parent = Button,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 12, 0, 8),
					Size = UDim2.new(1, -50, 0, 20),
					Font = Enum.Font.GothamBold,
					Text = ButtonName,
					TextColor3 = Theme.TextColor,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left
				})
				
				Create("TextLabel", {
					Parent = Button,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 12, 0, 26),
					Size = UDim2.new(1, -50, 0, 14),
					Font = Enum.Font.Gotham,
					Text = SubText,
					TextColor3 = Theme.TextSecondary,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left
				})
			end
			
			if Icon then
				Create("ImageLabel", {
					Parent = Button,
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.new(0, 20, 0, 20),
					Image = Icon,
					ImageColor3 = Theme.TextSecondary
				})
			end
			
			Button.MouseEnter:Connect(function()
				TweenService:Create(ButtonFrame, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.1}):Play()
				TweenService:Create(ButtonStroke, TweenInfo.new(0.2), {Color = Theme.Accent, Transparency = 0.2}):Play()
			end)
			
			Button.MouseLeave:Connect(function()
				TweenService:Create(ButtonFrame, TweenInfo.new(0.2), {BackgroundColor3 = Theme.ElementBackground, BackgroundTransparency = 0.2}):Play()
				TweenService:Create(ButtonStroke, TweenInfo.new(0.2), {Color = Theme.Outline, Transparency = 0.5}):Play()
			end)
			
			Button.MouseButton1Click:Connect(function()
				
				task.spawn(function()
					local Mouse = Players.LocalPlayer:GetMouse()
					local Ripple = Create("Frame", {
						Parent = ButtonFrame,
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0.8,
						BorderSizePixel = 0,
						Position = UDim2.new(0, Mouse.X - ButtonFrame.AbsolutePosition.X, 0, Mouse.Y - ButtonFrame.AbsolutePosition.Y),
						Size = UDim2.new(0, 0, 0, 0),
						ZIndex = 1
					})
					
					Create("UICorner", {
						CornerRadius = UDim.new(1, 0),
						Parent = Ripple
					})

					local Tween = TweenService:Create(Ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = UDim2.new(0, 200, 0, 200),
						Position = UDim2.new(0, Mouse.X - ButtonFrame.AbsolutePosition.X - 100, 0, Mouse.Y - ButtonFrame.AbsolutePosition.Y - 100),
						BackgroundTransparency = 1
					})
					
					Tween:Play()
					Tween.Completed:Wait()
					Ripple:Destroy()
				end)

				TweenService:Create(ButtonFrame, TweenInfo.new(0.1), {BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0}):Play()
				task.wait(0.1)
				TweenService:Create(ButtonFrame, TweenInfo.new(0.3), {BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.1}):Play()
				Callback()
			end)
		end
        function Tab:CreateToggle(options)
            options = options or {}
            local ToggleName = options.Name or "Toggle"
            local SubText = options.SubText
            -- Support both 'Default' and 'Value' for backward compatibility
            local Default = options.Default or options.Value or false
            local Values = options.Values or {}
            local Callback = options.Callback or function() end
            local ConfigKey = options.ConfigKey or ToggleName
            
            -- Load saved value if exists
            if ConfigData[ConfigKey] ~= nil then
                Default = ConfigData[ConfigKey]
            end
            
            local Toggled = Default
            
            local ToggleFrame = Create("Frame", {
                Name = "ToggleFrame",
                Parent = TabPage,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, SubText and 50 or 38)
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 6),
                Parent = ToggleFrame
            })
            
            Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.5,
                Thickness = 1,
                Parent = ToggleFrame
            })
            
            local Label = Create("TextLabel", {
                Parent = ToggleFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, SubText and 8 or 0),
                Size = UDim2.new(1, -60, 0, SubText and 20 or 38),
                Font = SubText and Enum.Font.GothamBold or Enum.Font.GothamMedium,
                Text = ToggleName,
                TextColor3 = Theme.TextColor,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center
            })
            
            if SubText then
                Create("TextLabel", {
                    Parent = ToggleFrame,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 0, 26),
                    Size = UDim2.new(1, -60, 0, 14),
                    Font = Enum.Font.Gotham,
                    Text = SubText,
                    TextColor3 = Theme.TextSecondary,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextYAlignment = Enum.TextYAlignment.Center
                })
            end
            
            local SwitchBg = Create("Frame", {
                Parent = ToggleFrame,
                AnchorPoint = Vector2.new(1, 0.5),
                BackgroundColor3 = Toggled and Theme.Accent or Color3.fromRGB(45, 45, 50),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, 42, 0, 22)
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(1, 0),
                Parent = SwitchBg
            })
            
            local SwitchCircle = Create("Frame", {
                Parent = SwitchBg,
                AnchorPoint = Vector2.new(0, 0.5),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                Position = UDim2.new(0, Toggled and 22 or 2, 0.5, 0),
                Size = UDim2.new(0, 18, 0, 18)
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(1, 0),
                Parent = SwitchCircle
            })
            
            local Button = Create("TextButton", {
                Parent = ToggleFrame,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = ""
            })
            
            -- Create the object to return
            local ToggleObject = {
                Value = Default
            }

            local function UpdateToggleState(newValue)
                Toggled = newValue
                ToggleObject.Value = Toggled
                
                local TargetColor = Toggled and Theme.Accent or Color3.fromRGB(45, 45, 50)
                local TargetPos = UDim2.new(0, Toggled and 22 or 2, 0.5, 0)
                
                TweenService:Create(SwitchBg, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundColor3 = TargetColor}):Play()
                TweenService:Create(SwitchCircle, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = TargetPos}):Play()
                
                -- Save to config
                ConfigData[ConfigKey] = Toggled
                saveConfig()
                
                if #Values > 0 then
                    Callback(Values[Toggled and 2 or 1]) 
                else
                    Callback(Toggled)
                end
            end
            
            function ToggleObject:Set(newValue)
                -- Type validation: ensure boolean
                if type(newValue) ~= "boolean" then
                    newValue = newValue == true or newValue == "true" or newValue == 1
                end
                UpdateToggleState(newValue)
            end
            
            Button.MouseButton1Click:Connect(function()
                UpdateToggleState(not Toggled)
            end)
            
            if Default then
                UpdateToggleState(true)
            end
            
            -- Register Element
            if ConfigKey then
                Window.Elements[ConfigKey] = {
                    Object = ToggleObject,
                    Type = "Toggle"
                }
            end

            return ToggleObject
        end


		function Tab:CreateSlider(options)
			options = options or {}
			local SliderName = options.Name or "Slider"
			local Min = options.Min or 0
			local Max = options.Max or 100
			-- Support both 'Default' and 'Value' for backward compatibility
			local Default = options.Default or options.Value or Min
			local Callback = options.Callback or function() end
			local ConfigKey = options.ConfigKey or SliderName
			
			-- Load saved value if exists
			if ConfigData[ConfigKey] ~= nil then
				Default = math.clamp(tonumber(ConfigData[ConfigKey]) or Default, Min, Max)
			end
			
			local SliderFrame = Create("Frame", {
				Name = "SliderFrame",
				Parent = TabPage,
				BackgroundColor3 = Theme.ElementBackground,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 55)
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 6),
				Parent = SliderFrame
			})
			
			Create("UIStroke", {
				Color = Theme.Outline,
				Transparency = 0.5,
				Thickness = 1,
				Parent = SliderFrame
			})
			
			local Label = Create("TextLabel", {
				Parent = SliderFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 8),
				Size = UDim2.new(1, -24, 0, 20),
				Font = Enum.Font.GothamMedium,
				Text = SliderName,
				TextColor3 = Theme.TextColor,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local ValueLabel = Create("TextLabel", {
				Parent = SliderFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 8),
				Size = UDim2.new(1, -24, 0, 20),
				Font = Enum.Font.Gotham,
				Text = tostring(Default),
				TextColor3 = Theme.TextSecondary,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Right
			})
			
			local SliderBarBg = Create("Frame", {
				Parent = SliderFrame,
				BackgroundColor3 = Color3.fromRGB(50, 50, 55),
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 12, 0, 38),
				Size = UDim2.new(1, -24, 0, 5)
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Parent = SliderBarBg
			})
			
			local SliderFill = Create("Frame", {
				Parent = SliderBarBg,
				BackgroundColor3 = Theme.Accent,
				BorderSizePixel = 0,
				Size = UDim2.new((Default - Min) / (Max - Min), 0, 1, 0)
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Parent = SliderFill
			})
			
			local SliderKnob = Create("Frame", {
				Parent = SliderBarBg,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				Position = UDim2.new((Default - Min) / (Max - Min), 0, 0.5, 0),
				Size = UDim2.new(0, 14, 0, 14),
				ZIndex = 2
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Parent = SliderKnob
			})
			
			local SliderButton = Create("TextButton", {
				Parent = SliderBarBg,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Text = "",
				ZIndex = 3
			})
			
			local Dragging = false
			
			local function UpdateSlider(Input)
				local SizeX = SliderBarBg.AbsoluteSize.X
				local PosX = SliderBarBg.AbsolutePosition.X
				
				local Percent = math.clamp((Input.Position.X - PosX) / SizeX, 0, 1)
				local Value = math.floor(Min + ((Max - Min) * Percent))
				
				TweenService:Create(SliderFill, TweenInfo.new(0.05), {Size = UDim2.new(Percent, 0, 1, 0)}):Play()
				TweenService:Create(SliderKnob, TweenInfo.new(0.05), {Position = UDim2.new(Percent, 0, 0.5, 0)}):Play()
				ValueLabel.Text = tostring(Value)
				
				-- Save to config
				if ConfigKey then
					ConfigData[ConfigKey] = Value
					saveConfig()
				end
				
				Callback(Value)
			end
			
			SliderButton.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
					Dragging = true
					TweenService:Create(SliderKnob, TweenInfo.new(0.15), {Size = UDim2.new(0, 18, 0, 18)}):Play()
					UpdateSlider(Input)
				end
			end)
			
			table.insert(Connections, UserInputService.InputEnded:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
					Dragging = false
					TweenService:Create(SliderKnob, TweenInfo.new(0.15), {Size = UDim2.new(0, 14, 0, 14)}):Play()
				end
			end))
			
			table.insert(Connections, UserInputService.InputChanged:Connect(function(Input)
				if Dragging and (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
					UpdateSlider(Input)
				end
			end))
			
			local SliderObject = {
				Value = Default
			}
			
			function SliderObject:Set(value)
				-- Type validation: ensure number
				if type(value) ~= "number" then
					value = tonumber(value) or Min
				end
				value = math.clamp(value, Min, Max)
				local percent = (value - Min) / (Max - Min)
				TweenService:Create(SliderFill, TweenInfo.new(0.3), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
				TweenService:Create(SliderKnob, TweenInfo.new(0.3), {Position = UDim2.new(percent, 0, 0.5, 0)}):Play()
				ValueLabel.Text = tostring(value)
				self.Value = value
				
				-- Save to config
				if ConfigKey then
					ConfigData[ConfigKey] = value
					saveConfig()
				end
				
				Callback(value)
			end
			
			-- Register Element
			if ConfigKey then
				Window.Elements[ConfigKey] = {
					Object = SliderObject,
					Type = "Slider"
				}
			end
			
			return SliderObject
		end
		
        function Tab:CreateInput(options)
            options = options or {}
            local InputName = options.Name or "Input"
            local Placeholder = options.Placeholder or InputName
            local Default = options.Default or ""
            local Callback = options.Callback or function() end
            local MultiLine = options.MultiLine or false
            local SideLabel = options.SideLabel
            local Value = options.Value or Default
            local Values = options.Values or {}
            local ConfigKey = options.ConfigKey
            if ConfigKey == nil and InputName ~= "Config Name" then
                ConfigKey = InputName
            end
            
            -- Load saved value if exists
            if ConfigData[ConfigKey] ~= nil then
                Value = ConfigData[ConfigKey]
            end
            
            local InputFrame = Create("Frame", {
                Name = "InputFrame",
                Parent = TabPage,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, MultiLine and 100 or 40)
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 6),
                Parent = InputFrame
            })
            
            Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.5,
                Thickness = 1,
                Parent = InputFrame
            })
            
            if SideLabel then
                local Label = Create("TextLabel", {
                    Parent = InputFrame,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 12, 0, 0),
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Font = Enum.Font.GothamMedium,
                    Text = SideLabel,
                    TextColor3 = Theme.TextColor,
                    TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left
                })
            end
            
            local InputBoxBg = Create("Frame", {
                Parent = InputFrame,
                BackgroundColor3 = Theme.Sidebar,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                Position = SideLabel and UDim2.new(1, -160, 0.5, 0) or UDim2.new(0, 6, 0, 6),
                Size = SideLabel and UDim2.new(0, 150, 0, 28) or UDim2.new(1, -12, 1, -12),
                AnchorPoint = SideLabel and Vector2.new(1, 0.5) or Vector2.new(0, 0)
            })
            
            if SideLabel then
                InputBoxBg.Position = UDim2.new(1, -12, 0.5, 0)
                InputBoxBg.AnchorPoint = Vector2.new(1, 0.5)
            end
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 4),
                Parent = InputBoxBg
            })
            
            local InputStroke = Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.7,
                Thickness = 1,
                Parent = InputBoxBg
            })
            
            local TextBox = Create("TextBox", {
                Parent = InputBoxBg,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 8, 0, MultiLine and 8 or 0),
                Size = UDim2.new(1, -16, 1, MultiLine and -16 or 0),
                Font = Enum.Font.Gotham,
                PlaceholderText = Placeholder,
                Text = Value or Default,
                TextColor3 = Theme.TextColor,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = MultiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
                ClearTextOnFocus = true,
                MultiLine = MultiLine,
                TextWrapped = true
            })
            
            TextBox.Focused:Connect(function()
                TweenService:Create(InputStroke, TweenInfo.new(0.2), {Color = Theme.Accent, Transparency = 0}):Play()
            end)
            
            local InputObject = {
                Value = Value or Default,
                Values = Values
            }

            TextBox.FocusLost:Connect(function(enterPressed)
                TweenService:Create(InputStroke, TweenInfo.new(0.2), {Color = Theme.Outline, Transparency = 0.7}):Play()
                local newValue = TextBox.Text
                InputObject.Value = newValue
                
                -- Save to config
                if ConfigKey then
                    ConfigData[ConfigKey] = newValue
                    saveConfig()
                end
                
                Callback(newValue)
            end)
            
            function InputObject:Set(value)
                -- Type validation: ensure string
                if value == nil then
                    value = ""
                end
                value = tostring(value)
                self.Value = value
                TextBox.Text = tostring(value)
                
                -- Save to config
                if ConfigKey then
                    ConfigData[ConfigKey] = tostring(value)
                    saveConfig()
                end
                
                Callback(tostring(value))
            end
            
            function InputObject:Get()
                return self.Value
            end
            
            if (Value or Default) ~= "" then
                Callback(Value or Default)
            end
            
            -- Register Element
            if ConfigKey then
                Window.Elements[ConfigKey] = {
                    Object = InputObject,
                    Type = "Input"
                }
            end

            return InputObject
        end
		
        function Tab:CreateDropdown(options)
            options = options or {}
            local DropdownName = options.Name or "Dropdown"
            local Items = options.Items or {}
            local Default = options.Default or Items[1]
            local Callback = options.Callback or function() end
            local ConfigKey = options.ConfigKey or DropdownName
            
            -- Load saved value if exists
            if ConfigData[ConfigKey] ~= nil and table.find(Items, ConfigData[ConfigKey]) then
                Default = ConfigData[ConfigKey]
            end
            
            local DropdownFrame = Create("Frame", {
                Name = "DropdownFrame",
                Parent = TabPage,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 38),
                ClipsDescendants = true,
                ZIndex = 2
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 6),
                Parent = DropdownFrame
            })
            
            Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.5,
                Thickness = 1,
                Parent = DropdownFrame
            })
            
            local Label = Create("TextLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -40, 0, 38),
                Font = Enum.Font.GothamMedium,
                Text = DropdownName,
                TextColor3 = Theme.TextColor,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 2
            })
            
            local CurrentValue = Create("TextLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, -35, 0, 38),
                Font = Enum.Font.Gotham,
                Text = Default or "Select...",
                TextColor3 = Theme.TextSecondary,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 2
            })
            
            local Arrow = Create("ImageLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -28, 0, 9),
                Size = UDim2.new(0, 20, 0, 20),
                Image = "rbxassetid://6031091004",
                ImageColor3 = Theme.TextSecondary,
                ZIndex = 2
            })
            
            local Button = Create("TextButton", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 38),
                Text = "",
                ZIndex = 3
            })
            
            local SearchBar = Create("TextBox", {
                Parent = DropdownFrame,
                BackgroundColor3 = Theme.Background,
                BackgroundTransparency = 0.5,
                Position = UDim2.new(0, 6, 0, 42),
                Size = UDim2.new(1, -12, 0, 26),
                Font = Enum.Font.Gotham,
                PlaceholderText = "Search...",
                Text = "",
                TextColor3 = Theme.TextColor,
                PlaceholderColor3 = Theme.TextSecondary,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 3,
                Visible = false
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 4),
                Parent = SearchBar
            })
            
            Create("UIPadding", {
                Parent = SearchBar,
                PaddingLeft = UDim.new(0, 8)
            })

            local DropdownContainer = Create("ScrollingFrame", {
                Parent = DropdownFrame,
                Active = true,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 6, 0, 74),
                Size = UDim2.new(1, -12, 0, 0),
                CanvasSize = UDim2.new(0, 0, 0, 0),
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Accent,
                ZIndex = 3
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 4),
                Parent = DropdownContainer
            })
            
            local ListLayout = Create("UIListLayout", {
                Parent = DropdownContainer,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4)
            })
            
            Create("UIPadding", {
                Parent = DropdownContainer,
                PaddingTop = UDim.new(0, 4),
                PaddingBottom = UDim.new(0, 4),
                PaddingLeft = UDim.new(0, 4),
                PaddingRight = UDim.new(0, 4)
            })
            
            local Open = false
            local ItemButtons = {}
            
            local function UpdateList(filter)
                filter = filter and filter:lower() or ""
                local contentSize = 0
                for _, btn in pairs(ItemButtons) do
                    if btn.Text:lower():find(filter, 1, true) then
                        btn.Visible = true
                        contentSize = contentSize + 28
                    else
                        btn.Visible = false
                    end
                end
                DropdownContainer.CanvasSize = UDim2.new(0, 0, 0, contentSize + 8)
            end

            local function ToggleDropdown()
                Open = not Open
                SearchBar.Visible = Open
                local TargetHeight = Open and math.min(#Items * 28 + 12, 160) or 0
                local FrameHeight = Open and (TargetHeight + 80) or 38
                
                TweenService:Create(DropdownFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, FrameHeight)}):Play()
                TweenService:Create(DropdownContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, -12, 0, TargetHeight)}):Play()
                TweenService:Create(Arrow, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Rotation = Open and 180 or 0}):Play()
                
                if Open then
                    SearchBar:CaptureFocus()
                else
                    SearchBar.Text = ""
                    UpdateList("")
                end
            end
            
            Button.MouseButton1Click:Connect(ToggleDropdown)
            
            SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
                UpdateList(SearchBar.Text)
            end)
            
            local function RefreshItems(newItems)
                Items = newItems or Items
                for _, btn in pairs(ItemButtons) do
                    btn:Destroy()
                end
                ItemButtons = {}
                
                for _, item in pairs(Items) do
                    local ItemButton = Create("TextButton", {
                        Parent = DropdownContainer,
                        BackgroundColor3 = Theme.Background,
                        BackgroundTransparency = 0.5,
                        Size = UDim2.new(1, 0, 0, 24),
                        Font = Enum.Font.Gotham,
                        Text = item,
                        TextColor3 = Theme.TextSecondary,
                        TextSize = 13,
                        ZIndex = 3,
                        AutoButtonColor = false,
                        ClipsDescendants = true
                    })
                    
                    Create("UICorner", {
                        CornerRadius = UDim.new(0, 4),
                        Parent = ItemButton
                    })
                    
                    ItemButton.MouseEnter:Connect(function()
                        TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.5, TextColor3 = Theme.TextColor}):Play()
                    end)
                    
                    ItemButton.MouseLeave:Connect(function()
                        TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.5, TextColor3 = Theme.TextSecondary}):Play()
                    end)
                    
                    ItemButton.MouseButton1Click:Connect(function()
                        task.spawn(function()
                            local Mouse = Players.LocalPlayer:GetMouse()
                            local Ripple = Create("Frame", {
                                Parent = ItemButton,
                                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                                BackgroundTransparency = 0.8,
                                BorderSizePixel = 0,
                                Position = UDim2.new(0, Mouse.X - ItemButton.AbsolutePosition.X, 0, Mouse.Y - ItemButton.AbsolutePosition.Y),
                                Size = UDim2.new(0, 0, 0, 0),
                                ZIndex = 4
                            })
                            
                            Create("UICorner", {
                                CornerRadius = UDim.new(1, 0),
                                Parent = Ripple
                            })

                            local Tween = TweenService:Create(Ripple, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = UDim2.new(0, 100, 0, 100),
                                Position = UDim2.new(0, Mouse.X - ItemButton.AbsolutePosition.X - 50, 0, Mouse.Y - ItemButton.AbsolutePosition.Y - 50),
                                BackgroundTransparency = 1
                            })
                            
                            Tween:Play()
                            Tween.Completed:Wait()
                            Ripple:Destroy()
                        end)
                        
                        CurrentValue.Text = item
                        
                        -- Save to config
                        ConfigData[ConfigKey] = item
                        saveConfig()
                        
                        Callback(item)
                        ToggleDropdown()
                    end)
                    
                    table.insert(ItemButtons, ItemButton)
                end
            end
            
            RefreshItems(Items)
            
            ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                DropdownContainer.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 8)
            end)
            

			local DropdownObject = {
				Items = Items,
				Value = Default
			}
			
			function DropdownObject:Refresh(newItems)
				items = newItems or items
				self.Items = items
				
				if not table.find(items, CurrentValue.Text) then
					CurrentValue.Text = items[1] or "none"
				end

				RefreshItems(items)
			end
			
			function DropdownObject:Set(value)
				-- Type validation: ensure string and exists in Items
				if type(value) ~= "string" then
					value = tostring(value)
				end
				if table.find(self.Items, value) then
					CurrentValue.Text = value
					self.Value = value
					Callback(value)
					
					-- Save to config
					if ConfigKey then
						ConfigData[ConfigKey] = value
						saveConfig()
					end
				end
			end
			
			-- Register Element
			if ConfigKey then
				Window.Elements[ConfigKey] = {
					Object = DropdownObject,
					Type = "Dropdown"
				}
			end
			
			return DropdownObject
        end


		
      function Tab:CreateMultiDropdown(options)
            options = options or {}
            local DropdownName = options.Name or "Multi Dropdown"
            local Items = options.Items or options.Values or {}
            -- Support both 'Default' and 'Value' for backward compatibility
            local Default = options.Default or options.Value or {}
            local Callback = options.Callback or function() end
            local ConfigKey = options.ConfigKey or DropdownName
            
            -- Load saved value if exists
            if ConfigData[ConfigKey] ~= nil and type(ConfigData[ConfigKey]) == "table" then
                Default = ConfigData[ConfigKey]
            end
            
            local Selected = type(Default) == "table" and Default or {}
            
            local DropdownFrame = Create("Frame", {
                Name = "MultiDropdownFrame",
                Parent = TabPage,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 38),
                ClipsDescendants = true,
                ZIndex = 2
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 6),
                Parent = DropdownFrame
            })
            
            Create("UIStroke", {
                Color = Theme.Outline,
                Transparency = 0.5,
                Thickness = 1,
                Parent = DropdownFrame
            })
            
            local Label = Create("TextLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -40, 0, 38),
                Font = Enum.Font.GothamMedium,
                Text = DropdownName,
                TextColor3 = Theme.TextColor,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 2
            })
            
            local function UpdateText()
                if #Selected == 0 then
                    return "None"
                elseif #Selected == 1 then
                    return Selected[1]
                else
                    return #Selected .. " Selected"
                end
            end
            
            local CurrentValue = Create("TextLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, -35, 0, 38),
                Font = Enum.Font.Gotham,
                Text = UpdateText(),
                TextColor3 = Theme.TextSecondary,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 2
            })
            
            local Arrow = Create("ImageLabel", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(1, -28, 0, 9),
                Size = UDim2.new(0, 20, 0, 20),
                Image = "rbxassetid://6031091004",
                ImageColor3 = Theme.TextSecondary,
                ZIndex = 2
            })
            
            local Button = Create("TextButton", {
                Parent = DropdownFrame,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 38),
                Text = "",
                ZIndex = 3
            })
            
            local SearchBar = Create("TextBox", {
                Parent = DropdownFrame,
                BackgroundColor3 = Theme.Background,
                BackgroundTransparency = 0.5,
                Position = UDim2.new(0, 6, 0, 42),
                Size = UDim2.new(1, -12, 0, 26),
                Font = Enum.Font.Gotham,
                PlaceholderText = "Search...",
                Text = "",
                TextColor3 = Theme.TextColor,
                PlaceholderColor3 = Theme.TextSecondary,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 3,
                Visible = false
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 4),
                Parent = SearchBar
            })
            
            Create("UIPadding", {
                Parent = SearchBar,
                PaddingLeft = UDim.new(0, 8)
            })

            local DropdownContainer = Create("ScrollingFrame", {
                Parent = DropdownFrame,
                Active = true,
                BackgroundColor3 = Theme.ElementBackground,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 6, 0, 74),
                Size = UDim2.new(1, -12, 0, 0),
                CanvasSize = UDim2.new(0, 0, 0, 0),
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Theme.Accent,
                ZIndex = 3
            })
            
            Create("UICorner", {
                CornerRadius = UDim.new(0, 4),
                Parent = DropdownContainer
            })
            
            local ListLayout = Create("UIListLayout", {
                Parent = DropdownContainer,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4)
            })
            
            Create("UIPadding", {
                Parent = DropdownContainer,
                PaddingTop = UDim.new(0, 4),
                PaddingBottom = UDim.new(0, 4),
                PaddingLeft = UDim.new(0, 4),
                PaddingRight = UDim.new(0, 4)
            })
            
            local Open = false
            local ItemButtons = {}
            
            local function UpdateList(filter)
                filter = filter and filter:lower() or ""
                local contentSize = 0
                for _, btn in pairs(ItemButtons) do
                    if btn.Text:lower():find(filter, 1, true) then
                        btn.Visible = true
                        contentSize = contentSize + 28
                    else
                        btn.Visible = false
                    end
                end
                DropdownContainer.CanvasSize = UDim2.new(0, 0, 0, contentSize + 8)
            end

            local function ToggleDropdown()
                Open = not Open
                SearchBar.Visible = Open
                local TargetHeight = Open and math.min(#Items * 28 + 12, 160) or 0
                local FrameHeight = Open and (TargetHeight + 80) or 38
                
                TweenService:Create(DropdownFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 0, FrameHeight)}):Play()
                TweenService:Create(DropdownContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(1, -12, 0, TargetHeight)}):Play()
                TweenService:Create(Arrow, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Rotation = Open and 180 or 0}):Play()
                
                if Open then
                    SearchBar:CaptureFocus()
                else
                    SearchBar.Text = ""
                    UpdateList("")
                end
            end
            
            Button.MouseButton1Click:Connect(ToggleDropdown)
            
            SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
                UpdateList(SearchBar.Text)
            end)
            
            local function RefreshItems(newItems)
                Items = newItems or Items
                for _, btn in pairs(ItemButtons) do
                    btn:Destroy()
                end
                ItemButtons = {}
                
                for _, item in pairs(Items) do
                    local IsSelected = table.find(Selected, item)
                    local ItemButton = Create("TextButton", {
                        Parent = DropdownContainer,
                        BackgroundColor3 = IsSelected and Theme.Hover or Theme.Background,
                        BackgroundTransparency = 0.5,
                        Size = UDim2.new(1, 0, 0, 24),
                        Font = Enum.Font.Gotham,
                        Text = item,
                        TextColor3 = IsSelected and Theme.Accent or Theme.TextSecondary,
                        TextSize = 13,
                        ZIndex = 3,
                        AutoButtonColor = false,
                        ClipsDescendants = true
                    })
                    
                    Create("UICorner", {
                        CornerRadius = UDim.new(0, 4),
                        Parent = ItemButton
                    })
                    
                    ItemButton.MouseEnter:Connect(function()
                        if not table.find(Selected, item) then
                            TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.5, TextColor3 = Theme.TextColor}):Play()
                        end
                    end)
                    
                    ItemButton.MouseLeave:Connect(function()
                        if not table.find(Selected, item) then
                            TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.5, TextColor3 = Theme.TextSecondary}):Play()
                        end
                    end)
                    
                    ItemButton.MouseButton1Click:Connect(function()
                        task.spawn(function()
                            local Mouse = Players.LocalPlayer:GetMouse()
                            local Ripple = Create("Frame", {
                                Parent = ItemButton,
                                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                                BackgroundTransparency = 0.8,
                                BorderSizePixel = 0,
                                Position = UDim2.new(0, Mouse.X - ItemButton.AbsolutePosition.X, 0, Mouse.Y - ItemButton.AbsolutePosition.Y),
                                Size = UDim2.new(0, 0, 0, 0),
                                ZIndex = 4
                            })
                            
                            Create("UICorner", {
                                CornerRadius = UDim.new(1, 0),
                                Parent = Ripple
                            })

                            local Tween = TweenService:Create(Ripple, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                                Size = UDim2.new(0, 100, 0, 100),
                                Position = UDim2.new(0, Mouse.X - ItemButton.AbsolutePosition.X - 50, 0, Mouse.Y - ItemButton.AbsolutePosition.Y - 50),
                                BackgroundTransparency = 1
                            })
                            
                            Tween:Play()
                            Tween.Completed:Wait()
                            Ripple:Destroy()
                        end)
                        
                        if table.find(Selected, item) then
                            table.remove(Selected, table.find(Selected, item))
                            TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.5, TextColor3 = Theme.TextSecondary}):Play()
                        else
                            table.insert(Selected, item)
                            TweenService:Create(ItemButton, TweenInfo.new(0.2), {BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.5, TextColor3 = Theme.Accent}):Play()
                        end
                        
                        CurrentValue.Text = UpdateText()
                        
                        -- Save to config
                        ConfigData[ConfigKey] = Selected
                        saveConfig()
                        
                        Callback(Selected)
                    end)
                    
                    table.insert(ItemButtons, ItemButton)
                end
            end
            
            RefreshItems()
            
            ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                DropdownContainer.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 8)
            end)
            
            local MultiDropdownObject = {
                Values = Items,
                Value = Selected
            }
            
            function MultiDropdownObject:Set(values)
                -- Type validation: ensure table
                if type(values) ~= "table" then
                    values = {}
                end
                Selected = values
                CurrentValue.Text = UpdateText()
                
                -- Save to config
                ConfigData[ConfigKey] = Selected
                saveConfig()
                
                Callback(Selected)

            end
            
            function MultiDropdownObject:Get()
                return Selected
            end
            
            function MultiDropdownObject:Refresh(newItems)
                RefreshItems(newItems)
            end
            
            -- Register Element
            if ConfigKey then
                Window.Elements[ConfigKey] = {
                    Object = MultiDropdownObject,
                    Type = "MultiDropdown"
                }
            end

            return MultiDropdownObject
        end

		
		function Tab:CreateColorPicker(options)
			options = options or {}
			local Name = options.Name or "Color Picker"
			local Default = options.Default or Color3.fromRGB(255, 255, 255)
			local Callback = options.Callback or function() end
			
			local ColorH, ColorS, ColorV = Default:ToHSV()
			local ColorVal = Default
			local Open = false
			
			local PickerFrame = Create("Frame", {
				Name = "PickerFrame",
				Parent = TabPage,
				BackgroundColor3 = Theme.ElementBackground,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 38),
				ClipsDescendants = true
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 6),
				Parent = PickerFrame
			})
			
			Create("UIStroke", {
				Color = Theme.Outline,
				Transparency = 0.5,
				Thickness = 1,
				Parent = PickerFrame
			})
			
			local Label = Create("TextLabel", {
				Parent = PickerFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -60, 0, 38),
				Font = Enum.Font.GothamMedium,
				Text = Name,
				TextColor3 = Theme.TextColor,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local Preview = Create("Frame", {
				Parent = PickerFrame,
				BackgroundColor3 = Default,
				Position = UDim2.new(1, -40, 0, 9),
				Size = UDim2.new(0, 28, 0, 20)
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 4),
				Parent = Preview
			})
			
			local Button = Create("TextButton", {
				Parent = PickerFrame,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 38),
				Text = ""
			})
			
			local PickerContainer = Create("Frame", {
				Parent = PickerFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 42),
				Size = UDim2.new(1, -24, 0, 160),
				Visible = true
			})
			
			
			local SVBox = Create("ImageButton", {
				Parent = PickerContainer,
				BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1, 0, 0, 120),
				Image = "rbxassetid://4155801252",
				AutoButtonColor = false
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 4),
				Parent = SVBox
			})
			
			local SVCursor = Create("Frame", {
				Parent = SVBox,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(ColorS, -3, 1 - ColorV, -3),
				Size = UDim2.new(0, 6, 0, 6),
				ZIndex = 2
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Parent = SVCursor
			})
			
			Create("UIStroke", {
				Color = Color3.new(0, 0, 0),
				Thickness = 1,
				Parent = SVCursor
			})
			
			
			local HueBar = Create("ImageButton", {
				Parent = PickerContainer,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 1, -24),
				Size = UDim2.new(1, 0, 0, 20),
				AutoButtonColor = false
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 4),
				Parent = HueBar
			})
			
			Create("UIGradient", {
				Parent = HueBar,
				Rotation = 0,
				Color = ColorSequence.new{
					ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
					ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
					ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
					ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
					ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
					ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
				}
			})
			
			local HueCursor = Create("Frame", {
				Parent = HueBar,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.new(ColorH, -3, 0, -2),
				Size = UDim2.new(0, 6, 1, 4),
				ZIndex = 2
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 2),
				Parent = HueCursor
			})
			
			Create("UIStroke", {
				Color = Color3.new(0, 0, 0),
				Thickness = 1,
				Parent = HueCursor
			})
			
			
			local function UpdateColor()
				ColorVal = Color3.fromHSV(ColorH, ColorS, ColorV)
				Preview.BackgroundColor3 = ColorVal
				SVBox.BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1)
				Callback(ColorVal)
			end
			
			local DraggingSV = false
			local DraggingHue = false
			
			SVBox.MouseButton1Down:Connect(function()
				DraggingSV = true
			end)
			
			HueBar.MouseButton1Down:Connect(function()
				DraggingHue = true
			end)
			
			table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					DraggingSV = false
					DraggingHue = false
				end
			end))
			
			table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement then
					if DraggingSV then
						local rX = math.clamp((input.Position.X - SVBox.AbsolutePosition.X) / SVBox.AbsoluteSize.X, 0, 1)
						local rY = math.clamp((input.Position.Y - SVBox.AbsolutePosition.Y) / SVBox.AbsoluteSize.Y, 0, 1)
						
						ColorS = rX
						ColorV = 1 - rY
						
						SVCursor.Position = UDim2.new(ColorS, -3, 1 - ColorV, -3)
						UpdateColor()
					elseif DraggingHue then
						local rX = math.clamp((input.Position.X - HueBar.AbsolutePosition.X) / HueBar.AbsoluteSize.X, 0, 1)
						
						ColorH = rX
						HueCursor.Position = UDim2.new(ColorH, -3, 0, -2)
						UpdateColor()
					end
				end
			end))
			
			Button.MouseButton1Click:Connect(function()
				Open = not Open
				TweenService:Create(PickerFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {Size = UDim2.new(1, 0, 0, Open and 200 or 38)}):Play()
			end)
		end

		function Tab:CreateKeybind(options)
			options = options or {}
			local KeybindName = options.Name or "Keybind"
			local Default = options.Default or Enum.KeyCode.RightControl
			local Callback = options.Callback or function() end
			
			local KeybindFrame = Create("Frame", {
				Name = "KeybindFrame",
				Parent = TabPage,
				BackgroundColor3 = Theme.ElementBackground,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 38)
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 6),
				Parent = KeybindFrame
			})
			
			Create("UIStroke", {
				Color = Theme.Outline,
				Transparency = 0.5,
				Thickness = 1,
				Parent = KeybindFrame
			})
			
			local Label = Create("TextLabel", {
				Parent = KeybindFrame,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -60, 1, 0),
				Font = Enum.Font.GothamMedium,
				Text = KeybindName,
				TextColor3 = Theme.TextColor,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local KeybindButton = Create("TextButton", {
				Parent = KeybindFrame,
				BackgroundColor3 = Theme.Background,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -95, 0.5, -12),
				Size = UDim2.new(0, 85, 0, 24),
				Font = Enum.Font.Gotham,
				Text = Default.Name,
				TextColor3 = Theme.TextSecondary,
				TextSize = 13,
				ClipsDescendants = true
			})
			
			Create("UICorner", {
				CornerRadius = UDim.new(0, 4),
				Parent = KeybindButton
			})
			
			Create("UIStroke", {
				Color = Theme.Outline,
				Transparency = 0.7,
				Thickness = 1,
				Parent = KeybindButton
			})
			
			local Binding = false
			
			KeybindButton.MouseButton1Click:Connect(function()
				
				task.spawn(function()
					local Mouse = Players.LocalPlayer:GetMouse()
					local Ripple = Create("Frame", {
						Parent = KeybindButton,
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BackgroundTransparency = 0.8,
						BorderSizePixel = 0,
						Position = UDim2.new(0, Mouse.X - KeybindButton.AbsolutePosition.X, 0, Mouse.Y - KeybindButton.AbsolutePosition.Y),
						Size = UDim2.new(0, 0, 0, 0),
						ZIndex = 2
					})
					
					Create("UICorner", {
						CornerRadius = UDim.new(1, 0),
						Parent = Ripple
					})

					local Tween = TweenService:Create(Ripple, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = UDim2.new(0, 100, 0, 100),
						Position = UDim2.new(0, Mouse.X - KeybindButton.AbsolutePosition.X - 50, 0, Mouse.Y - KeybindButton.AbsolutePosition.Y - 50),
						BackgroundTransparency = 1
					})
					
					Tween:Play()
					Tween.Completed:Wait()
					Ripple:Destroy()
				end)

				Binding = true
				KeybindButton.Text = "..."
				TweenService:Create(KeybindButton, TweenInfo.new(0.2), {TextColor3 = Theme.Accent}):Play()
			end)
			
			table.insert(Connections, UserInputService.InputBegan:Connect(function(Input)
				if Binding then
					if Input.UserInputType == Enum.UserInputType.Keyboard then
						Default = Input.KeyCode
						KeybindButton.Text = Default.Name
						Binding = false
						TweenService:Create(KeybindButton, TweenInfo.new(0.2), {TextColor3 = Theme.TextSecondary}):Play()
						Callback(Default)
					elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
						Binding = false
						KeybindButton.Text = Default.Name
						TweenService:Create(KeybindButton, TweenInfo.new(0.2), {TextColor3 = Theme.TextSecondary}):Play()
					end
				else
					if Input.KeyCode == Default then
						Callback(Default)
					end
				end
			end))
		end

		return Tab
	end

	function Window:Destroy()
		ScreenGui:Destroy()
		for _, connection in pairs(Connections) do
			connection:Disconnect()
		end
		Connections = {}
	end

	return Window
end

function VoraLib:Destroy()
	for _, connection in pairs(Connections) do
		connection:Disconnect()
	end
	Connections = {}
	
	if RunService:IsStudio() then
		local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("VoraHub")
		if gui then gui:Destroy() end
	else
		local gui = CoreGui:FindFirstChild("VoraHub")
		if gui then gui:Destroy() end
	end
end


local Window = VoraLib:CreateWindow({
	Name = "Vora Hub",
	Intro = true
})

Window:Notify({
    Title = "Vora Hub",
    Content = "UI Successfully Loaded!",
    Duration = 5,
})


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

-- ScreenGui di CoreGui (tembus semua UI Roblox)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FPSPingHUD_SmallText"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = CoreGui

-- Frame utama
local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.new(0, 200, 0, 35)           -- Tetap 200px lebar
frame.Position = UDim2.new(0, 10, 0, 50)        -- Kiri atas, agak ke bawah
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BackgroundTransparency = 0.55
frame.BorderSizePixel = 0
frame.ZIndex = 10
frame.Parent = screenGui

-- Sangat bulat
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 18)
corner.Parent = frame

-- FPS Label - teks lebih kecil
local fpsLabel = Instance.new("TextLabel")
fpsLabel.Size = UDim2.new(0.5, -5, 1, 0)
fpsLabel.Position = UDim2.new(0, 15, 0, 0)
fpsLabel.BackgroundTransparency = 1
fpsLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
fpsLabel.TextScaled = false                  -- Matikan TextScaled
fpsLabel.TextSize = 16                       -- Teks kecil (sebelumnya ~20-24 otomatis)
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
fpsLabel.Text = "FPS: --"
fpsLabel.ZIndex = 10
fpsLabel.Parent = frame

-- Ping Label - teks lebih kecil
local pingLabel = Instance.new("TextLabel")
pingLabel.Size = UDim2.new(0.5, -5, 1, 0)
pingLabel.Position = UDim2.new(0.5, 0, 0, 0)
pingLabel.BackgroundTransparency = 1
pingLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
pingLabel.TextScaled = false                 -- Matikan TextScaled
pingLabel.TextSize = 16                      -- Teks kecil
pingLabel.Font = Enum.Font.GothamBold
pingLabel.TextXAlignment = Enum.TextXAlignment.Right
pingLabel.Text = "Ping: --"
pingLabel.ZIndex = 10
pingLabel.Parent = frame

-- Hitung FPS
local lastTime = tick()
local frameCount = 0

RunService.RenderStepped:Connect(function()
    frameCount += 1
end)

-- Update loop
spawn(function()
    while true do
        local currentTime = tick()
        local delta = currentTime - lastTime
        
        if delta >= 1 then
            local fps = math.floor(frameCount / delta + 0.5)
            fpsLabel.Text = "FPS: " .. fps
            
            local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
            pingLabel.Text = "Ping: " .. math.floor(ping) .. " ms"
            
            -- Warna ping
            if ping < 60 then
                pingLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            elseif ping < 120 then
                pingLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
            else
                pingLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
            
            frameCount = 0
            lastTime = currentTime
        end
        
        wait(0.1)
    end
end)

local InfoTab = Window:CreateTab({
	Name = "Info",
	Icon = "rbxassetid://7733964719"
})

local ExclusiveTab = Window:CreateTab({
	Name = "Exclusive",
	Icon = "rbxassetid://7733765398"
})

local MainTab = Window:CreateTab({
	Name = "Main",
	Icon = "rbxassetid://7733779610"
})

local AutoTab = Window:CreateTab({
	Name = "Auto",
	Icon = "rbxassetid://7733799901"
})

local PlayerTab = Window:CreateTab({
	Name = "Player",
	Icon = "rbxassetid://7743875962"
})

local ShopTab = Window:CreateTab({
	Name = "Shop",
	Icon = "rbxassetid://7733793319"
})

local TeleportTab = Window:CreateTab({
	Name = "Teleport",
	Icon = "rbxassetid://128755575520135"
})

local SettingsTab = Window:CreateTab({
	Name = "Settings",
	Icon = "rbxassetid://7733954611"
})

local ConfigTab = Window:CreateTab({
	Name = "Config",
	Icon = "rbxassetid://7734053426"
})


InfoTab:CreateSection({ Name = "Community Support" })

InfoTab:CreateButton({
	Name = "Discord",
	SubText = "click to copy link",
	Icon = "rbxassetid://7733919427", 
	Callback = function()
		setclipboard("https://discord.gg/vorahub")
		Window:Notify({
			Title = "Discord",
			Content = "Link copied to clipboard!",
			Duration = 3
		})
	end
})

InfoTab:CreateParagraph({
	Title = "Update",
	Content = "Every time there is a game update or someone reports something, I will fix it as soon as possible."
})

getgenv().host = game:GetService("Players").LocalPlayer

 function applyZoom()
    host.CameraMaxZoomDistance = math.huge
    host.CameraMinZoomDistance = 0.1
end

applyZoom()

host.CharacterAdded:Connect(function()
    task.wait(0.1)
    applyZoom()
end)

ReplicatedStorage = game:GetService("ReplicatedStorage")
RunService = game:GetService("RunService")
Net = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net
Replion = require(ReplicatedStorage.Packages.Replion)
FishingController = require(ReplicatedStorage.Controllers.FishingController)
ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
VendorUtility = require(ReplicatedStorage.Shared.VendorUtility)
Data = Replion.Client:WaitReplion("Data")
Client = require(ReplicatedStorage.Packages.Replion).Client
dataStore = Client:WaitReplion("Data")
Items = ReplicatedStorage:WaitForChild("Items")
Players = game:GetService("Players")
LocalPlayer = Players.LocalPlayer
NetService = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
sellAllItems = NetService:WaitForChild("RF/SellAllItems")
enchan = NetService:WaitForChild("RE/ActivateEnchantingAltar")
oxygenRemote = NetService:WaitForChild("URE/UpdateOxygen")
radar = NetService:WaitForChild("RF/UpdateFishingRadar")
autoon = NetService:WaitForChild("RF/UpdateAutoFishingState")
equipTool = NetService:WaitForChild("RE/EquipToolFromHotbar")
CoreGui = game:GetService("CoreGui")
tradeFunc = Net["RF/InitiateTrade"]
RETextNotification = Net["RE/TextNotification"]
ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
TradingController = require(ReplicatedStorage.Controllers.ItemTradingController)

RE = {
    FavoriteItem = Net:FindFirstChild("RE/FavoriteItem"),
    FavoriteStateChanged = Net:FindFirstChild("RE/FavoriteStateChanged"),
    FishingCompleted = Net:FindFirstChild("RE/FishingCompleted"),
    FishCaught = Net:FindFirstChild("RE/FishCaught"),
    EquipItem = Net:FindFirstChild("RE/EquipItem"),
    ActivateAltar = Net:FindFirstChild("RE/ActivateEnchantingAltar"),
    EquipTool = Net:FindFirstChild("RE/EquipToolFromHotbar"),
    OpenPirateChest = Net:FindFirstChild("RE/ClaimPirateChest")
}

equipItemRemote = RE.EquipItem or Net:FindFirstChild("RE/EquipItem")
equipToolRemote = RE.EquipTool or Net:FindFirstChild("RE/EquipToolFromHotbar")
activateAltarRemote = RE.ActivateAltar or Net:FindFirstChild("RE/ActivateEnchantingAltar")

st = {
    canFish = true,
}

blockedFunctions = {
    "OnCooldown",
}

function patchFishingController()
     fishingModule = ReplicatedStorage.Controllers:FindFirstChild("FishingController")
    if not fishingModule then return end

     ok, FC = pcall(require, fishingModule)
    if not ok or type(FC) ~= "table" then return end

    for key, fn in pairs(FC) do
        if type(fn) == "function" and table.find(blockedFunctions, key) then
            FC[key] = function(...)
                return false
            end
        end
    end

end

patchFishingController()
------------------ Variable ------------------------
_G.AutoFarm = false
_G.AutoRod = false
_G.AutoSells = false
_G.InfiniteJump = false
_G.Radar = false
_G.AntiAFK = false
_G.AutoReconnect = false
autoFavEnabled = false

------------------ Fishing logic -------------------]

function instant()
    NetService:WaitForChild("RF/ChargeFishingRod"):InvokeServer(1)
    task.wait(0.2)
    NetService:WaitForChild("RF/RequestFishingMinigameStarted"):InvokeServer(1, 0.921, 17819.019)
    task.wait(delayfishing)
    NetService:WaitForChild("RE/FishingCompleted"):FireServer(1)
end


local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = game.Players.LocalPlayer
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
local REFishCaught = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RE/FishCaught"]

_G.Wurl = _G.Wurl or ""
_G.WebhookEnabled = _G.WebhookEnabled or false

local req = (syn and syn.request) or (http and http.request) or http_request or request

local function isValidWebhookURL(url)
    return string.find(url, "discord%.com") and string.find(url, "webhook")
end

ExclusiveTab:CreateSection({ Name = "Premium" })

local stopAnimConnections = {}
local function setAnim(v)
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    for _, c in ipairs(stopAnimConnections) do c:Disconnect() end
    stopAnimConnections = {}

    if v then
        for _, t in ipairs(hum:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks()) do
            t:Stop(0)
        end
        local c = hum:FindFirstChildOfClass("Animator").AnimationPlayed:Connect(function(t)
            task.defer(function() t:Stop(0) end)
        end)
        table.insert(stopAnimConnections, c)
    else
        for _, c in ipairs(stopAnimConnections) do c:Disconnect() end
        stopAnimConnections = {}
    end
end

ExclusiveTab:CreateToggle({
	Name = "No Animation",
    Value = false,
    Callback = setAnim
})

-- // TOTEM DATA
local TOTEM_DATA = {
    ["Luck Totem"] = {Id = 1, Duration = 3601},
    ["Mutation Totem"] = {Id = 2, Duration = 3601},
    ["Shiny Totem"] = {Id = 3, Duration = 3601}
}
local TOTEM_NAMES = {"Luck Totem", "Mutation Totem", "Shiny Totem"}
local selectedTotemName = "Luck Totem"

-- // AUTO SINGLE TOTEM
local AUTO_TOTEM_ACTIVE = false
local AUTO_TOTEM_THREAD = nil
local currentTotemExpiry = 0

-- // AUTO 9 TOTEM
local AUTO_9_TOTEM_ACTIVE = false
local AUTO_9_TOTEM_THREAD = nil
local stateConnection = nil
local noclipThread = nil

-- // REFERENCE POSITIONS (DIBUAT LEBIH JAUH & VARIATIF)
local REF_CENTER = Vector3.new(93.932, 9.532, 2684.134)
local REF_SPOTS = {
    Vector3.new(45.0468979, 9.51625347, 2730.19067),   -- 1
    Vector3.new(145.644608, 9.51625347, 2721.90747),   -- 2
    Vector3.new(84.6406631, 10.2174253, 2636.05786),   -- 3
    Vector3.new(45.0468979, 110.516253, 2730.19067),   -- 4
    Vector3.new(145.644608, 110.516253, 2721.90747),   -- 5
    Vector3.new(84.6406631, 111.217425, 2636.05786),   -- 6
    Vector3.new(45.0468979, -92.483747, 2730.19067),   -- 7
    Vector3.new(145.644608, -92.483747, 2721.90747),   -- 8
    Vector3.new(84.6406631, -93.782575, 2636.05786),   -- 9
}

-- // GET FLY PART
local function GetFlyPart()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

-- // ANTI-FALL STATE MANAGER
local function MaintainAntiFallState(enable)
    local char = player.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if not hum then return end
    if enable then
        hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

        if not stateConnection then
            stateConnection = RunService.Heartbeat:Connect(function()
                if hum and AUTO_9_TOTEM_ACTIVE then
                    hum:ChangeState(Enum.HumanoidStateType.Swimming)
                    hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
                    task.wait(0.1) -- Add delay to prevent CPU spike
                end
            end)
        end
    else
        if stateConnection then stateConnection:Disconnect(); stateConnection = nil end
        
        hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
        
        hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
    end
end

-- // ENABLE V3 PHYSICS
local function EnableV3Physics()
    local char = player.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local mainPart = GetFlyPart()
    
    if not mainPart or not hum then return end
    
    if char:FindFirstChild("Animate") then char.Animate.Disabled = true end
    hum.PlatformStand = true 
    
    MaintainAntiFallState(true)
    
    local bg = mainPart:FindFirstChild("FlyGuiGyro") or Instance.new("BodyGyro", mainPart)
    bg.Name = "FlyGuiGyro"
    bg.P = 9e4 
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.CFrame = mainPart.CFrame
    
    local bv = mainPart:FindFirstChild("FlyGuiVelocity") or Instance.new("BodyVelocity", mainPart)
    bv.Name = "FlyGuiVelocity"
    bv.Velocity = Vector3.new(0, 0.1, 0)
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    
    if noclipThread then task.cancel(noclipThread) end
    noclipThread = task.spawn(function()
        while AUTO_9_TOTEM_ACTIVE and char and char.Parent do
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = false end
            end
            task.wait(0.5) -- Increased from 0.1 to 0.5 to reduce CPU usage
        end
    end)
end

-- // DISABLE V3 PHYSICS (LANDING & TOGGLE OFF AMAN TOTAL)
local function DisableV3Physics()
    AUTO_9_TOTEM_ACTIVE = false
    
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    local mainPart = GetFlyPart()
    
    if mainPart then
        pcall(function()
            if mainPart:FindFirstChild("FlyGuiGyro") then mainPart.FlyGuiGyro:Destroy() end
            if mainPart:FindFirstChild("FlyGuiVelocity") then mainPart.FlyGuiVelocity:Destroy() end
        end)
        
        pcall(function()
            mainPart.Velocity = Vector3.zero
            mainPart.RotVelocity = Vector3.zero
            mainPart.AssemblyLinearVelocity = Vector3.zero 
            mainPart.AssemblyAngularVelocity = Vector3.zero
        end)
        
        local _, y, _ = mainPart.CFrame:ToEulerAnglesYXZ()
        mainPart.CFrame = CFrame.new(mainPart.Position) * CFrame.fromEulerAnglesYXZ(0, y, 0)
        
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {char}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        local result = workspace:Raycast(mainPart.Position, Vector3.new(0, -10, 0), params)
        if result then
            mainPart.CFrame = mainPart.CFrame + Vector3.new(0, 6, 0)
        end
    end
    
    if hum then 
        hum.PlatformStand = false 
        task.wait(0.1)
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.2)
        hum:ChangeState(Enum.HumanoidStateType.Running)
        task.wait(0.1)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    
    MaintainAntiFallState(false) 
    
    if char:FindFirstChild("Animate") then char.Animate.Disabled = false end
    
    task.delay(0.5, function()
        if char and char.Parent then
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then v.CanCollide = true end
            end
        end
    end)
    
    if noclipThread then task.cancel(noclipThread) noclipThread = nil end
end

-- // FLY TO TARGET
local function FlyPhysicsTo(targetPos)
    local mainPart = GetFlyPart()
    if not mainPart then return end
    
    local bv = mainPart:FindFirstChild("FlyGuiVelocity")
    local bg = mainPart:FindFirstChild("FlyGuiGyro")
    if not bv or not bg then EnableV3Physics(); task.wait(0.2); bv = mainPart.FlyGuiVelocity; bg = mainPart.FlyGuiGyro end
    local SPEED = 80 
    
    while AUTO_9_TOTEM_ACTIVE and mainPart.Parent do
        local currentPos = mainPart.Position
        local diff = targetPos - currentPos
        local dist = diff.Magnitude
        
        bg.CFrame = CFrame.lookAt(currentPos, targetPos)
        if dist < 1.5 then 
            bv.Velocity = Vector3.new(0, 0.1, 0)
            break
        else
            bv.Velocity = diff.Unit * SPEED
        end
        task.wait() -- Changed from RunService.Heartbeat:Wait() to task.wait() for better performance
    end
end

-- // GET TOTEM UUID
local function GetTotemUUID(name)
    local success, r = pcall(function()
        return require(ReplicatedStorage.Packages.Replion).Client:WaitReplion("Data")
    end)
    if not success then return nil end
    local s, d = pcall(function() return r:GetExpect("Inventory") end)
    if s and d.Totems then 
        for _, i in ipairs(d.Totems) do 
            if tonumber(i.Id) == TOTEM_DATA[name].Id and (i.Count or 1) >= 1 then return i.UUID end 
        end 
    end
    return nil
end

-- // OXYGEN REMOTE
local RF_EquipOxygenTank = Net["RF/EquipOxygenTank"]
local RF_UnequipOxygenTank = Net["RF/UnequipOxygenTank"]

-- // 9 TOTEM LOOP
local function Run9TotemLoop()
    if AUTO_9_TOTEM_THREAD then task.cancel(AUTO_9_TOTEM_THREAD) end
    
    AUTO_9_TOTEM_THREAD = task.spawn(function()
        AUTO_9_TOTEM_ACTIVE = true
        
        local char = player.Character or player.CharacterAdded:Wait()
        local mainPart = GetFlyPart()
        local hum = char:FindFirstChild("Humanoid")
        if not mainPart then 
            AUTO_9_TOTEM_ACTIVE = false
            return 
        end
        
        local uuid = GetTotemUUID(selectedTotemName)
        if not uuid then 
            Window:Notify({ Title = "No Stock", Content = "Isi inventory dulu!", Duration = 4, Icon = "x" })
            AUTO_9_TOTEM_ACTIVE = false
            local t = Exclusive:GetElementByTitle("Auto Spawn 9 Totem")
            if t then t:Set(false) end
            return 
        end
        
        local myStartPos = mainPart.Position 
        Window:Notify({ Title = "Started", Content = "V3 Engine + Oxygen Protection!", Duration = 4, Icon = "zap" })
        
        if RF_EquipOxygenTank then pcall(function() RF_EquipOxygenTank:InvokeServer(105) end) end
        
        if hum then hum.Health = hum.MaxHealth end
        
        EnableV3Physics()
        
        for _, refSpot in ipairs(REF_SPOTS) do
            if not AUTO_9_TOTEM_ACTIVE then break end
            
            local relativePos = refSpot - REF_CENTER
            local targetPos = myStartPos + relativePos
            
            FlyPhysicsTo(targetPos) 
            
            task.wait(1.2)
            
            uuid = GetTotemUUID(selectedTotemName)
            if uuid then
                pcall(function() Net["RE/SpawnTotem"]:FireServer(uuid) end)
                
                task.spawn(function() 
                    for k=1,3 do
                        pcall(function() Net["RE/EquipToolFromHotbar"]:FireServer(1) end)
                        task.wait(0.25) 
                    end 
                end)
            else
                break
            end
            
            task.wait(2.5) 
        end
        
        if AUTO_9_TOTEM_ACTIVE then
            FlyPhysicsTo(myStartPos)
            task.wait(1.2)  -- Tunggu lebih lama biar landing perfect
            Window:Notify({ Title = "Selesai", Content = "Landing aman total!", Duration = 5, Icon = "check" })
        end
        
        if RF_UnequipOxygenTank then pcall(function() RF_UnequipOxygenTank:InvokeServer() end) end
        
        DisableV3Physics()
        
        local t = Exclusive:GetElementByTitle("Auto Spawn 9 Totem")
        if t then t:Set(false) end
    end)
end

-- // AUTO SINGLE TOTEM
local function RunAutoTotemLoop()
    if AUTO_TOTEM_THREAD then task.cancel(AUTO_TOTEM_THREAD) end
    AUTO_TOTEM_THREAD = task.spawn(function()
        while AUTO_TOTEM_ACTIVE do
            local timeLeft = currentTotemExpiry - os.time()
            if timeLeft <= 0 then
                local uuid = GetTotemUUID(selectedTotemName)
                if uuid then
                    pcall(function() Net["RE/SpawnTotem"]:FireServer(uuid) end)
                    currentTotemExpiry = os.time() + TOTEM_DATA[selectedTotemName].Duration
                    task.spawn(function() 
                        for i=1,4 do task.wait(0.2) pcall(function() Net["RE/EquipToolFromHotbar"]:FireServer(1) end) end 
                    end)
                end
            end
            task.wait(1)
        end
    end)
end

ExclusiveTab:CreateDropdown({
	Name = "Pilih Jenis Totem",
Items = {"Luck Totem", "Mutation Totem", "Shiny Totem"},
    Value = selectedTotemName,
 Callback = function(n) 
        selectedTotemName = n
        currentTotemExpiry = 0 
    end 
})

ExclusiveTab:CreateToggle({
	Name = "Enable Auto Totem (Single)",
	SubText = "Mode Normal",
	Default = false,
	 Callback = function(s) 
        AUTO_TOTEM_ACTIVE = s
        if s then RunAutoTotemLoop() else if AUTO_TOTEM_THREAD then task.cancel(AUTO_TOTEM_THREAD) end end 
    end 
})

ExclusiveTab:CreateToggle({
	Name = "Auto Spawn 9 Totem",
	Default = false,
    Callback = function(s)
        AUTO_9_TOTEM_ACTIVE = s
        if s then
            Run9TotemLoop()
        else
            AUTO_9_TOTEM_ACTIVE = false
            DisableV3Physics()
            if AUTO_9_TOTEM_THREAD then task.cancel(AUTO_9_TOTEM_THREAD) end
            Window:Notify({ Title = "Stopped", Content = "Dihentikan & karakter normal!", Duration = 5, Icon = "x" })
        end
    end
})

ExclusiveTab:CreateSection({ Name = "Extreme FPS Boost" })


        -- Data penyimpanan untuk restore (Moved outside scope to persist)
        local restore = {
            lighting = {},
            terrain = {},
            objects = {},        -- instance -> data
            connection = nil
        }

        function saveLighting()
            if next(restore.lighting) == nil then
                restore.lighting = {
                    GlobalShadows = Lighting.GlobalShadows,
                    FogEnd = Lighting.FogEnd,
                    Brightness = Lighting.Brightness,
                    Ambient = Lighting.Ambient,
                    OutdoorAmbient = Lighting.OutdoorAmbient,
                    ColorShift_Top = Lighting.ColorShift_Top,
                    ColorShift_Bottom = Lighting.ColorShift_Bottom,
                    ShadowSoftness = Lighting.ShadowSoftness,
                    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
                    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
                    ClockTime = Lighting.ClockTime,
                    GeographicLatitude = Lighting.GeographicLatitude,
                }
            end
        end

        function saveTerrain()
            if Terrain and next(restore.terrain) == nil then
                restore.terrain = {
                    WaterTransparency = Terrain.WaterTransparency,
                    WaterReflectance = Terrain.WaterReflectance,
                    WaterWaveSize = Terrain.WaterWaveSize,
                    WaterWaveSpeed = Terrain.WaterWaveSpeed,
                }
            end
        end

        function optimizePart(part)
            if part:IsA("BasePart") and not restore.objects[part] then
                restore.objects[part] = {
                    Material = part.Material,
                    Reflectance = part.Reflectance,
                    CastShadow = part.CastShadow,
                    Transparency = part.Transparency,
                    CanCollide = part.CanCollide, -- penting untuk gameplay
                }

                part.Material = Enum.Material.SmoothPlastic
                part.Reflectance = 0
                part.CastShadow = false

                -- Hapus Decal/Texture/SurfaceAppearance (berat banget)
                for _, child in pairs(part:GetChildren()) do
                    if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                        if not restore.objects[child] then
                            restore.objects[child] = { Parent = child.Parent }
                        end
                        child.Parent = nil -- Sembunyikan (bisa di-restore), jangan Destroy!
                    end
                end
            end
        end

        function disableAllEffects(instance)
            local class = instance.ClassName
            if class == "ParticleEmitter" or class == "Trail" or class == "Beam" 
                or class == "Smoke" or class == "Fire" or class == "Sparkles" 
                or class == "Light" or class == "SurfaceLight" or class == "PointLight" or class == "SpotLight" then
                
                if not restore.objects[instance] then
                    restore.objects[instance] = { Enabled = instance.Enabled }
                end
                instance.Enabled = false
            end
        end

        local function extremeLowGraphics()
            -- Lighting super minimal
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
            Lighting.FogStart = 0
            Lighting.Brightness = 2
            Lighting.ClockTime = 12
            Lighting.GeographicLatitude = 0
            Lighting.ShadowSoftness = 0
            Lighting.EnvironmentDiffuseScale = 0
            Lighting.EnvironmentSpecularScale = 0
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)

            -- Hapus post-processing effects
            for _, effect in pairs(Lighting:GetChildren()) do
                if effect:IsA("PostEffect") then
                    if not restore.objects[effect] then
                        restore.objects[effect] = { Enabled = effect.Enabled }
                    end
                    effect.Enabled = false
                end
            end

            -- Terrain minimal
            if Terrain then
                Terrain.WaterTransparency = 1
                Terrain.WaterReflectance = 0
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
            end
        end

        function processAll()
            -- Process in batches to prevent CPU spike
            local descendants = workspace:GetDescendants()
            local batchSize = 50 -- Process 50 objects at a time
            local count = 0
            
            for _, obj in ipairs(descendants) do
                if obj:IsA("BasePart") then
                    optimizePart(obj)
                else
                    disableAllEffects(obj)
                end
                
                count = count + 1
                -- Yield every batch to prevent frame drops
                if count % batchSize == 0 then
                    task.wait()
                end
            end
        end

        function restoreEverything()
            -- Restore Lighting
            for prop, val in pairs(restore.lighting) do
                pcall(function() Lighting[prop] = val end)
            end

            -- Restore Terrain
            if Terrain then
                for prop, val in pairs(restore.terrain) do
                    pcall(function() Terrain[prop] = val end)
                end
            end

            -- Restore objects
            for obj, data in pairs(restore.objects) do
                if obj then
                    for prop, val in pairs(data) do
                        pcall(function() obj[prop] = val end)
                    end
                end
            end

            restore.objects = {}
        end

        ExclusiveTab:CreateToggle({
            Name = "Extreme FPS Boost",
            SubText = "Maksimalkan FPS dengan mengorbankan hampir semua efek visual",
            Default = false,
             Callback = function(enabled)
                if enabled then
                    saveLighting()
                    saveTerrain()
                    extremeLowGraphics()
                    processAll()
        
                    -- Monitor objek baru (penting untuk map dinamis)
                    if restore.connection then restore.connection:Disconnect() end
                    restore.connection = workspace.DescendantAdded:Connect(function(desc)
                        task.spawn(function()
                            if desc:IsA("BasePart") then
                                optimizePart(desc)
                            else
                                disableAllEffects(desc)
                            end
                        end)
                    end)
        
                else
                    if restore.connection then
                        restore.connection:Disconnect()
                        restore.connection = nil
                    end
                    restoreEverything()
                end
            end
        })

local freezeConnection
local originalCFrame

ExclusiveTab:CreateToggle({
	Name = "Freeze Character",
	Default = false,
	 Callback = function(state)
        _G.FreezeCharacter = state
        if state then
            local character = game.Players.LocalPlayer.Character
            if character then
                local root = character:FindFirstChild("HumanoidRootPart")
                if root then
                    originalCFrame = root.CFrame
                    freezeConnection = game:GetService("RunService").Heartbeat:Connect(function()
                        if _G.FreezeCharacter and root then
                            root.CFrame = originalCFrame
                        end
                    end)
                end
            end
        else
            if freezeConnection then
                freezeConnection:Disconnect()
                freezeConnection = nil
            end
        end
    end
})

ExclusiveTab:CreateToggle({
	Name = "Disable Notification",
	Default = false,
	 Callback = function(state)
        disableNotifs = state
        if state then
            for _, ev in ipairs({
                Net["RE/ObtainedNewFishNotification"],
                Net["RE/TextNotification"],
                Net["RE/ClaimNotification"],
                Net["RE/DisplaySystemMessage"],
                Net["RE/PlayVFX"],
            }) do
                if ev and ev.OnClientEvent then
                    for _, conn in ipairs(getconnections(ev.OnClientEvent)) do
                        conn:Disconnect()
                    end
                end
            end
        end
    end
})


ExclusiveTab:CreateToggle({
	Name = "Disable Fish Caught",
	Default = false,
  Callback = function(state)
        disableNotifs = state
        
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

        if state then
            -- 1. Hapus yang sudah ada sekarang
            local smallNotif = PlayerGui:FindFirstChild("Small Notification")
            if smallNotif then
                smallNotif:Destroy()
            end

            -- 2. Auto-hapus setiap kali game coba spawn lagi
            PlayerGui.ChildAdded:Connect(function(child)
                if child.Name == "Small Notification" or 
                   (child:FindFirstChild("Display") and child:FindFirstChildWhichIsA("Frame")) then
                    task.spawn(function()
                        task.wait() -- tunggu 1 frame biar aman
                        if child and child.Parent then
                            child:Destroy()
                        end
                    end)
                end
            end)
        end
    end
})

ExclusiveTab:CreateToggle({
	Name = "Disable Char Effect",
	Default = false,
	   Callback = function(state)
        disableCharFx = state
        if state then
            local effectEvents = {
                Net["RE/PlayFishingEffect"]
            }

            for _, ev in ipairs(effectEvents) do
                if ev and ev.OnClientEvent then
                    for _, conn in ipairs(getconnections(ev.OnClientEvent)) do
                        conn:Disconnect()
                    end
                    ev.OnClientEvent:Connect(function() end)
                end
            end

            if FishingController then
                if not _fxBackup then
                    _fxBackup = {
                        PlayFishingEffect = FishingController.PlayFishingEffect,
                        ReplicateCutscene = FishingController.ReplicateCutscene
                    }
                end
                FishingController.PlayFishingEffect = function() end
                FishingController.ReplicateCutscene = function() end
            end
        else
            if _fxBackup then
                for k, v in pairs(_fxBackup) do
                    FishingController[k] = v
                end
            end
        end
    end
})


ExclusiveTab:CreateToggle({
	Name = "Disable Fishing Effect",
	Default = false,
	  Callback = function(state)
        delEffects = state
        
        if state then
             -- Fix loop memory leak: connection should not be created recursively inside loop
             -- We just need a loop that runs periodically to clear existing effects
              spawn(function()
                while delEffects do
                    local cosmetic = workspace:FindFirstChild("CosmeticFolder")
                    if cosmetic then
                        for _, child in ipairs(cosmetic:GetChildren()) do
                            local isExactPart   = child.Name == "Part"
                            local isPureNumber  = string.match(child.Name, "^%d+$")

                            if not (isExactPart or isPureNumber) then
                                child:Destroy()
                            end
                        end
                    end
                    task.wait(0.25)
                end
            end)
            
            -- Single connection for new children
            if not _G.EffectsConnection then
                local cosmetic = workspace:WaitForChild("CosmeticFolder", 5)
                if cosmetic then
                     _G.EffectsConnection = cosmetic.ChildAdded:Connect(function(child)
                        if delEffects then
                             task.wait()
                            local isExactPart  = child.Name == "Part"
                            local isPureNumber = string.match(child.Name, "^%d+$")

                            if not (isExactPart or isPureNumber) then
                                child:Destroy()
                            end
                        end
                    end)
                end
            end
        else
            if _G.EffectsConnection then
                _G.EffectsConnection:Disconnect()
                _G.EffectsConnection = nil
            end
        end
    end
})

ExclusiveTab:CreateToggle({
	Name = "Hide Rod On Hand",
	Default = false,
	   Callback = function(state)
        hideRod = state
        if state then
            spawn(LPH_NO_VIRTUALIZE(function()
                while hideRod do
                    for _, char in ipairs(workspace.Characters:GetChildren()) do
                        local toolFolder = char:FindFirstChild("!!!EQUIPPED_TOOL!!!")
                        if toolFolder then
                            toolFolder:Destroy()
                        end
                    end
                    task.wait(1)
                end
            end))
        end
    end
})

ExclusiveTab:CreateSection({ Name = "Blatant V1" })

local Config = {
    blantant = false,
    cancel = 1.45,
    complete = 0.55,
    maxRetry = 3,
    retryDelay = 0.03
}

local Net = ReplicatedStorage
    :WaitForChild("Packages")
    :WaitForChild("_Index")
    :WaitForChild("sleitnick_net@0.2.0")
    :WaitForChild("net")

local charge
local requestminigame
local fishingcomplete
local equiprod
local cancelinput
local ReplicateTextEffect
local BaitSpawned
local BaitDestroyed

pcall(function()
    charge               = Net:WaitForChild("RF/ChargeFishingRod")
    requestminigame       = Net:WaitForChild("RF/RequestFishingMinigameStarted")
    fishingcomplete       = Net:WaitForChild("RE/FishingCompleted")
    equiprod              = Net:WaitForChild("RE/EquipToolFromHotbar")
    cancelinput           = Net:WaitForChild("RF/CancelFishingInputs")
    ReplicateTextEffect   = Net:WaitForChild("RE/ReplicateTextEffect")
    BaitSpawned           = Net:WaitForChild("RE/BaitSpawned")
    BaitDestroyed         = Net:WaitForChild("RE/BaitDestroyed")
end)

local mainThread
local equipThread

local exclaimDetected = false
local bait = 0

local lastAnimationTime = {}
local ANIMATION_COOLDOWN = 0.01

local function PlayFishingAnimationOptimized(animType)
    local currentTime = tick()
    if lastAnimationTime[animType] and (currentTime - lastAnimationTime[animType]) < ANIMATION_COOLDOWN then
        return
    end
    lastAnimationTime[animType] = currentTime
    pcall(function() _G.PlayFishingAnimation(animType) end)
end

ReplicateTextEffect.OnClientEvent:Connect(function(data)
    local char = LocalPlayer.Character
    if not char or not data.TextData or not data.TextData.AttachTo then return end

    if data.TextData.AttachTo:IsDescendantOf(char)
        and data.TextData.Text == "!" then
        exclaimDetected = true
    end
end)

if BaitSpawned then
    BaitSpawned.OnClientEvent:Connect(function(bobber, position, owner)
        if owner and owner ~= LocalPlayer then return end
        bait = 1
    end)
end

if BaitDestroyed then
    BaitDestroyed.OnClientEvent:Connect(function(bobber)
        bait = 0
    end)
end

local function StartCast()
    PlayFishingAnimationOptimized("idle")
    
    task.spawn(function()
        pcall(function()
            local ok = cancelinput:InvokeServer()
            local retries = 0
            
            if not ok then
                repeat 
                    task.wait(Config.retryDelay)
                    ok = cancelinput:InvokeServer()
                    retries += 1
                until ok or retries >= Config.maxRetry
                
                if not ok then return end
            end
            
            task.wait(0.05)

            PlayFishingAnimationOptimized("throw")

            task.spawn(function()
                pcall(function() 
                    local charged = charge:InvokeServer(math.huge)
                    local retries = 0
                    
                    if not charged then
                        repeat 
                            task.wait(Config.retryDelay)
                            charged = charge:InvokeServer(math.huge)
                            retries += 1
                        until charged or retries >= Config.maxRetry
                    end
                end)
            end)
            
            task.wait(0.05)
            
            task.spawn(function()
                pcall(function() 
                    requestminigame:InvokeServer(1, 0.05, 1731873.1873)
                end)
            end)

            PlayFishingAnimationOptimized("reel")
            
        end)
    end)

    task.spawn(function()
        exclaimDetected = false

        local timeout = 0.75
        local timer = 0

        while Config.blantant and timer < timeout do
            if exclaimDetected and bait == 0 then
                break
            end
            task.wait(0.05)
            timer += 0.05
        end

        if not Config.blantant then return end
        if not (exclaimDetected and bait == 0) then return end

        task.wait(Config.complete)

        if Config.blantant then
            pcall(function() fishingcomplete:FireServer() end)
            task.wait(0.05)

            PlayFishingAnimationOptimized("finish")
        end
    end)
end

local function MainLoop()
    equipThread = task.spawn(function()
        while Config.blantant do
            pcall(equiprod.FireServer, equiprod, 1)
            task.wait(2)
        end
    end)

    while Config.blantant do
        StartCast()
        task.wait(Config.cancel)
        if not Config.blantant then break end
        task.wait(0.2)
    end
end

local function Toggle(state)
    Config.blantant = state

    if state then
        if mainThread then task.cancel(mainThread) end
        if equipThread then task.cancel(equipThread) end
        mainThread = task.spawn(MainLoop)
    else
        if mainThread then task.cancel(mainThread) end
        if equipThread then task.cancel(equipThread) end
        mainThread = nil
        equipThread = nil
        bait = 0
        pcall(cancelinput.InvokeServer, cancelinput)
    end
end

ExclusiveTab:CreateToggle({
	Name = "Blatant V1",
	 Value = Config.blantant,
    Callback = Toggle
})

ExclusiveTab:CreateInput({
	Name = "Delay Bait",
	SideLabel = "Delay Bait",
	Placeholder = "Enter Text...",
	  Default = tostring(Config.cancel),
    Callback = function(v)
        local n = tonumber(v)
        if n and n > 0 then
            Config.cancel = n
        end
    end
})

ExclusiveTab:CreateInput({
	Name = "Delay Reel",
	SideLabel = "Delay Reel",
	Placeholder = "Enter Text...",
	 Default = tostring(Config.complete),
    Callback = function(v)
        local n = tonumber(v)
        if n and n > 0 then
            Config.complete = n
        end
    end
})

ExclusiveTab:CreateSection({ Name = "Recovery Fishing" })

ExclusiveTab:CreateButton({
	Name = "Recovery Fishing",
	SubText = "Fix stuck fishing & reset state",
	Callback = function()
		-- Notify start
		Window:Notify({
			Title = "Recovery Fishing",
			Content = "Attempting to recover fishing state...",
			Duration = 2
		})
		
		-- Step 1: Cancel any active fishing
		pcall(function() 
			if cancelinput then 
				cancelinput:InvokeServer() 
			end
		end)
		task.wait(0.1)
		
		-- Step 2: Force complete any stuck fishing
		pcall(function() 
			if fishingcomplete then 
				fishingcomplete:FireServer() 
			end
		end)
		task.wait(0.1)
		
		-- Step 3: Cancel again to ensure clean state
		pcall(function() 
			if cancelinput then 
				cancelinput:InvokeServer() 
			end
		end)
		task.wait(0.1)
		
		-- Step 4: Reset fishing state
		if st then
			st.canFish = true
		end
		
		-- Step 5: Re-equip rod if AutoRod is enabled
		if _G.AutoRod then
			pcall(function()
				if equipTool then
					equipTool:FireServer(1)
				end
			end)
		end
		
		-- Notify success
		Window:Notify({
			Title = "Recovery Complete",
			Content = "Fishing state has been reset!",
			Duration = 3
		})
	end
})

ExclusiveTab:CreateSection({ Name = "Blatant V2" })

Players = game:GetService("Players")
ReplicatedStorage = game:GetService("ReplicatedStorage")
LocalPlayer = Players.LocalPlayer

-- // GET NET LIBRARY
local v8 = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
local ChargeRod = v8:WaitForChild("RF/ChargeFishingRod")
local RequestGame = v8:WaitForChild("RF/RequestFishingMinigameStarted")
local CompleteGame = v8:WaitForChild("RE/FishingCompleted")
local CancelInput = v8:WaitForChild("RF/CancelFishingInputs")

-- // VARIABLES
local args = { -1.115296483039856, 0, 1763651451.636425 }
getgenv().fishingStart = false

local insaneSpeed = {
    enabled = false,
    delayCharge = 0.9,
    delayReset = 0.1
}

-- // ANIMATION SYSTEM
local lastAnimationTime = {}
local ANIMATION_COOLDOWN = 0.1

local function PlayFishingAnimationOptimized(animType)
    local currentTime = tick()
    if lastAnimationTime[animType] and (currentTime - lastAnimationTime[animType]) < ANIMATION_COOLDOWN then
        return
    end
    lastAnimationTime[animType] = currentTime
    pcall(function() _G.PlayFishingAnimation(animType) end)
end

-- // INSANE SPEED LOOP
local function startInsaneSpeedLoop()
    local _Charge = ChargeRod
    local _Request = RequestGame
    local _Complete = CompleteGame
    local _Cancel = CancelInput
    
    while getgenv().fishingStart and insaneSpeed.enabled do
        -- Play idle animation
        PlayFishingAnimationOptimized("idle")
        
        pcall(function() _Cancel:InvokeServer() end)
        task.wait(0.005)
        
        -- Play throw animation
        PlayFishingAnimationOptimized("throw")
        
        task.spawn(function() pcall(function() _Charge:InvokeServer() end) end)
        task.wait(0.005)
        task.spawn(function() pcall(function() _Request:InvokeServer(unpack(args)) end) end)
        
        -- Play reel animation
        PlayFishingAnimationOptimized("reel")
        
        task.wait(insaneSpeed.delayCharge * 0.15)
        
        -- Spam complete for better catch rate
        for i = 1, 5 do
            pcall(function() _Complete:FireServer() end)
            task.wait(0.001)
        end
        
        -- Play finish animation
        PlayFishingAnimationOptimized("finish")
        
        task.wait(insaneSpeed.delayReset * 0.15)
        pcall(function() _Cancel:InvokeServer() end)
        task.wait(0.005)
    end
end

ExclusiveTab:CreateToggle({
    Name = "Start Blatant V2",
    Value = false,  -- atau bisa diganti dengan Config.blatant jika ingin sync dengan config
    Callback = function(enabled)
        insaneSpeed.enabled = enabled
        getgenv().fishingStart = enabled
        
        if enabled then
            task.spawn(function()
                startInsaneSpeedLoop()
            end)
        else
            getgenv().fishingStart = false
        end
    end
})

ExclusiveTab:CreateInput({
    Name = "Delay Fishing",
    SideLabel = "Delay Fishing",
    Placeholder = "Enter delay (0 - 5)",
    Default = "4.20",
    Callback = function(v)
        local n = tonumber(v)
        if n and n >= 0 and n <= 5 then
            insaneSpeed.delayCharge = n
        else
            insaneSpeed.delayCharge = 1.15  -- fallback ke nilai aman
        end
    end
})

ExclusiveTab:CreateInput({
    Name = "Reset Delay",
    SideLabel = "Reset Delay",
    Placeholder = "Enter delay (0 - 1)",
    Default = "0.950",
    Callback = function(v)
        local n = tonumber(v)
        if n and n >= 0 and n <= 1 then
            insaneSpeed.delayReset = n
        else
            insaneSpeed.delayReset = 0.2  -- fallback ke nilai aman
        end
    end
})

ExclusiveTab:CreateSection({ Name = "Blatant V3" })

-- // V3 HYBRID CONFIG (V1 Stability + V2 Speed)
local V3Config = {
    enabled = false,
    cancelDelay = 0.8,
    completeDelay = 0.15,
    maxRetry = 3,
    retryDelay = 0.05,
    spamComplete = 5
}

local v3MainThread = nil
local v3EquipThread = nil
local v3ExclaimDetected = false
local v3Bait = 0

-- // V3 CACHED REMOTES (from V1)
local v3_charge = ChargeRod
local v3_requestminigame = RequestGame
local v3_fishingcomplete = CompleteGame
local v3_cancelinput = CancelInput
local v3_equiprod = equiprod

-- // V3 ANIMATION SYSTEM (from V2 optimized)
local v3AnimCache = {}
local V3_ANIM_COOLDOWN = 0.08

function PlayV3AnimationOptimized(animType)
    local now = tick()
    if v3AnimCache[animType] and (now - v3AnimCache[animType]) < V3_ANIM_COOLDOWN then
        return
    end
    v3AnimCache[animType] = now
    task.spawn(function()
        pcall(function() _G.PlayFishingAnimation(animType) end)
    end)
end

-- // V3 EXCLAIM DETECTION (from V1)
function setupV3ExclaimDetection()
    local player = game.Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    local function onExclaimAdded(child)
        if child.Name == "Exclaim" and V3Config.enabled then
            v3ExclaimDetected = true
        end
    end
    
    playerGui.ChildAdded:Connect(onExclaimAdded)
end

-- // V3 START CAST (Hybrid V1 structure + V2 speed)
function V3StartCast()
    task.spawn(function()
        v3ExclaimDetected = false
        v3Bait = 0
        
        task.spawn(function()
            PlayV3AnimationOptimized("idle")
            
            local ok = pcall(function() 
                v3_cancelinput:InvokeServer() 
            end)
            
            if not ok then
                local retries = 0
                repeat 
                    task.wait(V3Config.retryDelay)
                    ok = pcall(function() v3_cancelinput:InvokeServer() end)
                    retries += 1
                until ok or retries >= V3Config.maxRetry
                
                if not ok then return end
            end
            
            task.wait(0.03)

            PlayV3AnimationOptimized("throw")

            -- Parallel charge execution (V2 style)
            task.spawn(function()
                pcall(function() 
                    local charged = v3_charge:InvokeServer(math.huge)
                    local retries = 0
                    
                    if not charged then
                        repeat 
                            task.wait(V3Config.retryDelay)
                            charged = v3_charge:InvokeServer(math.huge)
                            retries += 1
                        until charged or retries >= V3Config.maxRetry
                    end
                end)
            end)
            
            task.wait(0.03)
            
            -- Parallel request execution (V2 style)
            task.spawn(function()
                pcall(function() 
                    v3_requestminigame:InvokeServer(1, 0.05, 1731873.1873)
                end)
            end)

            PlayV3AnimationOptimized("reel")
            
        end)
    end)

    -- Wait for exclaim detection (V1 style)
    task.spawn(function()
        v3ExclaimDetected = false

        local timeout = 0.5
        local timer = 0

        while V3Config.enabled and timer < timeout do
            if v3ExclaimDetected and v3Bait == 0 then
                break
            end
            task.wait(0.03)
            timer += 0.03
        end

        if not V3Config.enabled then return end
        if not (v3ExclaimDetected and v3Bait == 0) then return end

        task.wait(V3Config.completeDelay)

        if V3Config.enabled then
            -- Ultra spam complete (V2 style)
            for i = 1, V3Config.spamComplete do
                task.spawn(function()
                    pcall(function() v3_fishingcomplete:FireServer() end)
                end)
                task.wait(0.0005)
            end
            
            task.wait(0.03)
            PlayV3AnimationOptimized("finish")
        end
    end)
end

-- // V3 MAIN LOOP (V1 structure)
function V3MainLoop()
    v3EquipThread = task.spawn(function()
        while V3Config.enabled do
            pcall(v3_equiprod.FireServer, v3_equiprod, 1)
            task.wait(2)
        end
    end)

    while V3Config.enabled do
        V3StartCast()
        task.wait(V3Config.cancelDelay)
        if not V3Config.enabled then break end
        task.wait(0.1)
    end
end

-- // V3 TOGGLE (V1 style)
function V3Toggle(state)
    V3Config.enabled = state

    if state then
        -- Stop V1 and V2 if running
        if Config.blantant then
            Config.blantant = false
            if mainThread then task.cancel(mainThread) end
            if equipThread then task.cancel(equipThread) end
        end
        if getgenv().fishingStart then
            getgenv().fishingStart = false
            insaneSpeed.enabled = false
        end
        
        if v3MainThread then task.cancel(v3MainThread) end
        if v3EquipThread then task.cancel(v3EquipThread) end
        v3MainThread = task.spawn(V3MainLoop)
        
        Window:Notify({
            Title = "Blatant V3 Hybrid",
            Content = "V1+V2 Mode Activated!",
            Duration = 3
        })
    else
        if v3MainThread then task.cancel(v3MainThread) end
        if v3EquipThread then task.cancel(v3EquipThread) end
        v3MainThread = nil
        v3EquipThread = nil
        v3Bait = 0
        pcall(v3_cancelinput.InvokeServer, v3_cancelinput)
        
        Window:Notify({
            Title = "Blatant V3 Hybrid",
            Content = "Stopped",
            Duration = 2
        })
    end
end

-- Setup exclaim detection
setupV3ExclaimDetection()

ExclusiveTab:CreateToggle({
    Name = "Blatant V3 Hybrid",
    Value = V3Config.enabled,
    Callback = V3Toggle
})

ExclusiveTab:CreateInput({
    Name = "V3 Delay Bait",
    SideLabel = "Delay Bait",
    Placeholder = "Enter delay...",
    Default = tostring(V3Config.cancelDelay),
    Callback = function(v)
        local n = tonumber(v)
        if n and n > 0 then
            V3Config.cancelDelay = n
        end
    end
})

ExclusiveTab:CreateInput({
    Name = "V3 Delay Reel",
    SideLabel = "Delay Reel",
    Placeholder = "Enter delay...",
    Default = tostring(V3Config.completeDelay),
    Callback = function(v)
        local n = tonumber(v)
        if n and n > 0 then
            V3Config.completeDelay = n
        end
    end
})

ReplicatedStorage = game:GetService("ReplicatedStorage")
Packages = ReplicatedStorage.Packages._Index
NetService = Packages["sleitnick_net@0.2.0"].net

FishingController = require(ReplicatedStorage.Controllers.FishingController)

oldClick = FishingController.RequestFishingMinigameClick
oldCharge = FishingController.RequestChargeFishingRod

local autoPerf = false

task.spawn(function()
    while task.wait() do
        if autoPerf then
            NetService["RF/UpdateAutoFishingState"]:InvokeServer(true)
        end
    end
end)

ExclusiveTab:CreateSection({ Name = "Auto Perfection" })

ExclusiveTab:CreateToggle({
	Name = "Auto Perfection",
	Default = false,
 Callback = function(state)
        autoPerf = state
        
        if autoPerf then
            FishingController.RequestFishingMinigameClick = function(...) end
            FishingController.RequestChargeFishingRod = function(...) end
            print("Auto Perfection ON — Click & Charge disabled")

        else
            NetService["RF/UpdateAutoFishingState"]:InvokeServer(false)
            FishingController.RequestFishingMinigameClick = oldClick
            FishingController.RequestChargeFishingRod = oldCharge
            print("Auto Perfection OFF — Functions restored")
        end
    end
})


ExclusiveTab:CreateSection({ Name = "Webhook Fish Caught" })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local httpRequest = syn and syn.request or http and http.request or http_request or (fluxus and fluxus.request) or
    request
if not httpRequest then return end

local ItemUtility, Replion, DataService
-- Perbaikan akhir untuk bagian Webhook Fish Caught (fix local registers error & deteksi lebih akurat)

-- Hapus baris ini kalau ada di atas: local ItemUtility, Replion, DataService
-- Biar tidak declare local tidak perlu

fishDB = fishDB or {}
local rarityList = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "SECRET" }
local tierToRarity = {
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Mythic",
    [7] = "SECRET"
}
local knownFishUUIDs = {}

-- Pindah require ke dalam pcall biar aman & tidak pakai local di scope utama
pcall(function()
    local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
    local Replion = require(ReplicatedStorage.Packages.Replion)
    local DataService = Replion.Client:WaitReplion("Data")
    
    -- Simpan ke _G atau global kalau perlu dipakai di luar (webhook function)
    _G.ItemUtility = ItemUtility
    _G.DataService = DataService
end)

-- Function buildFishDatabase (sudah bagus, local di dalam loop aman karena per iteration)
function buildFishDatabase()
    table.clear(fishDB)
    local itemsContainer = ReplicatedStorage:WaitForChild("Items")
    
    for _, itemModule in ipairs(itemsContainer:GetChildren()) do
        if itemModule:IsA("ModuleScript") then
            local success, itemData = pcall(require, itemModule)
            if success and itemData and itemData.Data and itemData.Data.Type == "Fish" then
                local data = itemData.Data
                if data.Id and data.Name then
                    fishDB[data.Id] = {
                        Name = data.Name,
                        Tier = data.Tier,
                        Icon = data.Icon,
                        SellPrice = itemData.SellPrice or 0
                    }
                end
            end
        end
    end
end

-- Defer buildFishDatabase to prevent FPS drop on load
task.defer(function()
    buildFishDatabase()
end)

-- Di bagian lain webhook, pakai _G.ItemUtility & _G.DataService
-- Contoh di getInventoryFish():
function getInventoryFish()
    if not (_G.ItemUtility and _G.DataService) then return {} end
    local inventoryItems = _G.DataService:GetExpect({ "Inventory", "Items" })
    local fishes = {}
    for _, v in pairs(inventoryItems) do
        local itemData = _G.ItemUtility.GetItemDataFromItemType("Items", v.Id)
        if itemData and itemData.Data.Type == "Fish" then
            table.insert(fishes, { Id = v.Id, UUID = v.UUID, Metadata = v.Metadata })
        end
    end
    return fishes
end

-- Lakukan yang sama untuk function lain yang pakai ItemUtility/DataService

-- Tambahan: Kalau game update & tambah fish baru, panggil lagi buildFishDatabase()
-- Misal di spawn loop atau button refresh

function getPlayerCoins()
    if not DataService then return "N/A" end
    local success, coins = pcall(function() return DataService:Get("Coins") end)
    if success and coins then return string.format("%d", coins):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
    return "N/A"
end

function getThumbnailURL(assetString)
    local assetId = assetString:match("rbxassetid://(%d+)")
    if not assetId then return nil end
    local api = string.format("https://thumbnails.roblox.com/v1/assets?assetIds=%s&type=Asset&size=420x420&format=Png",
        assetId)
    local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(api)) end)
    return success and response and response.data and response.data[1] and response.data[1].imageUrl
end

function sendTestWebhook()
    -- Log: Mulai proses webhook
    print("[VoraHub Webhook] Attempting to send test webhook...")
    
    if not httpRequest then
        local msg = "HTTP request function not available!"
        print("[VoraHub Webhook] ERROR: " .. msg)
        Window:Notify({ Title = "❌ Error", Content = msg, Duration = 4 })
        return
    end
    
    if not _G.WebhookURL or _G.WebhookURL == "" then
        local msg = "Webhook URL is empty!"
        print("[VoraHub Webhook] ERROR: " .. msg)
        Window:Notify({ Title = "❌ Error", Content = msg, Duration = 4 })
        return
    end
    
    if not _G.WebhookURL:match("discord.com/api/webhooks") then
        local msg = "Invalid Discord webhook URL!"
        print("[VoraHub Webhook] ERROR: " .. msg)
        Window:Notify({ Title = "❌ Error", Content = msg, Duration = 4 })
        return
    end

    local payload = {
        username = "VoraHub Webhook",
        avatar_url = "https://cdn.discordapp.com/attachments/1434789394929287178/1448926732705988659/Swuppie.jpg?ex=693d09ac&is=693bb82c&hm=88d4c68207470eb4abc79d9b68227d85171aded5d3d99e9a76edcd823862f5fe",
        embeds = {{
            title = "Test Webhook Connected",
            description = "Webhook connection successful!",
            color = 0x00FF00
        }}
    }

    print("[VoraHub Webhook] Sending request to: " .. _G.WebhookURL)
    Window:Notify({ Title = "📤 Sending", Content = "Sending test webhook...", Duration = 2 })
    
    local success, result = pcall(function()
        return httpRequest({
            Url = _G.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
    end)
    
    if success then
        if result and result.StatusCode then
            if result.StatusCode == 204 or result.StatusCode == 200 then
                print("[VoraHub Webhook] ✓ SUCCESS! Status: " .. result.StatusCode)
                Window:Notify({ 
                    Title = "✅ Success", 
                    Content = "Test webhook sent successfully! (Status: " .. result.StatusCode .. ")", 
                    Duration = 4 
                })
            else
                print("[VoraHub Webhook] ⚠ WARNING! Unexpected status: " .. result.StatusCode)
                print("[VoraHub Webhook] Response: " .. (result.Body or "No body"))
                Window:Notify({ 
                    Title = "⚠ Warning", 
                    Content = "Webhook sent but got status: " .. result.StatusCode, 
                    Duration = 4 
                })
            end
        else
            print("[VoraHub Webhook] ✓ Request sent (no response data)")
            Window:Notify({ 
                Title = "✅ Sent", 
                Content = "Webhook request sent!", 
                Duration = 3 
            })
        end
    else
        print("[VoraHub Webhook] ✗ FAILED! Error: " .. tostring(result))
        Window:Notify({ 
            Title = "❌ Failed", 
            Content = "Failed to send: " .. tostring(result), 
            Duration = 5 
        })
    end
end

function sendNewFishWebhook(newlyCaughtFish)
    -- Log: Mulai process webhook fish caught
    -- print("[VoraHub Webhook] Processing caught fish...") 
    
    if not httpRequest then return end
    if not _G.WebhookURL or _G.WebhookURL == "" then return end
    if not _G.WebhookURL:match("discord.com/api/webhooks") then return end

    local newFishDetails = fishDB[newlyCaughtFish.Id]
    if not newFishDetails then 
        -- print("[VoraHub Webhook] ⚠ Fish ID not found in database: " .. tostring(newlyCaughtFish.Id))
        return 
    end

    local newFishRarity = tierToRarity[newFishDetails.Tier] or "Unknown"
    
    -- Cek Rarity Filter
    if #_G.WebhookRarities > 0 and not table.find(_G.WebhookRarities, newFishRarity) then 
        -- print("[VoraHub Webhook] Skipped due to rarity filter: " .. newFishRarity)
        return 
    end

    print("[VoraHub Webhook] Preparing webhook for: " .. newFishDetails.Name .. " (" .. newFishRarity .. ")")

    local fishWeight = (newlyCaughtFish.Metadata and newlyCaughtFish.Metadata.Weight and string.format("%.2f Kg", newlyCaughtFish.Metadata.Weight)) or "N/A"
    local mutation   = (newlyCaughtFish.Metadata and newlyCaughtFish.Metadata.VariantId and tostring(newlyCaughtFish.Metadata.VariantId)) or "None"
    local sellPrice  = (newFishDetails.SellPrice and ("$"..string.format("%d", newFishDetails.SellPrice):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "").." Coins")) or "N/A"
    local currentCoins = getPlayerCoins()

    local totalFishInInventory = #getInventoryFish()
    local backpackInfo = string.format("%d/4500", totalFishInInventory)

    local playerName = game.Players.LocalPlayer.Name

    local payload = {
        content = nil,
        embeds = {{
            title = "VoraHub Fish caught!",
            description = string.format("Congrats! **%s** You obtained new **%s** here for full detail fish :", playerName, newFishRarity),
            url = "https://discord.gg/vorahub",
            color = 8900346,
            fields = {
                { name = "Name Fish :",        value = "```\n"..newFishDetails.Name.."```" },
                { name = "Rarity :",           value = "```"..newFishRarity.."```" },
                { name = "Weight :",           value = "```"..fishWeight.."```" },
                { name = "Mutation :",         value = "```"..mutation.."```" },
                { name = "Sell Price :",       value = "```"..sellPrice.."```" },
                { name = "Backpack Counter :", value = "```"..backpackInfo.."```" },
                { name = "Current Coin :",     value = "```"..currentCoins.."```" },
            },
            footer = {
                text = "VoraHub Webhook",
                icon_url = "https://cdn.discordapp.com/attachments/1434789394929287178/1448926732705988659/Swuppie.jpg?ex=693d09ac&is=693bb82c&hm=88d4c68207470eb4abc79d9b68227d85171aded5d3d99e9a76edcd823862f5fe"
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
            thumbnail = {
                url = getThumbnailURL(newFishDetails.Icon)
            }
        }},
        username = "VoraHub Webhook",
        avatar_url = "https://cdn.discordapp.com/attachments/1434789394929287178/1448926732705988659/Swuppie.jpg?ex=693d09ac&is=693bb82c&hm=88d4c68207470eb4abc79d9b68227d85171aded5d3d99e9a76edcd823862f5fe",
        attachments = {}
    }

    task.spawn(function()
        local success, result = pcall(function()
            return httpRequest({
                Url = _G.WebhookURL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload)
            })
        end)
        
        if success then
            if result and (result.StatusCode == 200 or result.StatusCode == 204) then
                 -- print("[VoraHub Webhook] ✓ Fish caught sent successfully!")
            else
                 print("[VoraHub Webhook] ⚠ Failed to send fish caught. Status: " .. tostring(result.StatusCode))
            end
        else
            print("[VoraHub Webhook] ✗ Error sending fish caught: " .. tostring(result))
        end
    end)
end

ExclusiveTab:CreateInput({
	Name = "URL Webhook",
	Placeholder = "Paste your Discord...",
	Default = _G.WebhookURL or "",
    Callback = function(text)
        _G.WebhookURL = text
    end
})


ExclusiveTab:CreateMultiDropdown({
	Name = "Rarity Filter",
	Items = rarityList,
    Default = _G.WebhookRarities or {},
    Callback = function(selected_options)
        _G.WebhookRarities = selected_options
    end
})
ExclusiveTab:CreateToggle({
	Name = "Send Webhook",
    Items = _G.DetectNewFishActive or false,
    Callback = function(state)
        _G.DetectNewFishActive = state
    end
})

ExclusiveTab:CreateButton({
	Name = "Test Webhook",
	Icon = "rbxassetid://7733919427", 
    Callback = sendTestWebhook
})


ExclusiveTab:CreateSection({ Name = "Webhook Whatsapp Fish Caught" })

function sendFishToWhatsApp_API(fish)
    if not _G.WA_NumberID or _G.WA_NumberID == "" or
       not _G.WA_AccessToken or _G.WA_AccessToken == "" or
       not _G.WA_TargetPhone or _G.WA_TargetPhone == "" then
        warn("[VoraHub WA] Missing WhatsApp API credentials")
        return
    end

    local fishInfo = fishDB[fish.Id]
    if not fishInfo then return end

    local rarity = tierToRarity[fishInfo.Tier] or "Unknown"
    if #_G.WebhookRarities > 0 and not table.find(_G.WebhookRarities, rarity) then
        return
    end

    local weight   = (fish.Metadata and fish.Metadata.Weight and string.format("%.2f Kg", fish.Metadata.Weight)) or "N/A"
    local mutation = (fish.Metadata and fish.Metadata.VariantId and tostring(fish.Metadata.VariantId)) or "None"
    local price    = (fishInfo.SellPrice and ("$"..fishInfo.SellPrice)) or "N/A"
    local coins    = getPlayerCoins()
    local totalFish = #getInventoryFish()

    local thumbnail = getThumbnailURL(fishInfo.Icon)
    if not thumbnail then return end

    local caption = string.format(
        "🎣 *New Fish Caught!*\n\n" ..
        "🐟 *Name:* %s\n" ..
        "⭐ *Rarity:* %s\n" ..
        "⚖️ *Weight:* %s\n" ..
        "🧬 *Mutation:* %s\n" ..
        "💰 *Sell Price:* %s\n" ..
        "🎒 *Backpack:* %d/4500\n" ..
        "🪙 *Coins:* %s\n\n" ..
        "— VoraHub Auto Fishing",
        fishInfo.Name, rarity, weight, mutation, price, totalFish, coins
    )

    httpRequest({
        Url = "https://graph.facebook.com/v21.0/" .. _G.WA_NumberID .. "/messages",
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bearer " .. _G.WA_AccessToken,
            ["Content-Type"] = "application/json"
        },
        Body = HttpService:JSONEncode({
            messaging_product = "whatsapp",
            to = _G.WA_TargetPhone,
            type = "image",
            image = {
                link = thumbnail,
                caption = caption
            }
        })
    })
end

_G.FonnteToken        = "eJ2K4skattShv2iwYXCU"                     -- Token API Fonnte (lu isi sendiri)
_G.WA_TargetPhone     = ""                     -- Nomor tujuan WA (62xxxx)
_G.WebhookRarities    = {}                     -- List rarity yg mau dikirim (multi)
_G.DetectNewFishActive = false                 -- Toggle on/off webhook


function sendFonnteMessage(number, message, imageURL)
    local payload = {
        target = number,
        message = message,
        image = imageURL
    }

    httpRequest({
        Url = "https://api.fonnte.com/send",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = _G.FonnteToken
        },
        Body = HttpService:JSONEncode(payload)
    })
end
function sendNewFishWA(fish)
    local info = fishDB[fish.Id]
    if not info then return end

    local rarity = tierToRarity[info.Tier] or "Unknown"

    if #_G.WebhookRarities > 0 and not table.find(_G.WebhookRarities, rarity) then
        return
    end

    local weight   = fish.Metadata.Weight and string.format("%.2f Kg", fish.Metadata.Weight) or "N/A"
    local variant  = fish.Metadata.VariantId or "None"
    local iconURL  = getThumbnailURL(info.Icon)
    local playerName = game.Players.LocalPlayer.Name

    local msg = "🐟 New Fish Caught 🐟\n" .. "*" .. playerName .. "*" .. " Has Caught An *".. rarity .."* Fish!!!\n\n" ..
                "• Name: " .. info.Name .. "\n" ..
                "• Rarity: " .. rarity .. "\n" ..
                "• Weight: " .. weight .. "\n" ..
                "• Variant: " .. variant .. "\n" ..
                "• Sell Price: " .. tostring(info.SellPrice)

    sendFonnteMessage(_G.WA_TargetPhone, msg, iconURL)
end

ExclusiveTab:CreateInput({
	Name = "Target Phone (62...)",
	Placeholder = "Nomor WhatsApp",
    Default = _G.WA_TargetPhone,
    Callback = function(t)
        _G.WA_TargetPhone = t
    end
})

ExclusiveTab:CreateMultiDropdown({
	Name = "Rarity Filter",
    Items = rarityList,
    Default = _G.WebhookRarities,
    Callback = function(opts)
        _G.WebhookRarities = opts
    end
})

ExclusiveTab:CreateToggle({
	Name = "Send WA Notification",
	Default = _G.DetectNewFishActive,
    Callback = function(s)
        _G.DetectNewFishActive = s
    end
})

ExclusiveTab:CreateButton({
	Name = "Test Whatsapp",
	Icon = "rbxassetid://7733919427", 
    Callback = function()
        sendFonnteMessage(_G.WA_TargetPhone, "Test berhasil! Webhook WhatsApp aktif.", nil)
    end
})

-- Defer initial fish scan to prevent CPU spike on load
task.defer(function()
    task.wait(2) -- Wait 2 seconds after load before scanning
    local initialFishList = getInventoryFish()
    for _, fish in ipairs(initialFishList) do
        if fish and fish.UUID then
            knownFishUUIDs[fish.UUID] = true
        end
    end
end)

spawn( LPH_NO_VIRTUALIZE( function()
    while wait(0.1) do
        if _G.DetectNewFishActive then
            local currentFishList = getInventoryFish()
            for _, fish in ipairs(currentFishList) do
                if fish and fish.UUID and not knownFishUUIDs[fish.UUID] then
                    knownFishUUIDs[fish.UUID] = true
                    sendNewFishWebhook(fish)
                    sendNewFishWA(fish)
                end
            end
        end
        wait(3)
    end
end))   

MainTab:CreateSection({ Name = "Main" })

MainTab:CreateToggle({
	Name = "Auto Rod",
	Default = false,
	  Callback = function(Value) 
        _G.AutoRod = Value
        if Value then
            equipTool:FireServer(1)
        else return end
    end
})

CurrentOption = "Instant"

MainTab:CreateDropdown({
	Name = "Mode",
	Items = {"Legit", "Instant"},
	Default = "Instant",
	Callback = function(Option)
        CurrentOption = Option
    end
})

MainTab:CreateToggle({
	Name = "Auto Farm",
	Default = false,
	    Callback = function(Value)
        _G.AutoFarm = Value
        if Value then
            if CurrentOption == "Instant" then
                Window:Notify({
                    Title = "AutoFarm",
                    Content = "Instant Mode ON",
                    Duration = 3
                })
                task.spawn(function()
                    while _G.AutoFarm and CurrentOption == "Instant" do
                        pcall(instant)
                        task.wait(0.1)
                    end
                end)
            elseif CurrentOption == "Legit" then
                Window:Notify({
                    Title = "AutoFarm",
                    Content = "Legit Mode ON",
                    Duration = 3
                })
                task.spawn(function()
                    while _G.AutoFarm and CurrentOption == "Legit" do
                        pcall(function()
                            FishingController:RequestChargeFishingRod(Vector2.new(0, 0), true)
                             guid = FishingController.GetCurrentGUID and FishingController:GetCurrentGUID()
                            if guid then
                                while _G.AutoFarm
                                and CurrentOption == "Legit"
                                and guid == FishingController:GetCurrentGUID() do
                                    FishingController:FishingMinigameClick()
                                    task.wait(math.random(0, 3) / 100)
                                end
                            end
                        end)
                        task.wait(0.25)
                    end
                end)
            end

        -- ======================= WHEN AUTOFARM TURNS OFF =======================
        else
            Window:Notify({
                Title = "AutoFarm",
                Content = "AutoFarm OFF",
                Duration = 3
            })

            _G.AutoFarm = false
            pcall(autooff)
            pcall(cancel)
        end
    end
})

MainTab:CreateInput({
	Name = "Fishing Delay",
	SideLabel = "Fishing Delay",
	Placeholder = "Contoh: 1.0",
	Default = "",
	 Callback = function(value)
        delayfishing = value
    end
})

MainTab:CreateSection({ Name = "Sell", Icon = "rbxassetid://7733793319" })

Players = game:GetService("Players")
 LocalPlayer = Players.LocalPlayer

_G.AutoSells = false

local selldelay = 0
local countdelay = 0
local currentCount = 0
local sellMode = "Delay" -- "Delay" or "Count"

local label = LocalPlayer.PlayerGui.Inventory.Main.Top.Options.Fish.Label.BagSize

label:GetPropertyChangedSignal("ContentText"):Connect(function()
    local text = label.ContentText
    currentCount = tonumber(string.match(text, "^(%d+)")) or 0
end)

local sellAllItems = NetService:WaitForChild("RF/SellAllItems")

local function SafeSell()
    pcall(function()
        sellAllItems:InvokeServer()
    end)
end

local function AutoSellLoop()
    while _G.AutoSells do
        if sellMode == "Count" then
            -- Sell by count mode
            if countdelay > 0 and currentCount >= countdelay then
                SafeSell()
                task.wait(0.3)
            end
            task.wait(0.1)
        else
            -- Sell by delay mode (default)
            if selldelay > 0 then
                SafeSell()
                task.wait(selldelay)
            else
                task.wait(1) -- Default 1s if no delay set
            end
        end
    end
end

local function StartAutoSell()
    if _G.AutoSells then return end
    _G.AutoSells = true
    task.spawn(AutoSellLoop)
end

local function StopAutoSell()
    _G.AutoSells = false
end


MainTab:CreateToggle({
	Name = "Auto Sell",
	Default = false,
	  Callback = function(v)
        if v then
            StartAutoSell()
        else
            StopAutoSell()
        end
    end
})

MainTab:CreateDropdown({
	Name = "Sell Mode",
	Items = {"Delay", "Count"},
	Default = "Delay",
	Callback = function(selected)
        sellMode = selected
        Window:Notify({
            Title = "Sell Mode",
            Content = sellMode .. (sellMode == "Delay" and " (masukkan detik)" or " (masukkan jumlah item)"),
            Duration = 3
        })
    end
})

MainTab:CreateInput({
	Name = "Sell Value",
	SubText = "Delay: detik | Count: jumlah item",
	Placeholder = "10 (delay) atau 100 (count)",
	Default = "",
	Callback = function(txt)
        local value = tonumber(txt) or 0
        if sellMode == "Delay" then
            selldelay = value
            countdelay = 0
            Window:Notify({
                Title = "Sell Delay",
                Content = "Sell setiap " .. selldelay .. " detik",
                Duration = 2
            })
        else
            countdelay = value
            selldelay = 0
            Window:Notify({
                Title = "Sell Count",
                Content = "Sell saat " .. countdelay .. " item",
                Duration = 2
            })
        end
    end
})

MainTab:CreateSection({ Name = "Auto Favorite", Icon = "rbxassetid://7733765398" })

local REFishCaught = RE.FishCaught or Net:WaitForChild("RE/FishCaught")
local REFishingCompleted = RE.FishingCompleted or Net:WaitForChild("RE/FishingCompleted")

if REFishCaught then
    REFishCaught.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

if REFishingCompleted then
    REFishingCompleted.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

tierToRarity = {
    [1] = "Uncommon",
    [2] = "Common",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Mythic",
    [7] = "Secret"
}

fishNames = {}
for _, module in ipairs(Items:GetChildren()) do
    if module:IsA("ModuleScript") then
        local ok, data = pcall(require, module)
        if ok and data.Data and data.Data.Type == "Fish" then
            table.insert(fishNames, data.Data.Name)
        end
    end
end
table.sort(fishNames)

local favState, selectedName, selectedRarity = {}, {}, {}

if RE.FavoriteStateChanged then
    RE.FavoriteStateChanged.OnClientEvent:Connect(function(uuid, fav)
        if uuid then favState[uuid] = fav end
    end)
end

local function checkAndFavorite(item)
    if not st.autoFavEnabled then return end

    local info = ItemUtility.GetItemDataFromItemType("Items", item.Id)
    if not info or info.Data.Type ~= "Fish" then return end

    local rarity = tierToRarity[info.Data.Tier]
    if not rarity then return end

    local nameMatches = selectedName and table.find(selectedName, info.Data.Name)
    local rarityMatches = selectedRarity and table.find(selectedRarity, rarity)

    local isFav = favState[item.UUID] or item.Favorited or false
    local shouldFav = (nameMatches or rarityMatches) and not isFav

    if shouldFav then
        if RE.FavoriteItem then
            RE.FavoriteItem:FireServer(item.UUID, true)
            favState[item.UUID] = true
            warn("[AutoFav] Favorited:", info.Data.Name, "|", rarity)
        else
            warn("[AutoFav][ERROR] FavoriteItem RemoteEvent not found")
        end
    end
end

function scanInventory()
    if not st.autoFavEnabled then return end
    local inv = Data:GetExpect({ "Inventory", "Items" })
    if not inv then return end

    for _, item in ipairs(inv) do
        checkAndFavorite(item)
    end
end



Data:OnChange({ "Inventory", "Items" }, function()
    if st.autoFavEnabled then scanInventory() end
end)

function getPlayerNames()
    local names = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    return names
end

MainTab:CreateMultiDropdown({
	Name = "Favorite by Name",
	Items = #fishNames > 0 and fishNames or { "No Data" },
	Default = {},
	Callback = function(opts)
        selectedName = opts or {}
		if st.autoFavEnabled then
			scanInventory()
		end
    end
})


MainTab:CreateMultiDropdown({
	Name = "Favorite by Rarity",
	Items = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	Default = {}, -- HARUS table
	Callback = function(opts)
		selectedRarity = opts or {}
		if st.autoFavEnabled then
			scanInventory()
		end
	end
})


MainTab:CreateToggle({
	Name = "Start Auto Favorite",
	Default = false,
    Callback = function(state)
        st.autoFavEnabled = state
		if st.autoFavEnabled then
			scanInventory()
		end
    end
})

MainTab:CreateButton({
	Name = "Unfavorite All",
	Icon = "rbxassetid://7733919427", 
	 Callback = function()
        local inv = Data:GetExpect({ "Inventory", "Items" })
        if not inv then return end
        for _, item in ipairs(inv) do
            if (item.Favorited or favState[item.UUID]) and RE.FavoriteItem then
                RE.FavoriteItem:FireServer(item.UUID, false)
                favState[item.UUID] = false
            end
        end
    end
})

S = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
    VirtualInputManager = game:GetService("VirtualInputManager"),
    Camera = workspace.CurrentCamera,
    Workspace = workspace,
}

player = S.Players.LocalPlayer
RS = S.ReplicatedStorage
hrp = player.Character and player.Character:WaitForChild("HumanoidRootPart") or player.CharacterAdded:Wait():WaitForChild("HumanoidRootPart")

--// Quest Detector Functions (from document 1)
TARGET_QUESTS = {
    ["Element Quest"] = true,
    ["Deep Sea Quest"] = true,
    ["Diamond Researcher"] = true
}

function isObjectiveCompleted(objective)
    local checkmark = objective:FindFirstChild("Content") and 
                     objective.Content:FindFirstChild("Check") and 
                     objective.Content.Check:FindFirstChild("Vector")
    return checkmark and checkmark.Visible
end

function getObjectiveProgress(objective)
    local barFrame = objective:FindFirstChild("BarFrame")
    if barFrame then
        local bar = barFrame:FindFirstChild("Bar")
        local bg = barFrame:FindFirstChild("BG")
        local progress = barFrame:FindFirstChild("Progress")
        
        if bar and bg then
            local percentage = (bar.Size.X.Offset / bg.Size.X.Offset) * 100
            local progressText = progress and progress.Text or ""
            return math.floor(percentage), progressText
        end
    end
    return 0, ""
end

function getObjectiveDetails(objective)
    local content = objective:FindFirstChild("Content")
    if not content then return nil end
    
    local display = content:FindFirstChild("Display")
    if not display then return nil end
    
    local prefix = display:FindFirstChild("Prefix")
    local itemName = display:FindFirstChild("ItemName")
    local suffix = display:FindFirstChild("Suffix")
    
    local objectiveText = ""
    if prefix then objectiveText = objectiveText .. prefix.Text .. " " end
    if itemName then objectiveText = objectiveText .. itemName.Text .. " " end
    if suffix then objectiveText = objectiveText .. suffix.Text end
    
    return objectiveText:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

function checkQuestStatus(questFrame)
    local top = questFrame:FindFirstChild("Top")
    if not top then return nil end
    
    local topFrame = top:FindFirstChild("TopFrame")
    if not topFrame then return nil end
    
    local header = topFrame:FindFirstChild("Header")
    if not header then return nil end
    
    local questName = header.Text
    
    if not TARGET_QUESTS[questName] then
        return nil
    end
    
    local content = questFrame:FindFirstChild("Content")
    if not content then return nil end
    
    local objectives = {}
    local allCompleted = true
    
    for i = 1, 10 do
        local objective = content:FindFirstChild("Objective" .. i)
        if objective then
            local details = getObjectiveDetails(objective)
            local completed = isObjectiveCompleted(objective)
            local percentage, progressText = getObjectiveProgress(objective)
            
            if details then
                table.insert(objectives, {
                    text = details,
                    completed = completed,
                    percentage = percentage,
                    progressText = progressText
                })
                
                if not completed then
                    allCompleted = false
                end
            end
        end
    end
    
    return {
        name = questName,
        objectives = objectives,
        allCompleted = allCompleted and #objectives > 0
    }
end

-- Function to get quest data from UI
function getQuestData(questName)
    local playerGui = player:WaitForChild("PlayerGui")
    local questUI = playerGui:FindFirstChild("Quest")
    
    if not questUI then return nil end
    
    local list = questUI:FindFirstChild("List")
    if list then
        local inside = list:FindFirstChild("Inside")
        if inside then
            for _, questFrame in pairs(inside:GetChildren()) do
                if questFrame:IsA("Frame") and questFrame.Name == "Quest" then
                    local questData = checkQuestStatus(questFrame)
                    if questData and questData.name == questName then
                        return questData
                    end
                end
            end
        end
    end
    
    return nil
end

-- New functions using Quest Detector data
function getGhostfinnProgress()
    local progressTexts = {}
    local questData = getQuestData("Deep Sea Quest")
    
    if questData and questData.objectives then
        for i = 1, 4 do
            if questData.objectives[i] then
                local obj = questData.objectives[i]
                local status = obj.completed and "✓" or "✗"
                local progress = obj.progressText ~= "" and obj.progressText or (obj.percentage .. "%")
                progressTexts[i] = status .. " " .. obj.text .. " [" .. progress .. "]"
            else
                progressTexts[i] = "No progress data"
            end
        end
    else
        for i = 1, 4 do
            progressTexts[i] = "No progress data"
        end
    end
    
    return progressTexts
end

function getElementProgress()
    local progressTexts = {}
    local questData = getQuestData("Element Quest")
    
    if questData and questData.objectives then
        for i = 1, 4 do
            if questData.objectives[i] then
                local obj = questData.objectives[i]
                local status = obj.completed and "✓" or "✗"
                local progress = obj.progressText ~= "" and obj.progressText or (obj.percentage .. "%")
                progressTexts[i] = status .. " " .. obj.text .. " [" .. progress .. "]"
            else
                progressTexts[i] = "No progress data"
            end
        end
    else
        for i = 1, 4 do
            progressTexts[i] = "No progress data"
        end
    end
    
    return progressTexts
end

function getDiamondProgress()
    local progressTexts = {}
    local questData = getQuestData("Diamond Researcher")
    
    if questData and questData.objectives then
        for i = 1, 6 do
            if questData.objectives[i] then
                local obj = questData.objectives[i]
                local status = obj.completed and "✓" or "✗"
                local progress = obj.progressText ~= "" and obj.progressText or (obj.percentage .. "%")
                progressTexts[i] = status .. " " .. obj.text .. " [" .. progress .. "]"
            else
                progressTexts[i] = "No progress data"
            end
        end
    else
        for i = 1, 6 do
            progressTexts[i] = "No progress data"
        end
    end
    
    return progressTexts
end

function getElementQuestProgress()
    local progress = {"No progress data", "No progress data", "No progress data", "No progress data"}
    local questData = getQuestData("Element Quest")
    
    if questData and questData.objectives then
        for i = 1, 4 do
            if questData.objectives[i] then
                local obj = questData.objectives[i]
                progress[i] = obj.progressText ~= "" and obj.progressText or (obj.percentage .. "%")
            end
        end
    end
    
    return progress
end

function isElementQuestComplete()
    local questData = getQuestData("Element Quest")
    return questData and questData.allCompleted or false
end

--// Modules
Net = RS.Packages._Index["sleitnick_net@0.2.0"].net
Replion = require(RS.Packages.Replion)
FishingController = require(RS.Controllers.FishingController)
ItemUtility = require(RS.Shared.ItemUtility)
VendorUtility = require(RS.Shared.VendorUtility)
Data = Replion.Client:WaitReplion("Data")
Items = RS:WaitForChild("Items")

--// Remotes
RE = {
    ReplicateCutscene = Net:FindFirstChild("RE/ReplicateCutscene"),
    StopCutscene = Net:FindFirstChild("RE/StopCutscene"),
    FavoriteItem = Net:FindFirstChild("RE/FavoriteItem"),
    FavoriteStateChanged = Net:FindFirstChild("RE/FavoriteStateChanged"),
    FishingCompleted = Net:FindFirstChild("RE/FishingCompleted"),
    FishCaught = Net:FindFirstChild("RE/FishCaught"),
    TextNotification = Net:FindFirstChild("RE/TextNotification"),
    EquipItem = Net:FindFirstChild("RE/EquipItem"),
    ActivateAltar = Net:FindFirstChild("RE/ActivateEnchantingAltar"),
    EquipTool = Net:FindFirstChild("RE/EquipToolFromHotbar"),
    EvReward  = Net:FindFirstChild("RE/ClaimEventReward"),
}

RF = {
    PurchaseRod = Net:FindFirstChild("RF/PurchaseFishingRod"),
    PurchaseBait = Net:FindFirstChild("RF/PurchaseBait"),
    PurchaseWeather = Net:FindFirstChild("RF/PurchaseWeatherEvent"),
    ChargeRod = Net:FindFirstChild("RF/ChargeFishingRod"),
    Minigame = Net:FindFirstChild("RF/RequestFishingMinigameStarted"),
    UpdateSell = Net:FindFirstChild("RF/UpdateAutoSellThreshold"),
    SpecialEvent = Net:FindFirstChild("RF/SpecialDialogueEvent"),
    SellItem = Net:FindFirstChild("RF/SellItem"),
}

--// States
st = {
    canFish = true,
    autoInstant = false,
    autoFinish = false,
    sellMode = "Delay",
    sellDelay = 60,
    autoSellEnabled = false,
    autoFavEnabled = false ,
    autoPerf = true
}

_G.Celestial = _G.Celestial or {}
_G.Celestial.InstantCount = _G.Celestial.InstantCount or 0

-- Auto Perfection Loop (Always Active)
spawn(LPH_NO_VIRTUALIZE(function()
    local NetService = RS.Packages._Index["sleitnick_net@0.2.0"].net
    while task.wait(0.5) do
        if st.autoPerf and (_G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode) then
            pcall(function()
                NetService["RF/UpdateAutoFishingState"]:InvokeServer(true)
            end)
        end
    end
end))

--// Remote listeners
REFishCaught = RE.FishCaught or Net:WaitForChild("RE/FishCaught")
REFishingCompleted = RE.FishingCompleted or Net:WaitForChild("RE/FishingCompleted")

if REFishCaught then
    REFishCaught.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

if REFishingCompleted then
    REFishingCompleted.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

rodDataList = {}
rodDisplayNames = {}

-- Defer rod data loading to prevent FPS drop
task.defer(function()
    for _, item in ipairs(Items:GetChildren()) do
        if item:IsA("ModuleScript") and item.Name:match("^!!! .+ Rod$") then
            local success, moduleData = pcall(require, item)
            if success and typeof(moduleData) == "table" and moduleData.Data then
                local name = moduleData.Data.Name or "Unknown"
                local id = moduleData.Data.Id or "Unknown"
                local price = moduleData.Price or "???"
                local display = name .. " ($" .. price .. ")"
                table.insert(rodDataList, { Name = name, Id = id, Display = display })
                table.insert(rodDisplayNames, display)
            end
        end
        -- Yield every 5 items to prevent frame drops
        if #rodDataList % 5 == 0 then
            task.wait()
        end
    end
end)

baitDataList = {}
baitDisplayNames = {}

-- Defer bait data loading to prevent FPS drop
task.defer(function()
    BaitsFolder = S.ReplicatedStorage:WaitForChild("Baits")
    for _, module in ipairs(BaitsFolder:GetChildren()) do
        if module:IsA("ModuleScript") then
            local success, data = pcall(require, module)
            if success and typeof(data) == "table" and data.Data then
                local name = data.Data.Name or "Unknown"
                local id = data.Data.Id or "Unknown"
                local price = data.Price or "???"
                local display = name .. " ($" .. price .. ")"
                table.insert(baitDataList, { Name = name, Id = id, Display = display })
                table.insert(baitDisplayNames, display)
            end
        end
        -- Yield every 3 items to prevent frame drops
        if #baitDataList % 3 == 0 then
            task.wait()
        end
    end
end)

PlayerGui = player:WaitForChild("PlayerGui")

START_CFRAME = CFrame.new(
    -544.096191, 16.055603, 116.168938, 
    0.975038111, 1.26798724e-07, -0.222037584, 
    -1.31077371e-07, 1, -4.5339581e-09, 
    0.222037584, 3.35248842e-08, 0.975038111
)

GhostfinnPart1 = CFrame.new(
    -3741.23804, -135.074417, -1008.8219,
    -0.983854651, -5.2231119e-08, -0.178969383,
    -4.4131955e-08, 1, -4.92357373e-08,
    0.178969383, -4.05425382e-08, -0.983854651
)

GhostfinnPart2 = CFrame.new(
    -3576.43896, -281.441864, -1652.00879,
    -0.986065865, 6.27356229e-08, -0.166355252,
    4.83395013e-08, 1, 9.0587406e-08,
    0.166355252, 8.12836234e-08, -0.986065865
)

ElementRodLocation = CFrame.new(
    2113.85693, -91.1985855, -699.206787,
    0.998474956, -5.945203e-09, -0.0552060455,
    3.14363247e-09, 1, -5.0834366e-08,
    0.0552060455, 5.05832958e-08, 0.998474956
)

-- Diamond Quest Locations
DiamondQuest2Location = CFrame.new(
    -3188.67749, 1.07282305, 2101.84595, 
    0.938817143, 2.14984044e-10, 0.344415963, 
    8.34196712e-09, 1, -2.33629294e-08, 
    -0.344415963, 2.48066243e-08, 0.938817143
)

DiamondQuest3and4Location = CFrame.new(
    -2158.90967, 53.4871254, 3667.20703, 
    0.886574924, -4.98531634e-08, -0.462585062, 
    5.43041133e-12, 1, -1.077604e-07, 
    0.462585062, 9.55351496e-08, 0.886574924
)

DiamondQuest5and6Location = CFrame.new(
    -669.763306, 17.5000591, 414.084717, 
    -0.998891115, -1.21555646e-08, 0.0470801853, 
    -1.05114397e-08, 1, 3.51693892e-08, 
    -0.0470801853, 3.46355087e-08, -0.998891115
)

TempleLeverLocations = {
    ["Hourglass Diamond Artifact"] = CFrame.new(
        1466.80176, -30.1063519, -575.435425, 
        -0.439164162, 2.01621848e-08, 0.898406804, 
        -1.93919014e-08, 1, -3.19214095e-08, 
        -0.898406804, -3.14405568e-08, -0.439164162
    ),
    ["Arrow Artifact"] = CFrame.new(
        1466.80176, -30.1063519, -575.435425, 
        -0.439164162, 2.01621848e-08, 0.898406804, 
        -1.93919014e-08, 1, -3.19214095e-08, 
        -0.898406804, -3.14405568e-08, -0.439164162
    ),
    ["Diamond Artifact"] = CFrame.new(
        1466.80176, -30.1063519, -575.435425, 
        -0.439164162, 2.01621848e-08, 0.898406804, 
        -1.93919014e-08, 1, -3.19214095e-08, 
        -0.898406804, -3.14405568e-08, -0.439164162
    ),
    ["Crescent Artifact"] = CFrame.new(
        1466.80176, -30.1063519, -575.435425, 
        -0.439164162, 2.01621848e-08, 0.898406804, 
        -1.93919014e-08, 1, -3.19214095e-08, 
        -0.898406804, -3.14405568e-08, -0.439164162
    )
}

lastHookCall = tick()
originalFishCaught = FishingController.FishCaught
FishingController.FishCaught = function(...)
  if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
    lastHookCall = tick()
  end
    return originalFishCaught(...)
end

FishingRods = {
    ["Midnight Rod"] = {id = 80, price = 50000},
    ["Astral Rod"] = {id = 5, price = 1000500},
    -- ⭐ MISSION RODS - Harga impossible supaya TIDAK PERNAH kebeli, tapi bisa detect sebagai "Best Rod"
    ["Ghostfinn Rod"] = {id = 169, price = 9999999999999999999},  -- Deep Sea Quest reward
    ["Element Rod"] = {id = 257, price = 999999999999999999999999999},  -- Element Quest reward
}

function getRodUUID(rodId)
    inventory = dataStore:Get("Inventory")
    if not inventory or not inventory["Fishing Rods"] then return nil end
    for _, rod in ipairs(inventory["Fishing Rods"]) do
        if rod.Id == rodId then
            return rod.UUID
        end
    end
    return nil
end

function equipGhostfinnRod()
    ghostfinnRodId = 169
    uuid = getRodUUID(ghostfinnRodId)
    
    if uuid then
        args = {
            uuid,
            "Fishing Rods"
        }
        pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/EquipItem"):FireServer(unpack(args))
        end)
        return true
    else
        return false
    end
end

function getBestRod()
    inventory = dataStore:Get("Inventory")
    bestRodName, bestPrice = nil, 0
    if inventory and inventory["Fishing Rods"] then
        for _, rod in ipairs(inventory["Fishing Rods"]) do
            for name, info in pairs(FishingRods) do
                if rod.Id == info.id and info.price > bestPrice then
                    bestPrice = info.price
                    bestRodName = name
                end
            end
        end
    end
    return bestRodName
end

currentArtifactIndex = 1
isProcessingTemple = false

function processTempleLevers()
    if isProcessingTemple then return end
    isProcessingTemple = true
    
    spawn(function()
        local jungleInteractions = Workspace:WaitForChild("JUNGLE INTERACTIONS")
        if not jungleInteractions then 
            print("JUNGLE INTERACTIONS not found")
            isProcessingTemple = false
            return 
        end
        
        local templeLeverModels = {}
        for _, child in ipairs(jungleInteractions:GetChildren()) do
            if child.Name == "TempleLever" then
                table.insert(templeLeverModels, child)
            end
        end
        
        print("Total TempleLever models: " .. #templeLeverModels)
        
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart")
        
        local artifactOrder = {
            "Hourglass Diamond Artifact",
            "Arrow Artifact", 
            "Diamond Artifact",
            "Crescent Artifact"
        }
        
        for i = currentArtifactIndex, #artifactOrder do
            local artifactName = artifactOrder[i]
            local artifactCFrame = TempleLeverLocations[artifactName]
            
            print("Teleporting to: " .. artifactName)
            hrp.CFrame = artifactCFrame
            wait(2)
            
            local foundRootPart = nil
            for _, templeLeverModel in ipairs(templeLeverModels) do
                local artifactType = templeLeverModel:GetAttribute("Type")
                print("Checking TempleLever attribute: " .. tostring(artifactType))
                
                if artifactType == artifactName then
                    local rootPart = templeLeverModel:FindFirstChild("RootPart")
                    if rootPart then
                        local proximityPrompt = rootPart:FindFirstChild("ProximityPrompt")
                        if proximityPrompt then
                            foundRootPart = rootPart
                            print("FOUND ProximityPrompt for: " .. artifactName)
                            break
                        else
                            print("NO ProximityPrompt for: " .. artifactName)
                        end
                    end
                end
            end
            
            if not foundRootPart then
                print("NO ProximityPrompt found for: " .. artifactName)
                currentArtifactIndex = i + 1
            else
                print("Processing artifact: " .. artifactName)
                
                spawn(function()
                    while foundRootPart:FindFirstChild("ProximityPrompt") do
                        local args = { artifactName }
                        pcall(function()
                            game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/PlaceLeverItem"):FireServer(unpack(args))
                        end)
                        wait(10)
                    end
                    print("ProximityPrompt DISAPPEARED for: " .. artifactName)
                end)
                
                while foundRootPart:FindFirstChild("ProximityPrompt") do
                    wait(1)
                end
                
                print("Completed: " .. artifactName)
                currentArtifactIndex = i + 1
            end
        end
        
        print("ALL TempleLevers DONE")
        isProcessingTemple = false
        currentArtifactIndex = 1
    end)
end

function areAllTempleLeversComplete()
    local jungleInteractions = Workspace:WaitForChild("JUNGLE INTERACTIONS")
    if not jungleInteractions then return true end
    
    for _, child in ipairs(jungleInteractions:GetChildren()) do
        if child.Name == "TempleLever" then
            local rootPart = child:FindFirstChild("RootPart")
            if rootPart and rootPart:FindFirstChild("ProximityPrompt") then
                return false
            end
        end
    end
    return true
end

-- Helper function to check if item exists in inventory
function hasItemInInventory(itemName)
    local inventory = dataStore:Get("Inventory")
    if not inventory then return false end
    
    for _, category in pairs(inventory) do
        if type(category) == "table" then
            for _, item in ipairs(category) do
                if item.Id then
                    local itemData = ItemUtility:GetItemData(item.Id)
                    if itemData and itemData.Data and itemData.Data.Name == itemName then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Helper function to check if ANY item from a list exists in inventory
function hasAnyItemInInventory(itemNames)
    for _, itemName in ipairs(itemNames) do
        if hasItemInInventory(itemName) then
            return true
        end
    end
    return false
end

-- ⭐ FIXED TELEPORT FUNCTION - Quest Mode Aware ⭐
function teleportBasedOnCondition()
    local bestRod = getBestRod()
    local char = player.Character or player.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart")

    -- Get Deep Sea Quest progress using Quest Detector
    local ghostfinnData = getQuestData("Deep Sea Quest")
    local isDeepSeaComplete = ghostfinnData and ghostfinnData.allCompleted or false
    local isLabel1Done = ghostfinnData and ghostfinnData.objectives[1] and ghostfinnData.objectives[1].completed or false
    local isLabel2Done = ghostfinnData and ghostfinnData.objectives[2] and ghostfinnData.objectives[2].completed or false
    local isLabel3Done = ghostfinnData and ghostfinnData.objectives[3] and ghostfinnData.objectives[3].completed or false
    
    -- Get Element Quest progress using Quest Detector
    local elementData = getQuestData("Element Quest")
    local isElementQuestDone = elementData and elementData.allCompleted or false
    local isElementLabel1Done = elementData and elementData.objectives[1] and elementData.objectives[1].completed or false
    local isElementLabel2Done = elementData and elementData.objectives[2] and elementData.objectives[2].completed or false
    local isElementLabel3Done = elementData and elementData.objectives[3] and elementData.objectives[3].completed or false
    local isElementLabel4Done = elementData and elementData.objectives[4] and elementData.objectives[4].completed or false
    
    -- Get Diamond Quest progress using Quest Detector
    local diamondData = getQuestData("Diamond Researcher")
    local isDiamondComplete = diamondData and diamondData.allCompleted or false
    local isDiamondObj1Done = diamondData and diamondData.objectives[1] and diamondData.objectives[1].completed or false
    local isDiamondObj2Done = diamondData and diamondData.objectives[2] and diamondData.objectives[2].completed or false
    local isDiamondObj3Done = diamondData and diamondData.objectives[3] and diamondData.objectives[3].completed or false
    local isDiamondObj4Done = diamondData and diamondData.objectives[4] and diamondData.objectives[4].completed or false
    local isDiamondObj5Done = diamondData and diamondData.objectives[5] and diamondData.objectives[5].completed or false
    local isDiamondObj6Done = diamondData and diamondData.objectives[6] and diamondData.objectives[6].completed or false

    -- ⭐ CHECK IF RODS EXISTS (from mission rewards) ⭐
    local hasElementRod = getRodUUID(257) ~= nil  -- 257 = Element Rod ID (mission reward)
    local hasGhostfinnRod = getRodUUID(169) ~= nil  -- 169 = Ghostfinn Rod ID
    
    -- ⭐ DIAMOND QUEST MODE ⭐
    if _G.DiamondQuestMode then
        -- Check if Diamond Quest is complete
        if isDiamondComplete then
            print("[VoraHub] ✅ Diamond Quest COMPLETED!")
            WindUI:Notify({
                Title = "Quest Complete!",
                Content = "Diamond Quest has been completed!\nAuto-farm disabled.",
                Duration = 10
            })
            _G.DiamondQuestMode = false
            updateUIVisibility()
            hrp.CFrame = START_CFRAME
            return
        end
        
        -- Diamond Quest objective 2 (belum selesai)
        if not isDiamondObj2Done then
            if hasAnyItemInInventory({"Monster Shark", "Eerie Shark"}) then
                print("[VoraHub] Already have Monster/Eerie Shark, going to Diamond Quest 3-4 location")
                hrp.CFrame = DiamondQuest3and4Location
            else
                print("[VoraHub] Going to Diamond Quest 2 location")
                hrp.CFrame = DiamondQuest2Location
            end
            return
        end
        
        -- Diamond Quest objective 3 atau 4 (belum selesai)
        if not isDiamondObj3Done or not isDiamondObj4Done then
            if not isDiamondObj3Done then
                if hasItemInInventory("Great Whale") then
                    if hasItemInInventory("Ruby") then
                        print("[VoraHub] Great Whale + Ruby found, going to Diamond Quest 5-6 location")
                        hrp.CFrame = DiamondQuest5and6Location
                    else
                        print("[VoraHub] Great Whale found, staying at Diamond Quest 3-4 location")
                        hrp.CFrame = DiamondQuest3and4Location
                    end
                else
                    print("[VoraHub] Going to Diamond Quest 3-4 location for Great Whale")
                    hrp.CFrame = DiamondQuest3and4Location
                end
                return
            end
            
            if not isDiamondObj4Done then
                if hasItemInInventory("Ruby") then
                    print("[VoraHub] Ruby found, going to Diamond Quest 5-6 location")
                    hrp.CFrame = DiamondQuest5and6Location
                else
                    print("[VoraHub] Going to Diamond Quest 3-4 location for Ruby")
                    hrp.CFrame = DiamondQuest3and4Location
                end
                return
            end
            return
        end
        
        -- Diamond Quest objective 5 atau 6 (belum selesai)
        if not isDiamondObj5Done or not isDiamondObj6Done then
            if isDiamondObj6Done and not isDiamondObj5Done then
                print("[VoraHub] Objective 6 done, going back to Diamond Quest 3-4 location")
                hrp.CFrame = DiamondQuest3and4Location
            elseif hasItemInInventory("Lochnes Monster") then
                print("[VoraHub] Lochnes Monster found, going back to Diamond Quest 3-4 location")
                hrp.CFrame = DiamondQuest3and4Location
            else
                print("[VoraHub] Going to Diamond Quest 5-6 location")
                hrp.CFrame = DiamondQuest5and6Location
            end
            return
        end
        
        hrp.CFrame = ElementRodLocation
        return
    end
    
    -- ⭐ ELEMENT QUEST MODE ⭐
    if _G.ElementQuestMode then
        -- Check if Element Quest is complete
        if isElementQuestDone or hasElementRod then
            print("[VoraHub] ✅ Element Quest COMPLETED!")
            WindUI:Notify({
                Title = "Quest Complete!",
                Content = "Element Quest has been completed!\nElement Rod obtained.\nAuto-farm disabled.",
                Duration = 10
            })
            _G.ElementQuestMode = false
            updateUIVisibility()
            hrp.CFrame = START_CFRAME
            return
        end
        
        if getRodUUID(169) then
            equipGhostfinnRod()
            wait(0.5)
        end
        
        -- Check Element Quest objective 2 status using Quest Detector
        local currentElementData = getQuestData("Element Quest")
        local isLabel2Done = currentElementData and currentElementData.objectives[2] and currentElementData.objectives[2].completed or false
        
        if not isLabel2Done then
            if not areAllTempleLeversComplete() then
                print("[VoraHub] Processing Temple Levers...")
                processTempleLevers()
                
                spawn(function()
                    while not areAllTempleLeversComplete() do
                        wait(5)
                    end
                    hrp.CFrame = ElementRodLocation
                end)
            else
                print("[VoraHub] Temple Levers complete, going to Element location")
                hrp.CFrame = ElementRodLocation
            end
        else
            print("[VoraHub] Element Quest objective 2 complete, going to Temple location")
            hrp.CFrame = CFrame.new(
                1466.80176, -30.1063519, -575.435425, 
                -0.439164162, 2.01621848e-08, 0.898406804, 
                -1.93919014e-08, 1, -3.19214095e-08, 
                -0.898406804, -3.14405568e-08, -0.439164162
            )
        end
        return
    end
    
    -- ⭐ DEEP SEA QUEST MODE ⭐
    if _G.DeepSeaQuestMode then
        -- Check if Deep Sea Quest is complete
        if isDeepSeaComplete or hasGhostfinnRod then
            print("[VoraHub] ✅ Deep Sea Quest COMPLETED!")
            WindUI:Notify({
                Title = "Quest Complete!",
                Content = "Deep Sea Quest has been completed!\nGhostfinn Rod obtained.\nAuto-farm disabled.",
                Duration = 10
            })
            _G.DeepSeaQuestMode = false
            updateUIVisibility()
            hrp.CFrame = START_CFRAME
            return
        end
        
        -- Deep Sea Quest phase 2 (belum dapat Ghostfinn Rod)
        if not isLabel1Done and isLabel2Done and isLabel3Done and not hasGhostfinnRod then
            print("[VoraHub] Deep Sea Quest Phase 2 → Ghostfinn Part 2")
            hrp.CFrame = GhostfinnPart2
            return
        end
        
        -- Deep Sea Quest awal
        if bestRod == "Astral Rod" or bestRod == "Midnight Rod" then
            print("[VoraHub] Deep Sea Quest Phase 1 → Ghostfinn Part 1")
            hrp.CFrame = GhostfinnPart1
            return
        end
    end
    
    -- Default: START location
    print("[VoraHub] Default → START location")
    hrp.CFrame = START_CFRAME
end

function initialTeleport()
    if not _G.HasTeleported then
        _G.HasTeleported = true
        teleportBasedOnCondition(getBestRod())
        wait(2)
    end
end

spawn(LPH_NO_VIRTUALIZE(function()
    while true do
        task.wait(0.1)
        if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
            initialTeleport()
            char = workspace:FindFirstChild("Characters"):FindFirstChild(player.Name)
            if char then
                repeat
                    task.wait(0.1)
                    if char:FindFirstChild("!!!FISHING_VIEW_MODEL!!!") then
                        pcall(function()
                            ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net:FindFirstChild("RE/EquipToolFromHotbar"):FireServer(1)
                        end)
                    end
                    task.wait(0.1)
                    cosmeticFolder = workspace:FindFirstChild("CosmeticFolder")
                    if cosmeticFolder and not cosmeticFolder:FindFirstChild(tostring(player.UserId)) then
                        pcall(function()
                            FishingController:RequestChargeFishingRod(Vector2.new(0, 0), true)
                            task.wait(0.05)
                            local guid = FishingController.GetCurrentGUID 
                                and FishingController:GetCurrentGUID()
                            if not guid then 
                                return 
                            end
                            while (_G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode)
                                and FishingController:GetCurrentGUID() == guid do
                                FishingController:FishingMinigameClick()
                                task.wait(math.random(1, 10)/100)
                            end
                        end)
                    end
                    task.wait(0.25)
                until not (_G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode)
            end
        end
    end
end))

spawn( LPH_NO_VIRTUALIZE( function()
    while true do
        task.wait(5)
        if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
            pcall(function()
                SellAllItems:InvokeServer()
            end)
        end
    end
end))

spawn( LPH_NO_VIRTUALIZE( function()
    while true do
        task.wait(5)
        if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
            success, coins = pcall(function()
                return dataStore:Get("Coins")
            end)
            if not success or not coins then coins = 0 end

            for name, rod in pairs(FishingRods) do
                uuid = getRodUUID(rod.id)
                -- Hanya beli jika belum punya DAN coins cukup (mission rods tidak akan pernah kebeli)
                if not uuid and coins >= rod.price then
                    print("[VoraHub] Buying " .. name .. " (Price: " .. rod.price .. ")")
                    local wasDeepSea = _G.DeepSeaQuestMode
                    local wasElement = _G.ElementQuestMode
                    local wasDiamond = _G.DiamondQuestMode
                    _G.DeepSeaQuestMode = false
                    _G.ElementQuestMode = false
                    _G.DiamondQuestMode = false
                    _G.HasTeleported = false
                    char = workspace:FindFirstChild("Characters"):FindFirstChild(player.Name)
                    if char then
                        hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Health = 0 end
                        task.wait(5)
                        pcall(function()
                            ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/PurchaseFishingRod"):InvokeServer(rod.id)
                        end)
                        task.wait(0.5)
                        newUUID = getRodUUID(rod.id)
                        if newUUID then
                            pcall(function()
                                ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RE/EquipItem"]:FireServer(newUUID, "Fishing Rods")
                            end)
                            print("[VoraHub] " .. name .. " equipped!")
                        end
                        teleportBasedOnCondition(getBestRod())
                        task.wait(0.5)
                        _G.DeepSeaQuestMode = wasDeepSea
                        _G.ElementQuestMode = wasElement
                        _G.DiamondQuestMode = wasDiamond
                        break
                    end
                end
            end
        end
    end
end))

Baits = {
    [3]  = {name = "Midnight Bait", price = 3000},
    [15] = {name = "Corrupt Bait", price = 1150000},
    [16] = {name = "Aether Bait", price = 3700000},
}

function hasBait(baitId)
    inventory = dataStore:Get("Inventory")
    if not inventory or not inventory.Baits then return false end
    for _, b in ipairs(inventory.Baits) do
        if b.Id == baitId then
            return true
        end
    end
    return false
end

function buyBait(baitId)
    args = {baitId}
    pcall(function()
        ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseBait"]:InvokeServer(unpack(args))
    end)
end

function equipBait(baitId)
    args = {baitId}
    pcall(function()
        ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RE/EquipBait"]:FireServer(unpack(args))
    end)
end

spawn( LPH_NO_VIRTUALIZE( function()
    while true do
        task.wait(5)
        if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
            coins = 0
            pcall(function()
                coins = dataStore:Get("Coins") or 0
            end)

            for baitId, bait in pairs(Baits) do
                if not hasBait(baitId) and coins >= bait.price then
                    print("[VoraHub] Buying " .. bait.name .. "...")
                    local wasDeepSea = _G.DeepSeaQuestMode
                    local wasElement = _G.ElementQuestMode
                    local wasDiamond = _G.DiamondQuestMode
                    _G.DeepSeaQuestMode = false
                    _G.ElementQuestMode = false
                    _G.DiamondQuestMode = false
                    _G.HasTeleported = false
                    char = workspace:FindFirstChild("Characters"):FindFirstChild(player.Name)
                    if char then
                        hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Health = 0 end
                        task.wait(5)
                        buyBait(baitId)
                        task.wait(0.5)
                        equipBait(baitId)
                        teleportBasedOnCondition(getBestRod())
                        task.wait(0.5)
                        _G.DeepSeaQuestMode = wasDeepSea
                        _G.ElementQuestMode = wasElement
                        _G.DiamondQuestMode = wasDiamond
                        break
                    end
                end
            end
        end
    end
end))

spawn( LPH_NO_VIRTUALIZE( function()
    local cachedChar, cachedHum, cachedHrp = nil, nil, nil
    local lastCharUpdate = 0
    local charUpdateInterval = 2 -- Update character cache every 2 seconds
    
    while true do
        task.wait(2.5) -- Increased from 1s to reduce CPU usage
        if _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode then
          repeat
          wait(0.5) -- Increased from 0.2s to reduce CPU usage
            -- Update character cache if needed
            if tick() - lastCharUpdate > charUpdateInterval then
                char = workspace:FindFirstChild("Characters"):FindFirstChild(player.Name)
                hum = char and char:FindFirstChildOfClass("Humanoid")
                hrp = char and char:FindFirstChild("HumanoidRootPart")
                cachedChar, cachedHum, cachedHrp = char, hum, hrp
                lastCharUpdate = tick()
            else
                char, hum, hrp = cachedChar, cachedHum, cachedHrp
            end
            
            if hum and hrp and tick() - lastHookCall > 15 then
                print("[VoraHub] No hook activity detected, respawning...")
                local wasDeepSea = _G.DeepSeaQuestMode
                local wasElement = _G.ElementQuestMode
                local wasDiamond = _G.DiamondQuestMode
                _G.DeepSeaQuestMode = false
                _G.ElementQuestMode = false
                _G.DiamondQuestMode = false
                _G.HasTeleported = false
                hum.Health = 0
                task.wait(5)
                char = workspace:FindFirstChild("Characters"):FindFirstChild(player.Name)
                if char and char:FindFirstChild("HumanoidRootPart") then
                    teleportBasedOnCondition(getBestRod())
                    task.wait(0.5)
                    _G.DeepSeaQuestMode = wasDeepSea
                    _G.ElementQuestMode = wasElement
                    _G.DiamondQuestMode = wasDiamond
                end
                lastHookCall = tick()
                -- Reset cache after respawn
                cachedChar, cachedHum, cachedHrp = nil, nil, nil
                lastCharUpdate = 0
            end
           until not (_G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode)
        else
            lastHookCall = tick()
        end
    end
end))

sendEnabled = false
lastSend = 0

function getBestBait()
    inventory = dataStore:Get("Inventory")
    if not inventory or not inventory.Baits then return "None" end
    best, bestPrice = nil, 0
    baitPrices = {
        [3]  = {"Midnight Bait", 3000},
        [15] = {"Corrupt Bait", 1150000},
        [16] = {"Aether Bait", 3700000},
    }
    for _, bait in ipairs(inventory.Baits) do
        info = baitPrices[bait.Id]
        if info and info[2] > bestPrice then
            bestPrice = info[2]
            best = info[1]
        end
    end
    return best or "None"
end

function getCoins()
    success, coins = pcall(function()
        return dataStore:Get("Coins")
    end)
    return (success and coins) or 0
end

function getFishCounts()
    -- Cache results to avoid expensive nested loops
    local fishCountsCache = DataCache:Get("fishCounts")
    if fishCountsCache then return fishCountsCache end
    
    inventory = dataStore:Get("Inventory")
    counts = {Common=0, Uncommon=0, Rare=0, Epic=0, Legendary=0, Mythical=0, Secret=0}

    if not inventory then return counts end

    for _, category in pairs(inventory) do
        if type(category) == "table" then
            for _, item in ipairs(category) do
                if item.Id then
                    itemData = ItemUtility:GetItemData(item.Id)
                    if itemData and itemData.Data and itemData.Data.Type == "Fish" then
                        tier = itemData.Data.Tier or 1
                        if tier == 1 then counts.Common += 1
                        elseif tier == 2 then counts.Uncommon += 1
                        elseif tier == 3 then counts.Rare += 1
                        elseif tier == 4 then counts.Epic += 1
                        elseif tier == 5 then counts.Legendary += 1
                        elseif tier == 6 then counts.Mythical += 1
                        elseif tier == 7 then counts.Secret += 1
                        end
                    end
                end
            end
        end
    end
    
    -- Cache the result
    DataCache:Set("fishCounts", counts)
    return counts
end

screenGui = Instance.new("ScreenGui")
screenGui.Name = "VoraHub Status"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

blur = Instance.new("BlurEffect")
blur.Name = "TanzBlur"
blur.Size = 24
blur.Enabled = false
blur.Parent = Lighting

titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0,300,0,40)
titleLabel.Position = UDim2.new(0.5,0,0.25,0)
titleLabel.AnchorPoint = Vector2.new(0.5,0.5)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(64,224,208)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 24
titleLabel.Text = "VoraHub Status"
titleLabel.TextScaled = true
titleLabel.Visible = false
titleLabel.Parent = screenGui

row1 = Instance.new("TextLabel")
row1.Size = UDim2.new(0,600,0,30)
row1.Position = UDim2.new(0.5,0,0.35,0)
row1.AnchorPoint = Vector2.new(0.5,0.5)
row1.BackgroundTransparency = 1
row1.TextColor3 = Color3.fromRGB(255,255,255)
row1.Font = Enum.Font.GothamBold
row1.TextSize = 18
row1.TextXAlignment = Enum.TextXAlignment.Center
row1.Visible = false
row1.Parent = screenGui

row2 = Instance.new("TextLabel")
row2.Size = UDim2.new(0,600,0,30)
row2.Position = UDim2.new(0.5,0,0.4,0)
row2.AnchorPoint = Vector2.new(0.5,0.5)
row2.BackgroundTransparency = 1
row2.TextColor3 = Color3.fromRGB(255,255,255)
row2.Font = Enum.Font.GothamBold
row2.TextSize = 18
row2.TextXAlignment = Enum.TextXAlignment.Center
row2.Visible = false
row2.Parent = screenGui

row3 = Instance.new("TextLabel")
row3.Size = UDim2.new(0,600,0,30)
row3.Position = UDim2.new(0.5,0,0.45,0)
row3.AnchorPoint = Vector2.new(0.5,0.5)
row3.BackgroundTransparency = 1
row3.TextColor3 = Color3.fromRGB(255,255,255)
row3.Font = Enum.Font.GothamBold
row3.TextSize = 18
row3.TextXAlignment = Enum.TextXAlignment.Center
row3.Visible = false
row3.Parent = screenGui

ghostfinnTitle = Instance.new("TextLabel")
ghostfinnTitle.Size = UDim2.new(0,600,0,30)
ghostfinnTitle.Position = UDim2.new(0.5,0,0.5,0)
ghostfinnTitle.AnchorPoint = Vector2.new(0.5,0.5)
ghostfinnTitle.BackgroundTransparency = 1
ghostfinnTitle.TextColor3 = Color3.fromRGB(64,224,208)
ghostfinnTitle.Font = Enum.Font.GothamBold
ghostfinnTitle.TextSize = 18
ghostfinnTitle.TextXAlignment = Enum.TextXAlignment.Center
ghostfinnTitle.Text = "Deep Sea Quest"
ghostfinnTitle.Visible = false
ghostfinnTitle.Parent = screenGui

ghostfinnRow1 = Instance.new("TextLabel")
ghostfinnRow1.Size = UDim2.new(0,600,0,25)
ghostfinnRow1.Position = UDim2.new(0.5,0,0.55,0)
ghostfinnRow1.AnchorPoint = Vector2.new(0.5,0.5)
ghostfinnRow1.BackgroundTransparency = 1
ghostfinnRow1.TextColor3 = Color3.fromRGB(255,255,255)
ghostfinnRow1.Font = Enum.Font.Gotham
ghostfinnRow1.TextSize = 12
ghostfinnRow1.TextXAlignment = Enum.TextXAlignment.Center
ghostfinnRow1.Text = "Loading..."
ghostfinnRow1.Visible = false
ghostfinnRow1.Parent = screenGui

ghostfinnRow2 = Instance.new("TextLabel")
ghostfinnRow2.Size = UDim2.new(0,600,0,25)
ghostfinnRow2.Position = UDim2.new(0.5,0,0.575,0)
ghostfinnRow2.AnchorPoint = Vector2.new(0.5,0.5)
ghostfinnRow2.BackgroundTransparency = 1
ghostfinnRow2.TextColor3 = Color3.fromRGB(255,255,255)
ghostfinnRow2.Font = Enum.Font.Gotham
ghostfinnRow2.TextSize = 12
ghostfinnRow2.TextXAlignment = Enum.TextXAlignment.Center
ghostfinnRow2.Text = ""
ghostfinnRow2.Visible = false
ghostfinnRow2.Parent = screenGui

ghostfinnRow3 = Instance.new("TextLabel")
ghostfinnRow3.Size = UDim2.new(0,600,0,25)
ghostfinnRow3.Position = UDim2.new(0.5,0,0.6,0)
ghostfinnRow3.AnchorPoint = Vector2.new(0.5,0.5)
ghostfinnRow3.BackgroundTransparency = 1
ghostfinnRow3.TextColor3 = Color3.fromRGB(255,255,255)
ghostfinnRow3.Font = Enum.Font.Gotham
ghostfinnRow3.TextSize = 12
ghostfinnRow3.TextXAlignment = Enum.TextXAlignment.Center
ghostfinnRow3.Text = ""
ghostfinnRow3.Visible = false
ghostfinnRow3.Parent = screenGui

ghostfinnRow4 = Instance.new("TextLabel")
ghostfinnRow4.Size = UDim2.new(0,600,0,25)
ghostfinnRow4.Position = UDim2.new(0.5,0,0.625,0)
ghostfinnRow4.AnchorPoint = Vector2.new(0.5,0.5)
ghostfinnRow4.BackgroundTransparency = 1
ghostfinnRow4.TextColor3 = Color3.fromRGB(255,255,255)
ghostfinnRow4.Font = Enum.Font.Gotham
ghostfinnRow4.TextSize = 12
ghostfinnRow4.TextXAlignment = Enum.TextXAlignment.Center
ghostfinnRow4.Text = ""
ghostfinnRow4.Visible = false
ghostfinnRow4.Parent = screenGui

elementTitle = Instance.new("TextLabel")
elementTitle.Size = UDim2.new(0,600,0,30)
elementTitle.Position = UDim2.new(0.5,0,0.5,0)
elementTitle.AnchorPoint = Vector2.new(0.5,0.5)
elementTitle.BackgroundTransparency = 1
elementTitle.TextColor3 = Color3.fromRGB(64,224,208)
elementTitle.Font = Enum.Font.GothamBold
elementTitle.TextSize = 18
elementTitle.TextXAlignment = Enum.TextXAlignment.Center
elementTitle.Text = "Element Quest"
elementTitle.Visible = false
elementTitle.Parent = screenGui

elementRow1 = Instance.new("TextLabel")
elementRow1.Size = UDim2.new(0,600,0,25)
elementRow1.Position = UDim2.new(0.5,0,0.55,0)
elementRow1.AnchorPoint = Vector2.new(0.5,0.5)
elementRow1.BackgroundTransparency = 1
elementRow1.TextColor3 = Color3.fromRGB(255,255,255)
elementRow1.Font = Enum.Font.Gotham
elementRow1.TextSize = 12
elementRow1.TextXAlignment = Enum.TextXAlignment.Center
elementRow1.Text = "Loading..."
elementRow1.Visible = false
elementRow1.Parent = screenGui

elementRow2 = Instance.new("TextLabel")
elementRow2.Size = UDim2.new(0,600,0,25)
elementRow2.Position = UDim2.new(0.5,0,0.575,0)
elementRow2.AnchorPoint = Vector2.new(0.5,0.5)
elementRow2.BackgroundTransparency = 1
elementRow2.TextColor3 = Color3.fromRGB(255,255,255)
elementRow2.Font = Enum.Font.Gotham
elementRow2.TextSize = 12
elementRow2.TextXAlignment = Enum.TextXAlignment.Center
elementRow2.Text = ""
elementRow2.Visible = false
elementRow2.Parent = screenGui

elementRow3 = Instance.new("TextLabel")
elementRow3.Size = UDim2.new(0,600,0,25)
elementRow3.Position = UDim2.new(0.5,0,0.6,0)
elementRow3.AnchorPoint = Vector2.new(0.5,0.5)
elementRow3.BackgroundTransparency = 1
elementRow3.TextColor3 = Color3.fromRGB(255,255,255)
elementRow3.Font = Enum.Font.Gotham
elementRow3.TextSize = 12
elementRow3.TextXAlignment = Enum.TextXAlignment.Center
elementRow3.Text = ""
elementRow3.Visible = false
elementRow3.Parent = screenGui

elementRow4 = Instance.new("TextLabel")
elementRow4.Size = UDim2.new(0,600,0,25)
elementRow4.Position = UDim2.new(0.5,0,0.625,0)
elementRow4.AnchorPoint = Vector2.new(0.5,0.5)
elementRow4.BackgroundTransparency = 1
elementRow4.TextColor3 = Color3.fromRGB(255,255,255)
elementRow4.Font = Enum.Font.Gotham
elementRow4.TextSize = 12
elementRow4.TextXAlignment = Enum.TextXAlignment.Center
elementRow4.Text = ""
elementRow4.Visible = false
elementRow4.Parent = screenGui

diamondTitle = Instance.new("TextLabel")
diamondTitle.Size = UDim2.new(0,600,0,30)
diamondTitle.Position = UDim2.new(0.5,0,0.5,0)
diamondTitle.AnchorPoint = Vector2.new(0.5,0.5)
diamondTitle.BackgroundTransparency = 1
diamondTitle.TextColor3 = Color3.fromRGB(64,224,208)
diamondTitle.Font = Enum.Font.GothamBold
diamondTitle.TextSize = 18
diamondTitle.TextXAlignment = Enum.TextXAlignment.Center
diamondTitle.Text = "Diamond Researcher"
diamondTitle.Visible = false
diamondTitle.Parent = screenGui

diamondRow1 = Instance.new("TextLabel")
diamondRow1.Size = UDim2.new(0,600,0,25)
diamondRow1.Position = UDim2.new(0.5,0,0.55,0)
diamondRow1.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow1.BackgroundTransparency = 1
diamondRow1.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow1.Font = Enum.Font.Gotham
diamondRow1.TextSize = 12
diamondRow1.TextXAlignment = Enum.TextXAlignment.Center
diamondRow1.Text = "Loading..."
diamondRow1.Visible = false
diamondRow1.Parent = screenGui

diamondRow2 = Instance.new("TextLabel")
diamondRow2.Size = UDim2.new(0,600,0,25)
diamondRow2.Position = UDim2.new(0.5,0,0.575,0)
diamondRow2.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow2.BackgroundTransparency = 1
diamondRow2.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow2.Font = Enum.Font.Gotham
diamondRow2.TextSize = 12
diamondRow2.TextXAlignment = Enum.TextXAlignment.Center
diamondRow2.Text = ""
diamondRow2.Visible = false
diamondRow2.Parent = screenGui

diamondRow3 = Instance.new("TextLabel")
diamondRow3.Size = UDim2.new(0,600,0,25)
diamondRow3.Position = UDim2.new(0.5,0,0.6,0)
diamondRow3.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow3.BackgroundTransparency = 1
diamondRow3.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow3.Font = Enum.Font.Gotham
diamondRow3.TextSize = 12
diamondRow3.TextXAlignment = Enum.TextXAlignment.Center
diamondRow3.Text = ""
diamondRow3.Visible = false
diamondRow3.Parent = screenGui

diamondRow4 = Instance.new("TextLabel")
diamondRow4.Size = UDim2.new(0,600,0,25)
diamondRow4.Position = UDim2.new(0.5,0,0.625,0)
diamondRow4.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow4.BackgroundTransparency = 1
diamondRow4.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow4.Font = Enum.Font.Gotham
diamondRow4.TextSize = 12
diamondRow4.TextXAlignment = Enum.TextXAlignment.Center
diamondRow4.Text = ""
diamondRow4.Visible = false
diamondRow4.Parent = screenGui

diamondRow5 = Instance.new("TextLabel")
diamondRow5.Size = UDim2.new(0,600,0,25)
diamondRow5.Position = UDim2.new(0.5,0,0.65,0)
diamondRow5.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow5.BackgroundTransparency = 1
diamondRow5.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow5.Font = Enum.Font.Gotham
diamondRow5.TextSize = 12
diamondRow5.TextXAlignment = Enum.TextXAlignment.Center
diamondRow5.Text = ""
diamondRow5.Visible = false
diamondRow5.Parent = screenGui

diamondRow6 = Instance.new("TextLabel")
diamondRow6.Size = UDim2.new(0,600,0,25)
diamondRow6.Position = UDim2.new(0.5,0,0.675,0)
diamondRow6.AnchorPoint = Vector2.new(0.5,0.5)
diamondRow6.BackgroundTransparency = 1
diamondRow6.TextColor3 = Color3.fromRGB(255,255,255)
diamondRow6.Font = Enum.Font.Gotham
diamondRow6.TextSize = 12
diamondRow6.TextXAlignment = Enum.TextXAlignment.Center
diamondRow6.Text = ""
diamondRow6.Visible = false
diamondRow6.Parent = screenGui

RunService.RenderStepped:Connect( LPH_NO_VIRTUALIZE( function()
    counts = getFishCounts()
    row1.Text = "Best Rod: "..tostring(getBestRod())
    row2.Text = "Best Bait: "..tostring(getBestBait())
    row3.Text = "Coins: "..tostring(getCoins())
    
    ghostfinnProgress = getGhostfinnProgress()
    ghostfinnRow1.Text = ghostfinnProgress[1] or "No progress data"
    ghostfinnRow2.Text = ghostfinnProgress[2] or "No progress data"
    ghostfinnRow3.Text = ghostfinnProgress[3] or "No progress data"
    ghostfinnRow4.Text = ghostfinnProgress[4] or "No progress data"

    elementProgress = getElementProgress()
    elementRow1.Text = elementProgress[1] or "No progress data"
    elementRow2.Text = elementProgress[2] or "No progress data"
    elementRow3.Text = elementProgress[3] or "No progress data"
    elementRow4.Text = elementProgress[4] or "No progress data"
    
    diamondProgress = getDiamondProgress()
    diamondRow1.Text = diamondProgress[1] or "No progress data"
    diamondRow2.Text = diamondProgress[2] or "No progress data"
    diamondRow3.Text = diamondProgress[3] or "No progress data"
    diamondRow4.Text = diamondProgress[4] or "No progress data"
    diamondRow5.Text = diamondProgress[5] or "No progress data"
    diamondRow6.Text = diamondProgress[6] or "No progress data"
end))

-- Initialize quest flags
_G.DeepSeaQuestMode = _G.DeepSeaQuestMode or false
_G.ElementQuestMode = _G.ElementQuestMode or false
_G.DiamondQuestMode = _G.DiamondQuestMode or false

-- Helper function to check if any quest is active
function isAnyQuestActive()
    return _G.DeepSeaQuestMode or _G.ElementQuestMode or _G.DiamondQuestMode
end

-- Helper function to update UI visibility
function updateUIVisibility()
    local anyActive = isAnyQuestActive()
    
    -- Common UI elements
    row1.Visible = anyActive
    row2.Visible = anyActive
    row3.Visible = anyActive
    titleLabel.Visible = anyActive
    blur.Enabled = anyActive
    
    -- Deep Sea Quest UI
    ghostfinnTitle.Visible = _G.DeepSeaQuestMode
    ghostfinnRow1.Visible = _G.DeepSeaQuestMode
    ghostfinnRow2.Visible = _G.DeepSeaQuestMode
    ghostfinnRow3.Visible = _G.DeepSeaQuestMode
    ghostfinnRow4.Visible = _G.DeepSeaQuestMode
    
    -- Element Quest UI
    elementTitle.Visible = _G.ElementQuestMode
    elementRow1.Visible = _G.ElementQuestMode
    elementRow2.Visible = _G.ElementQuestMode
    elementRow3.Visible = _G.ElementQuestMode
    elementRow4.Visible = _G.ElementQuestMode
    
    -- Diamond Quest UI
    diamondTitle.Visible = _G.DiamondQuestMode
    diamondRow1.Visible = _G.DiamondQuestMode
    diamondRow2.Visible = _G.DiamondQuestMode
    diamondRow3.Visible = _G.DiamondQuestMode
    diamondRow4.Visible = _G.DiamondQuestMode
    diamondRow5.Visible = _G.DiamondQuestMode
    diamondRow6.Visible = _G.DiamondQuestMode
end

REFishCaught = RE.FishCaught or Net:WaitForChild("RE/FishCaught")
REFishingCompleted = RE.FishingCompleted or Net:WaitForChild("RE/FishingCompleted")

if REFishCaught then
    REFishCaught.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

if REFishingCompleted then
    REFishingCompleted.OnClientEvent:Connect(function()
        st.canFish = true
    end)
end

tierToRarity = {
    [1] = "Uncommon",
    [2] = "Common",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
    [6] = "Mythic",
    [7] = "Secret"
}

fishNames = {}
for _, module in ipairs(Items:GetChildren()) do
    if module:IsA("ModuleScript") then
        local ok, data = pcall(require, module)
        if ok and data.Data and data.Data.Type == "Fish" then
            table.insert(fishNames, data.Data.Name)
        end
    end
end
table.sort(fishNames)

favState, selectedName, selectedRarity = {}, {}, {}

if RE.FavoriteStateChanged then
    RE.FavoriteStateChanged.OnClientEvent:Connect(function(uuid, fav)
        if uuid then favState[uuid] = fav end
    end)
end

function checkAndFavorite(item)
    if not st.autoFavEnabled then return end

    local info = ItemUtility.GetItemDataFromItemType("Items", item.Id)
    if not info or info.Data.Type ~= "Fish" then return end

    local rarity = tierToRarity[info.Data.Tier]
    if not rarity then return end

    local nameMatches = selectedName and table.find(selectedName, info.Data.Name)
    local rarityMatches = selectedRarity and table.find(selectedRarity, rarity)

    local isFav = favState[item.UUID] or item.Favorited or false
    local shouldFav = (nameMatches or rarityMatches) and not isFav

    if shouldFav then
        if RE.FavoriteItem then
            while st.autoFavEnabled do
                RE.FavoriteItem:FireServer(item.UUID, true)
                favState[item.UUID] = true
                warn("[AutoFav] Favorited:", info.Data.Name, "|", rarity)
                task.wait(15)
            end
        else
            warn("[AutoFav][ERROR] FavoriteItem RemoteEvent not found")
        end
    end
end

function scanInventory()
    if not st.autoFavEnabled then return end
    local inv = Data:GetExpect({ "Inventory", "Items" })
    if not inv then return end

    for _, item in ipairs(inv) do
        checkAndFavorite(item)
    end
end

Data:OnChange({ "Inventory", "Items" }, function()
    if st.autoFavEnabled then scanInventory() end
end)

function getPlayerNames()
    local names = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    return names
end

function filterValidNames(list)
    local valid = {}
    local lookup = {}

    for _, n in ipairs(fishNames) do
        lookup[n] = true
    end

    for _, n in ipairs(list) do
        if lookup[n] then
            table.insert(valid, n)
        end
    end

    return valid
end

selectedName = filterValidNames({
    "Ruby",
})

AutoTab:CreateSection({ Name = "Auto Quest" })

AutoTab:CreateToggle({
	Name = "Auto Deep Sea Quest",
	Default = _G.DeepSeaQuestMode,
	Callback = function(state)
        _G.DeepSeaQuestMode = state
        updateUIVisibility()
        
        if not state and not isAnyQuestActive() then
            pcall(function()
                game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/CancelFishingInputs"):InvokeServer()
            end)
        end
    end
})

AutoTab:CreateToggle({
	Name = "Auto Element Quest",
	Default = _G.ElementQuestMode,
	Callback = function(state)
        _G.ElementQuestMode = state
        updateUIVisibility()
        
        if not state and not isAnyQuestActive() then
            pcall(function()
                game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/CancelFishingInputs"):InvokeServer()
            end)
        end
    end
})

AutoTab:CreateToggle({
	Name = "Auto Diamond Quest",
	Default = _G.DiamondQuestMode,
	Callback = function(state)
        _G.DiamondQuestMode = state
        updateUIVisibility()
        
        if not state and not isAnyQuestActive() then
            pcall(function()
                game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RF/CancelFishingInputs"):InvokeServer()
            end)
        end
    end
})

AutoTab:CreateSection({ Name = "Auto Candy" })

AutoTab:CreateToggle({
	Name = "Auto Infinite Candy",
	Default = false,
	 Callback = function(state)
        if state then
            local characters = {
                "Talon", "Kenny", "OutOfOrderFoxy", "Terror", "Req",
                "Mac", "Wildes", "Jixxio", "Relukt", "Tapiobaa", "nthnth", "TheBluePurple", "Mitch"
            }
            
            for _, character in ipairs(characters) do
                local args = {
                    [1] = character,
                    [2] = "PresentChristmasDoor"
                }
                game:GetService("ReplicatedStorage").Packages._Index:FindFirstChild("sleitnick_net@0.2.0").net:FindFirstChild("RF/SpecialDialogueEvent"):InvokeServer(unpack(args))
            end
        end
    end
})


AutoTab:CreateSection({ Name = "Auto Cave", Icon = "rbxassetid://7733799901" })

AutoTab:CreateToggle({
	Name = "Auto Open Mysterious Cave Wall",
	Default = false,
	Callback = function(state)
        if state then
            spawn(function()
                -- Fire TNT event 4 times
                for i = 1, 4 do
                    local args = {
                        "TNT"
                    }
                    pcall(function()
                        game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/SearchItemPickedUp"):FireServer(unpack(args))
                    end)
                    task.wait(0.5)
                end
                
                -- Wait a bit then fire GainAccessToMaze
                task.wait(1)
                pcall(function()
                    game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/GainAccessToMaze"):FireServer()
                end)
                
                Window:Notify({
                    Title = "Cave Wall Opened! 🚪",
                    Content = "Mysterious Cave Wall has been opened!",
                    Duration = 5
                })
            end)
        end
    end
})

AutoTab:CreateToggle({
	Name = "Auto Open Pirate Chest",
	Default = false,
	Callback = function(state)
        _G.AutoOpenPirateChest = state
        
        if state then
            spawn(function()
                while _G.AutoOpenPirateChest do
                    pcall(function()
                        -- Get the remote event
                        local RE = game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net"):WaitForChild("RE/ClaimPirateChest")
                        
                        -- Find all pirate chests in PirateChestStorage
                        local chestsFound = 0
                        local pirateChestStorage = workspace:FindFirstChild("PirateChestStorage")
                        
                        if pirateChestStorage then
                            -- Get all children from PirateChestStorage
                            for _, chest in ipairs(pirateChestStorage:GetChildren()) do
                                -- Check if the chest name is a UUID format
                                local chestId = chest.Name
                                
                                if chestId:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") then
                                    local args = { chestId }
                                    RE:FireServer(unpack(args))
                                    chestsFound = chestsFound + 1
                                    print("[VoraHub] Claiming chest: " .. chestId)
                                    task.wait(0.3)
                                end
                            end
                            
                            if chestsFound > 0 then
                                print("[VoraHub] Successfully claimed " .. chestsFound .. " pirate chests!")
                            else
                                print("[VoraHub] No pirate chests found in PirateChestStorage")
                            end
                        else
                            print("[VoraHub] PirateChestStorage not found in workspace")
                        end
                    end)
                    task.wait(2) -- Wait 2 seconds before scanning again
                end
            end)
            
            Window:Notify({
                Title = "Auto Pirate Chest ON! 🏴‍☠️",
                Content = "Auto claiming pirate chests enabled!",
                Duration = 4
            })
        else
            Window:Notify({
                Title = "Auto Pirate Chest OFF",
                Content = "Auto claiming pirate chests disabled!",
                Duration = 3
            })
        end
    end
})



AutoTab:CreateSection({ Name = "Auto Trade", Icon = "rbxassetid://7733955511" })

local TradeState         = {
    selectedPlayer = nil,
    selectedItem   = nil,
    tradeAmount    = 1,
    trading        = false,
    successCount   = 0,
    totalToTrade   = 0,
    awaiting       = false,
    currentGrouped = {},
    lastResult     = nil
}


function getGroupedByType(typeName)
    local items = Data:GetExpect({ "Inventory", "Items" })
    local grouped, values = {}, {}
    for _, item in ipairs(items) do
        local info = ItemUtility.GetItemDataFromItemType("Items", item.Id)
        if info and info.Data.Type == typeName then
            local name = info.Data.Name
            grouped[name] = grouped[name] or { count = 0, uuids = {} }
            grouped[name].count += (item.Quantity or 1)
            table.insert(grouped[name].uuids, item.UUID)
        end
    end
    for name, data in pairs(grouped) do
        table.insert(values, ("%s | Total %dx"):format(name, data.count))
    end
    return grouped, values
end

local tradeParagraph = AutoTab:CreateParagraph({
    Title = "Trade Status",
    Desc = "<font color='#999999'>Progress : Idle</font>",
    RichText = true
})

local function setStatus(text)
    if not text then
        text = "<font color='#999999'>Progress : Idle</font>"
    end
    tradeParagraph:SetDesc(text)
end

local itemDropdown = AutoTab:CreateDropdown({
	Name = "Select Item",
	Items = { "None" },
	Default = "None",
	Callback = function(value)
		if not value or value == "None" then
			TradeState.selectedItem = nil
		else
			TradeState.selectedItem = value:match("^(.-) %|") or value
		end
		setStatus(nil)
	end
})

AutoTab:CreateInput({
	Name = "Amount to Trade",
	SideLabel = "Amount to Trade",
	Placeholder = "Enter Number",
	Default = "1",
	Callback = function(value)
        TradeState.tradeAmount = tonumber(value) or 1
        setStatus(nil)
    end
})

AutoTab:CreateButton({
	Name = "Refresh Fish",
	Callback = function()
		local grouped, values = getGroupedByType("Fish")
		TradeState.currentGrouped = grouped
		itemDropdown:Refresh(values)
	end
})

AutoTab:CreateButton({
	Name = "Refresh Stone",
	Callback = function()
		local grouped, values = getGroupedByType("Enchant Stones")
		TradeState.currentGrouped = grouped
		itemDropdown:Refresh(values)
	end
})


local playerList = {}

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= Players.LocalPlayer then
        table.insert(playerList, plr.Name)
    end
end

if #playerList == 0 then
    table.insert(playerList, "None")
end

local playerDropdown = AutoTab:CreateDropdown({
	Name = "Select Player",
	Items = playerList,
    Default = playerList[1] or "None",
	Callback = function(value)
        if value == "None" then
            TradeState.selectedPlayer = nil
        else
            TradeState.selectedPlayer = value
        end
        setStatus(nil)
    end
})


AutoTab:CreateButton({
	Name = "Refresh Player",
	 Callback = function()
        local names = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= Players.LocalPlayer then
                table.insert(names, plr.Name)
            end
        end
        playerDropdown:Refresh(names)
    end
})

RETextNotification.OnClientEvent:Connect(function(data)
    if not TradeState.trading then return end
    if not data or not data.Text then return end
    local msg = data.Text

    if msg:find("Trade completed") then
        TradeState.awaiting = false
        TradeState.lastResult = "completed"
        setStatus("<font color='#00cc66'>Progress : Trade success</font>")
    elseif msg:find("Sent trade request") then
        setStatus("<font color='#daa520'>Progress : Waiting player...</font>")
    end
end)

TradingController.CompletedTrade = function()
    if TradeState.trading then
        TradeState.awaiting = false
        TradeState.lastResult = "completed"
    end
end
TradingController.OnTradeCancelled = function()
    if TradeState.trading then
        TradeState.awaiting = false
        TradeState.lastResult = "declined"
    end
end

function sendTrade(target, uuid, itemName)
    while TradeState.trading do
        TradeState.awaiting = true
        TradeState.lastResult = nil
        setStatus("<font color='#3399ff'>Sending " .. (itemName or "Item") .. "...</font>")

        pcall(function()
            tradeFunc:InvokeServer(target.UserId, uuid)
        end)

        local startTime = tick()
        while TradeState.trading and TradeState.awaiting do
            task.wait()
            if tick() - startTime > 6 then
                TradeState.awaiting = false
                TradeState.lastResult = "timeout"
                break
            end
        end

        if TradeState.lastResult == "completed" then
            TradeState.successCount += 1
            setStatus("<font color='#00cc66'>Success : " .. (itemName or "Item") .. "</font>")
            return true
        elseif TradeState.lastResult == "declined" or TradeState.lastResult == "timeout" then
            setStatus("<font color='#999999'>Skipped " .. (itemName or "Item") .. "</font>")
            return false
        else
            setStatus("<font color='#ffaa00'>Retrying " .. (itemName or "Item") .. "...</font>")
            task.wait(0.5)
        end
    end
    return false
end

function startTrade()
    if TradeState.trading then return end
    if not TradeState.selectedPlayer or not TradeState.selectedItem then
        return warn("Not Completed")
    end

    TradeState.trading = true
    TradeState.successCount = 0

    local itemData = TradeState.currentGrouped[TradeState.selectedItem]
    if not itemData then
        setStatus("<font color='#ff3333'>Item not found</font>")
        TradeState.trading = false
        return
    end

    local target = Players:FindFirstChild(TradeState.selectedPlayer)
    if not target then
        setStatus("<font color='#ff3333'>Player not found</font>")
        TradeState.trading = false
        return
    end

    local uuids = itemData.uuids
    TradeState.totalToTrade = math.min(TradeState.tradeAmount, #uuids)

    local i = 1
    while TradeState.trading and TradeState.successCount < TradeState.totalToTrade do
        local uuid = uuids[i]
        if not uuid then break end

        local ok = sendTrade(target, uuid, TradeState.selectedItem)

        -- naik item kalau sukses atau skip
        if ok or TradeState.lastResult == "declined" or TradeState.lastResult == "timeout" then
            i += 1
        end
    end

    TradeState.trading = false
    setStatus(string.format(
        "<font color='#66ccff'>Progress : All trades finished! (%d/%d)</font>",
        TradeState.successCount,
        TradeState.totalToTrade
    ))

    tradeParagraph.Desc = [[
<font color="rgb(255,105,180)">🌌 </font>
<font color="rgb(135,206,250)">VORAHUB TRADING COMPLETE!</font>
<font color="rgb(255,105,180)"> 🌌</font>
]]
end

AutoTab:CreateToggle({
	Name = "Auto Trade",
	Default = false,
	Callback = function(state)
        if state then
            spawn(startTrade)
        else
            TradeState.trading = false
            TradeState.awaiting = false
            setStatus("<font color='#999999'>Progress : Idle</font>")
        end
    end
})

AutoTab:CreateSection({ Name = "Auto Accept Trade", Icon = "rbxassetid://7733774602" })

AutoTab:CreateToggle({
	Name = "Auto Accept Trade",
	Default = false,
	   Callback = function(value)
        _G.AutoAccept = value
    end
})

spawn(function()
    while true do
        task.wait(0.5)
        if _G.AutoAccept then
            pcall(function()
                local promptGui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("Prompt")
                if promptGui and promptGui:FindFirstChild("Blackout") then
                    local blackout = promptGui.Blackout
                    if blackout:FindFirstChild("Options") then
                        local options = blackout.Options
                        local yesButton = options:FindFirstChild("Yes")                    
                        if yesButton then
                            local vr = game:GetService("VirtualInputManager") 
                            local absPos = yesButton.AbsolutePosition
                            local absSize = yesButton.AbsoluteSize                          
                            local clickX = absPos.X + (absSize.X / 2)
                            local clickY = absPos.Y + (absSize.Y / 2) + 50 
                            vr:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
                            task.wait(0.03)
                            vr:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)  
                        end
                    end
                end
            end)
        end
    end
end)

if getconnections then
    for _, conn in ipairs(getconnections(RETextNotification.OnClientEvent)) do
        if typeof(conn.Function) == "function" then
            local oldFn = conn.Function
            conn:Disable()
            RETextNotification.OnClientEvent:Connect(function(data)
                if data and data.Text then
                    if data.Text ~= "Sending trades too fast!"
                        and data.Text ~= "One or more people are already in a trade!"
                        and data.Text ~= "Trade was declined" then
                        oldFn(data)
                    end
                end
            end)
        end
    end
end


AutoTab:CreateSection({ Name = "Enchant Features", Icon = "rbxassetid://7733801202" })

function gStone()
    local it = Data:GetExpect({ "Inventory", "Items" })
    local t = 0
    for _, v in ipairs(it) do
        local i = ItemUtility.GetItemDataFromItemType("Items", v.Id)
        if i and i.Data.Type == "Enchant Stones" then t += v.Quantity or 1 end
    end
    return t
end

local enchantNames = {
    "Big Hunter 1", "Cursed 1", "Empowered 1", "Glistening 1",
    "Gold Digger 1", "Leprechaun 1", "Leprechaun 2",
    "Mutation Hunter 1", "Mutation Hunter 2", "Prismatic 1",
    "Reeler 1", "Stargazer 1", "Stormhunter 1", "XPerienced 1"
}

local enchantIdMap = {
    ["Big Hunter 1"] = 3, ["Cursed 1"] = 12, ["Empowered 1"] = 9,
    ["Glistening 1"] = 1, ["Gold Digger 1"] = 4, ["Leprechaun 1"] = 5,
    ["Leprechaun 2"] = 6, ["Mutation Hunter 1"] = 7, ["Mutation Hunter 2"] = 14,
    ["Prismatic 1"] = 13, ["Reeler 1"] = 2, ["Stargazer 1"] = 8,
    ["Stormhunter 1"] = 11, ["XPerienced 1"] = 10
}

function countDisplayImageButtons()
    local success, backpackGui = pcall(function() return LocalPlayer.PlayerGui.Backpack end)
    if not success or not backpackGui then return 0 end
    local display = backpackGui:FindFirstChild("Display")
    if not display then return 0 end
    local imageButtonCount = 0
    for _, child in ipairs(display:GetChildren()) do
        if child:IsA("ImageButton") then
            imageButtonCount += 1
        end
    end
    return imageButtonCount
end

function findEnchantStones()
      ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
    if not Data then return {} end
    
    -- Use cache if available
    local cached = DataCache:Get("enchantStones")
    if cached then return cached end
    
    local inventory = Data:GetExpect({ "Inventory", "Items" })
    if not inventory then return {} end
    local stones = {}
    for _, item in pairs(inventory) do
        local def = ItemUtility:GetItemData(item.Id)
        if def and def.Data and def.Data.Type == "Enchant Stones" then
            table.insert(stones, { UUID = item.UUID, Quantity = item.Quantity or 1 })
        end
    end
    
    -- Cache the result
    DataCache:Set("enchantStones", stones)
    return stones
end

function getEquippedRodName()
    -- Use cached data if available
    local equipped = DataCache:Get("equipped")
    local rods = DataCache:Get("rods")
    
    if not equipped then
        equipped = Data:Get("EquippedItems") or {}
        DataCache:Set("equipped", equipped)
    end
    
    if not rods then
        rods = Data:GetExpect({ "Inventory", "Fishing Rods" }) or {}
        DataCache:Set("rods", rods)
    end
    
    for _, uuid in pairs(equipped) do
        for _, rod in ipairs(rods) do
            if rod.UUID == uuid then
                local itemData = ItemUtility:GetItemData(rod.Id)
                if itemData and itemData.Data and itemData.Data.Name then
                    return itemData.Data.Name
                elseif rod.ItemName then
                    return rod.ItemName
                end
            end
        end
    end
    return "None"
end

function getCurrentRodEnchant()
    if not Data then return nil end
    local equipped = Data:Get("EquippedItems") or {}
    local rods = Data:GetExpect({ "Inventory", "Fishing Rods" }) or {}
    for _, uuid in pairs(equipped) do
        for _, rod in ipairs(rods) do
            if rod.UUID == uuid and rod.Metadata and rod.Metadata.EnchantId then
                return rod.Metadata.EnchantId
            end
        end
    end
    return nil
end


local Paragraph = AutoTab:CreateParagraph({
	Title = "Enchanting Features",
	Content = "Rod Active = <font color='#00aaff'>Demascus Rod</font>\nEnchant Now = <font color='#ff00ff'>None</font>\nEnchant Stone Left = <font color='#ffff00'>0</font>"
})

spawn(LPH_NO_VIRTUALIZE(function()
    local lastRodName, lastEnchantName, lastTotalStones = "", "", 0
    
    while task.wait(4) do -- Increased from 1s to 4s to reduce CPU usage
        local stones = findEnchantStones()
        local totalStones = 0
        for _, s in ipairs(stones) do
            totalStones += s.Quantity or 0
        end
        local rodName = getEquippedRodName()
        local currentEnchantId = getCurrentRodEnchant()
        local currentEnchantName = "None"
        if currentEnchantId then
            for name, id in pairs(enchantIdMap) do
                if id == currentEnchantId then
                    currentEnchantName = name
                    break
                end
            end
        end
        
        -- Only update UI if values have changed
        if rodName ~= lastRodName or currentEnchantName ~= lastEnchantName or totalStones ~= lastTotalStones then
            local desc =
                "Rod Active <font color='rgb(0,191,255)'>= " .. rodName .. "</font>\n" ..
                "Enchant Now <font color='rgb(200,0,255)'>= " .. currentEnchantName .. "</font>\n" ..
                "Enchant Stone Left <font color='rgb(255,215,0)'>= " .. totalStones .. "</font>"
            Paragraph:SetDesc(desc)
            
            lastRodName = rodName
            lastEnchantName = currentEnchantName
            lastTotalStones = totalStones
        end
    end
end))

AutoTab:CreateButton({
	Name = "Teleport to Altar",
	Icon = "rbxassetid://128755575520135",
 Callback = function()
        local targetCFrame = CFrame.new(3234.83667, -1302.85486, 1398.39087, 0.464485794, -1.12043161e-07, -0.885580599, 6.74793981e-08, 1, -9.11265872e-08, 0.885580599, -1.74314394e-08, 0.464485794)
        local character = LocalPlayer.Character
        if character then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                humanoidRootPart.CFrame = targetCFrame
            end
        end
    end
})

AutoTab:CreateButton({
	Name = "Teleport to Second Altar",
	Icon = "rbxassetid://7733920644",
	 Callback = function()
        local character = LocalPlayer.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            local targetCFrame = CFrame.new(1481, 128, -592)
            character:PivotTo(targetCFrame)
        end
    end
})

AutoTab:CreateDropdown({
	Name = "Target Enchant",
  Items = enchantNames,
    Value = _G.TargetEnchant or enchantNames[1],
    Callback = function(selected)
        _G.TargetEnchant = selected
    end
})

AutoTab:CreateToggle({
	Name = "Auto Enchant",
  Value = _G.AutoEnchant,
    Callback = function(value)
        _G.AutoEnchant = value
    end
})

function getData(stoneId)
    local rod, ench, stones, uuids = "None", "None", 0, {}
    local equipped = Data:Get("EquippedItems") or {}
    local rods = Data:Get({ "Inventory", "Fishing Rods" }) or {}

    for _, u in pairs(equipped) do
        for _, r in ipairs(rods) do
            if r.UUID == u then
                local d = ItemUtility:GetItemData(r.Id)
                rod = (d and d.Data.Name) or r.ItemName or "None"
                if r.Metadata and r.Metadata.EnchantId then
                    local e = ItemUtility:GetEnchantData(r.Metadata.EnchantId)
                    ench = (e and e.Data.Name) or "None"
                end
            end
        end
    end

    for _, it in pairs(Data:GetExpect({ "Inventory", "Items" })) do
        local d = ItemUtility:GetItemData(it.Id)
        if d and d.Data.Type == "Enchant Stones" and it.Id == stoneId then
            stones += 1
            table.insert(uuids, it.UUID)
        end
    end
    return rod, ench, stones, uuids
end

AutoTab:CreateButton({
	Name = "Start Double Enchant",
	Icon = "rbxassetid://7733920644",
	  Callback = function()
        task.spawn(function()
            local rod, ench, s, uuids = getData(246)
            if rod == "None" or s <= 0 then return end

            local slot, start = nil, tick()
            while tick() - start < 5 do
                for sl, id in pairs(Data:Get("EquippedItems") or {}) do
                    if id == uuids[1] then slot = sl end
                end
                if slot then break end
                equipItemRemote:FireServer(uuids[1], "EnchantStones")
                task.wait(0.3)
            end
            if not slot then return end

            equipToolRemote:FireServer(slot)
            task.wait(0.2)
            activateAltarRemote2:FireServer()
        end)
    end
})

spawn( LPH_NO_VIRTUALIZE( function()
    while task.wait(0.8) do -- CRITICAL FIX: Added 0.8s wait (was task.wait() with no delay!)
        if _G.AutoEnchant then
            local currentEnchantId = getCurrentRodEnchant()
            local targetEnchantId = enchantIdMap[_G.TargetEnchant]

            if currentEnchantId == targetEnchantId then
                _G.AutoEnchant = false
                break
            end

            local enchantStones = findEnchantStones()
            if #enchantStones > 0 then
                local enchantStone = enchantStones[1]
                local args = { enchantStone.UUID, "Enchant Stones" }
                pcall(function()
                    equipItemRemote:FireServer(unpack(args))
                end)

                task.wait(1)

                local imageButtonCount = countDisplayImageButtons()
                local slotNumber = imageButtonCount - 2
                if slotNumber < 1 then slotNumber = 1 end

                pcall(function()
                    equipToolRemote:FireServer(slotNumber)
                end)

                task.wait(1)

                pcall(function()
                    activateAltarRemote:FireServer()
                end)
            else
                -- No stones available, wait longer before checking again
                task.wait(2)
            end

            task.wait(5)
        end
    end
end))

------------------ Player Tab ------------------
local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

PlayerTab:CreateInput({
	Name = "Walk Speed",
	SideLabel = "Contoh: 18",
	Placeholder = "Enter Speed...",
	Default = "",
	Callback = function(value)
        local hum = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = tonumber(value) or 18
        end
    end
})

PlayerTab:CreateInput({
	Name = "Jump Power",
	SideLabel = "Contoh: 50",
	Placeholder = "Enter Power...",
	Default = "",
	Callback = function(Text)
		local hum = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            hum.JumpPower = tonumber(value) or 50
        end
    end
})

local UserInputService = game:GetService("UserInputService")

PlayerTab:CreateToggle({
	Name = "Infinite Jump",
	Default = false,
 Callback = function(Value)
        _G.InfiniteJump = Value
        if Value then
            print("✅ Infinite Jump Active")
            InfiniteJumpConnection = UserInputService.JumpRequest:Connect(function()
                if _G.InfiniteJump then
                    local character = Player.Character or Player.CharacterAdded:Wait()
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end
            end)
        else
            print("❌ Infinite Jump Inactive")
            end
        end
})

PlayerTab:CreateToggle({
	Name = "Noclip",
	Default = false,
	 Callback = function(state)
        _G.Noclip = state
        task.spawn(function()
            local Player = game:GetService("Players").LocalPlayer
            while _G.Noclip do
                task.wait(0.1)
                if Player.Character then
                    for _, part in pairs(Player.Character:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide == true then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)
    end
})

PlayerTab:CreateToggle({
	Name = "Radar",
	Default = false,
	   Callback = function(state)
        local Lighting = game:GetService("Lighting")
        local Replion = require(ReplicatedStorage.Packages.Replion).Client:GetReplion("Data")
        local NetFunction = require(ReplicatedStorage.Packages.Net):RemoteFunction("UpdateFishingRadar")

        if Replion and NetFunction:InvokeServer(state) then
            local sound = require(ReplicatedStorage.Shared.Soundbook).Sounds.RadarToggle:Play()
            sound.PlaybackSpeed = 1 + math.random() * 0.3

            local c = Lighting:FindFirstChildWhichIsA("ColorCorrectionEffect")
            if c then
                require(ReplicatedStorage.Packages.spr).stop(c)

                local time = require(ReplicatedStorage.Controllers.ClientTimeController)
                local profile = time._getLightingProfile and time:_getLightingProfile() or {}
                local correction = profile.ColorCorrection or {}
                correction.Brightness = correction.Brightness or 0.04
                correction.TintColor = correction.TintColor or Color3.fromRGB(255,255,255)

                if state then
                    c.TintColor = Color3.fromRGB(42, 226, 118)
                    c.Brightness = 0.4
                else
                    c.TintColor = Color3.fromRGB(255, 0, 0)
                    c.Brightness = 0.2
                end

                require(ReplicatedStorage.Packages.spr).target(c, 1, 1, correction)
            end

            require(ReplicatedStorage.Packages.spr).stop(Lighting)
            Lighting.ExposureCompensation = 1
            require(ReplicatedStorage.Packages.spr).target(Lighting, 1, 2, {ExposureCompensation = 0})
        end
    end
})

PlayerTab:CreateToggle({
	Name = "Diving Gear",
	Default = false,
	 Callback = function(state)
        _G.DivingGear = state
        local RemoteFolder = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net
        if state then
            RemoteFolder["RF/EquipOxygenTank"]:InvokeServer(105)
        else
            RemoteFolder["RF/UnequipOxygenTank"]:InvokeServer()
        end
    end
})

PlayerTab:CreateButton({
	Name = "FlyGui V3",
	Icon = "rbxassetid://7733920644",
	 Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/XNEOFF/FlyGuiV3/main/FlyGuiV3.txt"))()
        Notify("Fly GUI Activated")
    end
})


ShopTab:CreateSection({ Name = "Buy Rod" })

local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RFPurchaseFishingRod = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseFishingRod"]  

local rods = {  
    ["Luck Rod"] = 79,  
    ["Carbon Rod"] = 76,  
    ["Grass Rod"] = 85,
    ["Demascus Rod"] = 77,  
    ["Ice Rod"] = 78,  
    ["Lucky Rod"] = 4,  
    ["Midnight Rod"] = 80,  
    ["Steampunk Rod"] = 6,  
    ["Chrome Rod"] = 7,  
    ["Astral Rod"] = 5,  
    ["Ares Rod"] = 126,  
    ["Angler Rod"] = 168,
    ["Bamboo Rod"] = 258
}  

local rodNames = {  
    "Luck Rod (350 Coins)", "Carbon Rod (900 Coins)", "Grass Rod (1.5k Coins)", "Demascus Rod (3k Coins)",  
    "Ice Rod (5k Coins)", "Lucky Rod (15k Coins)", "Midnight Rod (50k Coins)", "Steampunk Rod (215k Coins)",  
    "Chrome Rod (437k Coins)", "Astral Rod (1M Coins)", "Ares Rod (3M Coins)", "Angler Rod (8M Coins)",
    "Bamboo Rod (12M Coins)"
}  

local rodKeyMap = {  
    ["Luck Rod (350 Coins)"]="Luck Rod",  
    ["Carbon Rod (900 Coins)"]="Carbon Rod",  
    ["Grass Rod (1.5k Coins)"]="Grass Rod",  
    ["Demascus Rod (3k Coins)"]="Demascus Rod",  
    ["Ice Rod (5k Coins)"]="Ice Rod",  
    ["Lucky Rod (15k Coins)"]="Lucky Rod",  
    ["Midnight Rod (50k Coins)"]="Midnight Rod",  
    ["Steampunk Rod (215k Coins)"]="Steampunk Rod",  
    ["Chrome Rod (437k Coins)"]="Chrome Rod",  
    ["Astral Rod (1M Coins)"]="Astral Rod",  
    ["Ares Rod (3M Coins)"]="Ares Rod",  
    ["Angler Rod (8M Coins)"]="Angler Rod",
    ["Bamboo Rod (12M Coins)"]="Bamboo Rod"
}  

local selectedRod = rodNames[1]  

ShopTab:CreateDropdown({
	Name = "Select Rod",
	  Items = rodNames,  
    Value = selectedRod,  
    Callback = function(value)  
        selectedRod = value  
    end  
})  


ShopTab:CreateButton({
	Name = "Buy Rod",
	Icon = "rbxassetid://7733920644",
	 Callback=function()  
        local key = rodKeyMap[selectedRod]  
        if key and rods[key] then  
            local success, err = pcall(function()  
                RFPurchaseFishingRod:InvokeServer(rods[key])  
            end)  
            if success then  
                Window:Notify({Title="Rod Purchase", Content="Purchased "..selectedRod, Duration=3})  
            else  
                Window:Notify({Title="Rod Purchase Error", Content=tostring(err), Duration=5})  
            end  
        end  
    end  
})

ShopTab:CreateSection({ Name = "Buy Baits" })

local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RFPurchaseBait = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseBait"]  

local baits = {
    ["TopWater Bait"] = 10,
    ["Lucky Bait"] = 2,
    ["Midnight Bait"] = 3,
    ["Chroma Bait"] = 6,
    ["Dark Mater Bait"] = 8,
    ["Corrupt Bait"] = 15,
    ["Aether Bait"] = 16
}

local baitNames = {
    "TopWater Bait (100 Coins)",
    "Lucky Bait (1k Coins)",
    "Midnight Bait (3k Coins)",
    "Chroma Bait (290k Coins)",
    "Dark Mater Bait (630k Coins)",
    "Corrupt Bait (1.15M Coins)",
    "Aether Bait (3.7M Coins)"
}

local baitKeyMap = {
    ["TopWater Bait (100 Coins)"] = "TopWater Bait",
    ["Lucky Bait (1k Coins)"] = "Lucky Bait",
    ["Midnight Bait (3k Coins)"] = "Midnight Bait",
    ["Chroma Bait (290k Coins)"] = "Chroma Bait",
    ["Dark Mater Bait (630k Coins)"] = "Dark Mater Bait",
    ["Corrupt Bait (1.15M Coins)"] = "Corrupt Bait",
    ["Aether Bait (3.7M Coins)"] = "Aether Bait"
}

local selectedBait = baitNames[1]  

ShopTab:CreateDropdown({
	Name = "Select Bait",
	 Items = baitNames,  
    Value = selectedBait,  
    Callback = function(value)  
        selectedBait = value  
    end  
})  

ShopTab:CreateButton({
	Name = "Buy Bait",
	Icon = "rbxassetid://7733920644",
 Callback = function()  
        local key = baitKeyMap[selectedBait]  
        if key and baits[key] then  
            local success, err = pcall(function()  
                RFPurchaseBait:InvokeServer(baits[key])  
            end)  
            if success then  
                Window:Notify({Title = "Bait Purchase", Content = "Purchased " .. selectedBait, Duration = 3})  
            else  
                Window:Notify({Title = "Bait Purchase Error", Content = tostring(err), Duration = 5})  
            end  
        end  
    end  
})


ShopTab:CreateSection({ Name = "Buy Weather Event", Icon = "rbxassetid://7733955511" })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RFPurchaseWeatherEvent = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseWeatherEvent"]

-- Data cuaca
local weathers = {
    ["Wind"] = "Wind",
    ["Cloudy"] = "Cloudy",
    ["Snow"] = "Snow",
    ["Storm"] = "Storm",
    ["Radiant"] = "Radiant",
    ["Shark Hunt"] = "Shark Hunt"
}

-- Nama tampilan
local weatherNames = {
    "Windy (10k Coins)",
    "Cloudy (20k Coins)",
    "Snow (15k Coins)",
    "Stormy (35k Coins)",
    "Radiant (50k Coins)",
    "Shark Hunt (300k Coins)"
}

-- Mapping nama → key internal
local weatherKeyMap = {
    ["Windy (10k Coins)"] = "Wind",
    ["Cloudy (20k Coins)"] = "Cloudy",
    ["Snow (15k Coins)"] = "Snow",
    ["Stormy (35k Coins)"] = "Storm",
    ["Radiant (50k Coins)"] = "Radiant",
    ["Shark Hunt (300k Coins)"] = "Shark Hunt"
}

local selectedWeathers = {}
local autoBuyRunning = false

ShopTab:CreateMultiDropdown({
	Name = "Select Weather Events",
	Items = weatherNames,
    Default = selectedWeathers,
    Callback = function(values)
        selectedWeathers = values
        print("Selected:", table.concat(values, ", "))
    end
})


ShopTab:CreateToggle({
	Name = "Auto Buy Selected Weathers",
	SubText = "Continuously purchase all selected weather events while ON",
	Default = false,
 Callback = function(state)
        autoBuyRunning = state

        if state then
            if #selectedWeathers == 0 then
                Window:Notify({
                    Title = "⚠️ No Selection",
                    Content = "Please select at least one weather event before enabling.",
                    Duration = 3
                })
                autoBuyRunning = false
                return
            end

            Window:Notify({
                Title = "🌤️ Auto Buy Enabled",
                Content = "Auto-purchase started. It will keep buying until turned off.",
                Duration = 3
            })

            -- Jalankan loop di thread terpisah
            task.spawn(function()
                while autoBuyRunning do
                    for _, selected in ipairs(selectedWeathers) do
                        local key = weatherKeyMap[selected]
                        if key and weathers[key] then
                            local success, err = pcall(function()
                                RFPurchaseWeatherEvent:InvokeServer(weathers[key])
                            end)
                        else
                            Window:Notify({
                                Title = "⚠️ Invalid Weather",
                                Content = "Invalid selection: " .. tostring(selected),
                                Duration = 3
                            })
                        end
                        task.wait(0.5)
                    end

                    task.wait(5) -- Increased from 2s to 5s to reduce CPU usage
                end
            end)
        else
            Window:Notify({
                Title = "🛑 Auto Buy Disabled",
                Content = "Weather auto-purchase stopped.",
                Duration = 3
            })
        end
    end
})


TeleportTab:CreateSection({ Name = "Island", Icon = "rbxassetid://7733955511" })

local IslandLocations = {
    ["Ancient Ruins"] = Vector3.new(6009, -585, 4691),
    ["Ancient Jungle"] = Vector3.new(1518, 1, -186),
    ["Coral Refs"] = Vector3.new(-2855, 47, 1996),
    ["Crater Island"] = Vector3.new(997, 1, 5012),
    ["Classic Island"] = Vector3.new(1438, 45, 2778),
    ["Enchant Room"] = Vector3.new(3221, -1303, 1406),
    ["Enchant Room 2"] = Vector3.new(1480, 126, -585),
    ["Esoteric Island"] = Vector3.new(1990, 5, 1398),
    ["Fisherman Island"] = Vector3.new(-175, 3, 2772),
    ["Iron Cavern"] = Vector3.new(-8790, -585, 94),
    ["Iron Cafe"] = Vector3.new(-8643, -547, 160),
    ["Kohana Volcano"] = Vector3.new(-545.302429, 17.1266193, 118.870537),
    ["Konoha"] = Vector3.new(-603, 3, 719),
    ["Lost Isle"] = Vector3.new(-3643, 1, -1061),
    ["Sacred Temple"] = Vector3.new(1498, -23, -644),
    ["Sysyphus Statue"] = Vector3.new(-3783.26807, -135.073914, -949.946289),
    ["Treasure Room"] = Vector3.new(-3600, -267, -1575),
    ["Tropical Grove"] = Vector3.new(-2091, 6, 3703),
    ["Weather Machine"] = Vector3.new(-1508, 6, 1895),
    ["Christmas island"] = Vector3.new(1138.14966, 23.5075855, 1560.2113, 0.423432112, -1.18154251e-08, -0.905927837, -3.26613829e-08, 1, -2.83083299e-08, 0.905927837, 4.1575511e-08, 0.423432112),
    ["Pirate Cave"] = Vector3.new(3398.86011, 4.19197035, 3480.54517, 0.617785096, -6.47339746e-08, -0.786346972, 3.20196716e-11, 1, -8.22972481e-08, 0.786346972, 5.0816837e-08, 0.617785096),
    ["Pirate Treasure room"] = Vector3.new(3299.81274, -305.034851, 3041.50952, -0.483591467, 2.84460047e-08, -0.875293851, -4.8970314e-08, 1, 5.95544378e-08, 0.875293851, 7.1663429e-08, -0.483591467),
}

local SelectedIsland = nil

TeleportTab:CreateDropdown({
	Name = "Select Island",
	 Items = (function()
        local keys = {}
        for name in pairs(IslandLocations) do
            table.insert(keys, name)
        end
        table.sort(keys)
        return keys
    end)(),
    Callback = function(Value)
        SelectedIsland = Value
    end
})

TeleportTab:CreateButton({
	Name = "Teleport to Island",
	Icon = "rbxassetid://7733920644",
	  Callback = function()
        if SelectedIsland and IslandLocations[SelectedIsland] and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            Player.Character.HumanoidRootPart.CFrame = CFrame.new(IslandLocations[SelectedIsland])
        end
    end
})

TeleportTab:CreateSection({ Name = "Tp To Player", Icon = "rbxassetid://7733955511" })

local SelectedPlayer = nil

local FishingDropdown = TeleportTab:CreateDropdown({
	Name = "Select Player",
	Items = (function()
        local players = {}
        for _, plr in pairs(game.Players:GetPlayers()) do
            if plr.Name ~= Player.Name then
                table.insert(players, plr.Name)
            end
        end
        table.sort(players)
        return players
    end)(),
    Callback = function(Value)
        SelectedPlayer = Value
    end
})

local function RefreshPlayerList()
    local list = {}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= Player.Name then
            table.insert(list, plr.Name)
        end
    end
    table.sort(list)
    FishingDropdown:Refresh(list)
end

game.Players.PlayerAdded:Connect(RefreshPlayerList)
game.Players.PlayerRemoving:Connect(RefreshPlayerList)

TeleportTab:CreateButton({
	Name = "Teleport to Player",
	Icon = "rbxassetid://7733920644",
	 Callback = function()
        if SelectedPlayer then
            local target = game.Players:FindFirstChild(SelectedPlayer)
            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                    Player.Character.HumanoidRootPart.CFrame =
                        target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 2, 0)
                end
            end
        end
    end
})

TeleportTab:CreateSection({ Name = "Location NPC", Icon = "rbxassetid://7733955511" })

local NPC_Locations = {
    ["Alex"] = Vector3.new(43,17,2876),
    ["Aura kid"] = Vector3.new(70,17,2835),
    ["Billy Bob"] = Vector3.new(84,17,2876),
    ["Boat Expert"] = Vector3.new(32,9,2789),
    ["Esoteric Gatekeeper"] = Vector3.new(2101,-30,1350),
    ["Jeffery"] = Vector3.new(-2771,4,2132),
    ["Joe"] = Vector3.new(144,20,2856),
    ["Jones"] = Vector3.new(-671,16,596),
    ["Lava Fisherman"] = Vector3.new(-593,59,130),
    ["McBoatson"] = Vector3.new(-623,3,719),
    ["Ram"] = Vector3.new(-2838,47,1962),
    ["Ron"] = Vector3.new(-48,17,2856),
    ["Scott"] = Vector3.new(-19,9,2709),
    ["Scientist"] = Vector3.new(-6,17,2881),
    ["Seth"] = Vector3.new(107,17,2877),
    ["Silly Fisherman"] = Vector3.new(97,9,2694),
    ["Tim"] = Vector3.new(-604,16,609),
}

local SelectedNPC = nil

TeleportTab:CreateDropdown({
	Name = "Select NPC",
	Items = (function()
        local keys = {}
        for name in pairs(NPC_Locations) do
            table.insert(keys, name)
        end
        table.sort(keys)
        return keys
    end)(),
    Callback = function(Value)
        SelectedNPC = Value
    end
})

TeleportTab:CreateButton({
	Name = "Teleport to NPC",
	Icon = "rbxassetid://7733920644",
	 Callback = function()
        if SelectedNPC and NPC_Locations[SelectedNPC] and Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
            Player.Character.HumanoidRootPart.CFrame = CFrame.new(NPC_Locations[SelectedNPC])
        end
    end
})

TeleportTab:CreateSection({ Name = "Event Teleporter", Icon = "rbxassetid://7733955511" })

-- ⚙️ Auto Event TP System (Multi-select Dropdown + Spam Teleport)

local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(c)
	character = c
	hrp = c:WaitForChild("HumanoidRootPart")
end)

-- Settings
local megCheckRadius = 150

-- Control states
local autoEventTPEnabled = false
local selectedEvents = {}
local createdEventPlatform = nil

-- Event configurations (with priority)
local eventData = {
	["Worm Hunt"] = {
		TargetName = "Model",
		Locations = {
			Vector3.new(2190.85, -1.4, 97.575), 
			Vector3.new(-2450.679, -1.4, 139.731), 
			Vector3.new(-267.479, -1.4, 5188.531),
			Vector3.new(-327, -1.4, 2422)
		},
		PlatformY = 107,
		Priority = 1,
		Icon = "fish"
	},
	["Megalodon Hunt"] = {
		TargetName = "Megalodon Hunt",
		Locations = {
			Vector3.new(-1076.3, -1.4, 1676.2),
			Vector3.new(-1191.8, -1.4, 3597.3),
			Vector3.new(412.7, -1.4, 4134.4),
		},
		PlatformY = 107,
		Priority = 2,
		Icon = "anchor"
	},
	["Ghost Shark Hunt"] = {
		TargetName = "Ghost Shark Hunt",
		Locations = {
			Vector3.new(489.559, -1.35, 25.406), 
			Vector3.new(-1358.216, -1.35, 4100.556), 
			Vector3.new(627.859, -1.35, 3798.081)
		},
		PlatformY = 107,
		Priority = 3,
		Icon = "fish"
	},
	["Shark Hunt"] = {
		TargetName = "Shark Hunt",
		Locations = {
			Vector3.new(1.65, -1.35, 2095.725),
			Vector3.new(1369.95, -1.35, 930.125),
			Vector3.new(-1585.5, -1.35, 1242.875),
			Vector3.new(-1896.8, -1.35, 2634.375)
		},
		PlatformY = 107,
		Priority = 4,
		Icon = "fish"
	},
}

local eventNames = {}
for name in pairs(eventData) do
	table.insert(eventNames, name)
end

-- Utility
local function destroyEventPlatform()
	if createdEventPlatform and createdEventPlatform.Parent then
		createdEventPlatform:Destroy()
		createdEventPlatform = nil
	end
end

local function createAndTeleportToPlatform(targetPos, y)
	destroyEventPlatform()

	local platform = Instance.new("Part")
	platform.Size = Vector3.new(5, 1, 5)
	platform.Position = Vector3.new(targetPos.X, y, targetPos.Z)
	platform.Anchored = true
	platform.Transparency = 1
	platform.CanCollide = true
	platform.Name = "EventPlatform"
	platform.Parent = Workspace
	createdEventPlatform = platform

	hrp.CFrame = CFrame.new(platform.Position + Vector3.new(0, 3, 0))
end

local function runMultiEventTP()
	selectedEvents = type(selectedEvents) == "table" and selectedEvents or {}

	while autoEventTPEnabled do
		local sorted = {}

		for _, e in ipairs(selectedEvents) do
			local cfg = eventData[e]
			if type(cfg) == "table" then
				table.insert(sorted, cfg)
			end
		end

		table.sort(sorted, function(a, b)
			return (a.Priority or 0) < (b.Priority or 0)
		end)

		for _, config in ipairs(sorted) do
			if type(config.Locations) ~= "table" then
				continue
			end

			local foundTarget, foundPos

			if config.TargetName == "Model" then
				local menuRings = Workspace:FindFirstChild("!!! MENU RINGS")
				if menuRings then
					for _, props in ipairs(menuRings:GetChildren()) do
						if props.Name == "Props" then
							local model = props:FindFirstChild("Model")
							if model and model.PrimaryPart then
								for _, loc in ipairs(config.Locations) do
									if (model.PrimaryPart.Position - loc).Magnitude <= megCheckRadius then
										foundTarget = model
										foundPos = model.PrimaryPart.Position
										break
									end
								end
							end
						end
						if foundTarget then break end
					end
				end
			else
				for _, loc in ipairs(config.Locations) do
					for _, d in ipairs(Workspace:GetDescendants()) do
						if d.Name == config.TargetName then
							local pos = d:IsA("BasePart") and d.Position
								or (d.PrimaryPart and d.PrimaryPart.Position)
							if pos and (pos - loc).Magnitude <= megCheckRadius then
								foundTarget = d
								foundPos = pos
								break
							end
						end
					end
					if foundTarget then break end
				end
			end

			if foundTarget and foundPos then
				createAndTeleportToPlatform(foundPos, config.PlatformY)
			end
		end

		task.wait(0.05)
	end

	destroyEventPlatform()
end


TeleportTab:CreateDropdown({
	Name = "Select Fish Events",
	Items = eventNames,
	Callback = function(value)
		selectedEvents = { value } -- paksa jadi table
		print("[EventTP] Selected Event:", value)
	end
})


TeleportTab:CreateToggle({
	Name = "Auto Fish Event TP",
	Default = false,
	Callback = function(state)
		autoEventTPEnabled = state
		if state then
			task.spawn(runMultiEventTP)
		else
		end
	end
})

TeleportTab:CreateSection({ Name = "Winter Cavern (Christmas Cave Event)", Icon = "rbxassetid://7733801202" })

autoChristmasCaveEnabled = false
previousCFrame = nil
wasInCave = false

targetCaveCFrame = CFrame.new(
    457.491913, -580.58136, 8907.0459,
    0.00628850982, 2.50354376e-10, -0.999980211,
    6.77411549e-08, 1, 6.76358691e-10,
    0.999980211, -6.77440681e-08, 0.00628850982
)

function getCaveStatus()
    local possibleTeleporters = {"CavernTeleporter", "WinterCavernTeleporter", "ChristmasCavernTeleporter", "CaveTeleporter", "WinterCaveTeleporter"}
    local teleporterGui = nil
    for _, name in ipairs(possibleTeleporters) do
        teleporterGui = workspace.Map:FindFirstChild(name)
        if teleporterGui then break end
    end
    
    if not teleporterGui then return nil end
    
    local startTeleport = teleporterGui:FindFirstChild("StartTeleport")
    if not startTeleport then return nil end
    
    local gui = startTeleport:FindFirstChild("Gui")
    if not gui then return nil end
    
    local frame = gui:FindFirstChild("Frame")
    if not frame then return nil end
    
    local possibleLabels = {"NewLabel", "Label", "TextLabel", "StatusLabel", "Title"}
    local label = nil
    for _, lname in ipairs(possibleLabels) do
        label = frame:FindFirstChild(lname)
        if label and label:IsA("TextLabel") and label.Text ~= "" then break end
    end
    
    if not label then return nil end
    
    local textLower = string.lower(label.Text)
    
    if string.find(textLower, "close") or string.find(textLower, "closed") or string.find(textLower, "coming soon") or string.find(textLower, "wait") then
        return "closed"
    elseif string.find(textLower, "open") or string.find(textLower, "enter") or string.find(textLower, "winter cavern") or string.find(textLower, "active") or string.find(textLower, "christmas cave") then
        return "open"
    end
    
    return nil
end

function runAutoChristmasCave()
    wasInCave = false
    previousCFrame = nil
    
    while autoChristmasCaveEnabled do
        local status = getCaveStatus()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        
        if hrp and status then
            if status == "open" then
                if not wasInCave then
                    previousCFrame = hrp.CFrame
                    hrp.CFrame = targetCaveCFrame
                    Window:Notify({
                        Title = "Winter Cavern OPEN! ❄️🎄",
                        Content = "Cave BUKA 30 menit! Auto TP masuk grind WinterFrost Shark & Icebreaker Whale!",
                        Duration = 9
                    })
                    wasInCave = true
                end
            elseif status == "closed" then
                if wasInCave and previousCFrame then
                    hrp.CFrame = previousCFrame
                    Window:Notify({
                        Title = "Winter Cavern CLOSED ⛄",
                        Content = "Cave TUTUP. Auto balik posisi lama. Next open ~1.5-2 jam!",
                        Duration = 8
                    })
                    wasInCave = false
                    previousCFrame = nil
                end
            end
        end
        
        task.wait(8)
    end
end

TeleportTab:CreateToggle({
	Name = "Auto TP Winter Cavern (Detect Open/Close)",
	Default = false,
	  Callback = function(state)
        autoChristmasCaveEnabled = state
        if state then
            task.spawn(runAutoChristmasCave)
            Window:Notify({
                Title = "Auto Detect ON ❄️",
                Content = "Monitoring Winter Cavern setiap 8 detik. Open → TP masuk, Close → balik otomatis.",
                Duration = 10
            })
        else
            Window:Notify({ Title = "Auto Detect OFF", Content = "Auto TP Winter Cavern dimatikan.", Duration = 4 })
        end
    end
})

TeleportTab:CreateButton({
	Name = "Manual TP Inside Winter Cavern",
	Icon = "rbxassetid://7733920644",
 Callback = function()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            previousCFrame = hrp.CFrame
            hrp.CFrame = targetCaveCFrame
            Window:Notify({ Title = "TP Success ❄️", Content = "Berhasil masuk Winter Cavern!", Duration = 6 })
        end
    end
})

TeleportTab:CreateButton({
	Name = "Balik ke Posisi Sebelum TP",
	Icon = "rbxassetid://7733920644",
	  Callback = function()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp and previousCFrame then
            hrp.CFrame = previousCFrame
            Window:Notify({ Title = "Back Success", Content = "Kembali ke posisi sebelumnya!", Duration = 5 })
            previousCFrame = nil
        end
    end
})

TeleportTab:CreateSection({ Name = "Leviathan Event", Icon = "rbxassetid://7733801202" })

-- Variabel global untuk simpan posisi awal
local savedStartCFrame = nil

-- Auto simpan posisi awal saat script pertama kali dijalankan (misalnya di lobby/spawn)
spawn(function()
    local player = game.Players.LocalPlayer
    
    -- Tunggu character muncul
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Auto simpan posisi saat ini sebagai posisi awal
    savedStartCFrame = humanoidRootPart.CFrame
    
    -- Optional: Kasih notif biar tau udah auto save
    game.StarterGui:SetCore("SendNotification", {
        Title = "Auto Save Position",
        Text = "Posisi awal otomatis disimpan!",
        Duration = 4
    })
end)

-- Target CFrame untuk Leviathan Event
local targetEventCFrame = CFrame.new(
    16.7717381, 4.65576172, 2430.92822, 
    0.0186407156, -0.0800831094, 0.99661386, 
    7.13295689e-09, 0.996787071, 0.0800970271, 
    -0.999826252, -0.00149305887, 0.018580826
)

-- Function untuk parse waktu dari label (format: "1m 30s" atau "45s")
local function parseTimeToSeconds(timeText)
    if not timeText or timeText == "" then return nil end
    
    local minutes = 0
    local seconds = 0
    
    -- Cek format menit (contoh: "1m 30s")
    local m = string.match(timeText, "(%d+)m")
    if m then
        minutes = tonumber(m) or 0
    end
    
    -- Cek format detik (contoh: "30s" atau "1m 30s")
    local s = string.match(timeText, "(%d+)s")
    if s then
        seconds = tonumber(s) or 0
    end
    
    return (minutes * 60) + seconds
end

TeleportTab:CreateToggle({
    Name = "Auto Tp Event Leviathan",
    Default = false,
    Callback = function(state)
        local player = game.Players.LocalPlayer
        local platform = nil
        local isAtEvent = false
        local hasNotifiedCountdown = false
        
        if state then
            -- Ambil character awal
            local character = player.Character or player.CharacterAdded:Wait()
            local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
            local originalCFrame = humanoidRootPart.CFrame

            -- Buat platform invisible
            platform = Instance.new("Part")
            platform.Name = "AutoTpPlatform"
            platform.Size = Vector3.new(10, 1, 10)
            platform.Position = humanoidRootPart.Position - Vector3.new(0, 4, 0)
            platform.Anchored = true
            platform.Transparency = 1
            platform.CanCollide = true
            platform.Parent = game.Workspace

            -- Loop cek event
            spawn(function()
                while state and player.Character and player.Character:FindFirstChild("HumanoidRootPart") do
                    task.wait(0.3)

                    humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                    if not humanoidRootPart then break end

                    -- Cek label countdown
                    local success, remainingLabel = pcall(function()
                        return workspace["!!!! ISLAND LOCATIONS !!!!"]["Event Notification"].Gui.Frame.Frame.Remaining
                    end)

                    if success and remainingLabel and remainingLabel:IsA("TextLabel") then
                        local timeText = remainingLabel.Text
                        local timeInSeconds = parseTimeToSeconds(timeText)
                        
                        if timeInSeconds and timeInSeconds >= 0 and timeInSeconds <= 1 then
                            -- Countdown antara 1-0 detik → TP ke event!
                            if not isAtEvent then
                                humanoidRootPart.CFrame = targetEventCFrame
                                platform.Position = targetEventCFrame.Position - Vector3.new(0, 4, 0)
                                isAtEvent = true
                                hasNotifiedCountdown = false
                                
                                game.StarterGui:SetCore("SendNotification", {
                                    Title = "Leviathan Event Started! 🐋",
                                    Text = "Auto TP ke event location!",
                                    Duration = 5
                                })
                            end
                        elseif timeInSeconds and timeInSeconds > 1 and not hasNotifiedCountdown then
                            -- Masih ada waktu, kasih notif countdown
                            hasNotifiedCountdown = true
                            game.StarterGui:SetCore("SendNotification", {
                                Title = "Leviathan Event Soon! ⏰",
                                Text = "Event akan dimulai dalam " .. timeText,
                                Duration = 4
                            })
                        end
                    else
                        -- Label hilang atau tidak ada → event sudah selesai
                        if isAtEvent then
                            -- Balik ke posisi awal
                            if savedStartCFrame then
                                humanoidRootPart.CFrame = savedStartCFrame
                                platform.Position = savedStartCFrame.Position - Vector3.new(0, 4, 0)
                            else
                                humanoidRootPart.CFrame = originalCFrame
                                platform.Position = originalCFrame.Position - Vector3.new(0, 4, 0)
                            end
                            
                            isAtEvent = false
                            hasNotifiedCountdown = false
                            
                            game.StarterGui:SetCore("SendNotification", {
                                Title = "Leviathan Event Ended 🌊",
                                Text = "Auto balik ke posisi awal!",
                                Duration = 5
                            })
                        end
                    end
                end

                -- Toggle mati atau loop berhenti → hapus platform
                if platform and platform.Parent then
                    platform:Destroy()
                    platform = nil
                end
            end)

            -- Handle respawn (update posisi awal & platform)
            player.CharacterAdded:Connect(function(newChar)
                if not state then return end
                local newHRP = newChar:WaitForChild("HumanoidRootPart")
                originalCFrame = newHRP.CFrame
                isAtEvent = false
                hasNotifiedCountdown = false
                
                if platform and platform.Parent then
                    platform.Position = newHRP.Position - Vector3.new(0, 4, 0)
                end
            end)

        else
            -- Toggle dimatikan → hapus platform
            if platform and platform.Parent then
                platform:Destroy()
                platform = nil
            end
        end
    end
})

-- Button Manual TP ke Leviathan Event
TeleportTab:CreateButton({
    Name = "Manual TP to Leviathan Event",
    Callback = function()
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
        
        humanoidRootPart.CFrame = targetEventCFrame
        game.StarterGui:SetCore("SendNotification", {
            Title = "Teleport Success",
            Text = "Kamu sudah di Leviathan Event!",
            Duration = 3
        })
    end
})

-- Button Balik ke Posisi Awal (yang sudah auto disimpan)
TeleportTab:CreateButton({
    Name = "Return to Start Position",
    Callback = function()
        local player = game.Players.LocalPlayer
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
        
        if savedStartCFrame then
            player.Character.HumanoidRootPart.CFrame = savedStartCFrame
            game.StarterGui:SetCore("SendNotification", {
                Title = "Teleported Back",
                Text = "Kembali ke posisi awal!",
                Duration = 3
            })
        else
            game.StarterGui:SetCore("SendNotification", {
                Title = "Error",
                Text = "Posisi awal belum tersimpan (coba reload script).",
                Duration = 4
            })
        end
    end
})

SettingsTab:CreateSection({ Name = "Skip Cutscene" })

local skipCutscene = false
local replicateConn
local stopConn
local originalPlay
local originalStop
local hooked = false

SettingsTab:CreateToggle({
	Name = "Skip Cutscene",
	Default = false,
	  Callback = function(state)
        skipCutscene = state

        -- ===== Remote Events (connect sekali) =====
        if not replicateConn and RE.ReplicateCutscene then
            replicateConn = RE.ReplicateCutscene.OnClientEvent:Connect(function(...)
                if skipCutscene then
                    warn("[VoraHub] Blocked ReplicateCutscene event!")
                end
            end)
        end

        if not stopConn and RE.StopCutscene then
            stopConn = RE.StopCutscene.OnClientEvent:Connect(function()
                if skipCutscene then
                    warn("[VoraHub] Blocked StopCutscene event!")
                end
            end)
        end

        -- ===== Controller (hook sekali doang) =====
        if hooked then return end
        hooked = true

        spawn(LPH_NO_VIRTUALIZE(function()
            local ok, CutsceneController = pcall(function()
                return require(ReplicatedStorage.Controllers.CutsceneController)
            end)

            if not ok or not CutsceneController then
                warn("[VoraHub] CutsceneController not found.")
                return
            end

            originalPlay = originalPlay or CutsceneController.Play
            originalStop = originalStop or CutsceneController.Stop

            -- monitor toggle
            while true do
                if skipCutscene then
                    CutsceneController.Play = function(...)
                        warn("[VoraHub] Cutscene skipped (Play).")
                    end
                    CutsceneController.Stop = function(...)
                        warn("[VoraHub] Cutscene skipped (Stop).")
                    end
                else
                    CutsceneController.Play = originalPlay
                    CutsceneController.Stop = originalStop
                end
                task.wait(0.25)
            end
        end))
    end
})

SettingsTab:CreateSection({ Name = "General", Icon = "rbxassetid://7733954611" })

SettingsTab:CreateToggle({
	Name = "AntiAFK",
	SubText = "Prevent Roblox from kicking you when idle",
	Default = false,
 Callback = function(state)
        _G.AntiAFK = state
        local VirtualUser = game:GetService("VirtualUser")

        if state then
            task.spawn(function()
                while _G.AntiAFK do
                    task.wait(60)
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new())
                    end)
                end
            end)

            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "AntiAFK loaded!",
                Text = "Coded By nat.sh",
                Button1 = "Nigger",
                Duration = 5
            })
        else
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "AntiAFK Disabled",
                Text = "Stopped AntiAFK",
                Duration = 3
            })
        end
    end
})

SettingsTab:CreateToggle({
	Name = "Auto Reconnect",
	SubText = "Automatic reconnect if disconnected",
	Default = false,
	 Callback = function(state)
        _G.AutoReconnect = state
        if state then
            task.spawn(function()
                while _G.AutoReconnect do
                    task.wait(2)

                    local reconnectUI = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
                    if reconnectUI then
                        local prompt = reconnectUI:FindFirstChild("promptOverlay")
                        if prompt then
                            local button = prompt:FindFirstChild("ButtonPrimary")
                            if button and button.Visible then
                                firesignal(button.MouseButton1Click)
                            end
                        end
                    end
                end
            end)
        end
    end
})

SettingsTab:CreateSection({ Name = "Hide Identity Features", Icon = "rbxassetid://7743875962" })

Players = game:GetService("Players")
Player = Players.LocalPlayer
Character = Player.Character or Player.CharacterAdded:Wait()

function getOverhead(char)
    local hrp = char:WaitForChild("HumanoidRootPart")
    return hrp:WaitForChild("Overhead")
end

overhead = getOverhead(Character)
header = overhead.Content.Header
levelLabel = overhead.LevelContainer.Label

defaultHeader = header.Text
defaultLevel = levelLabel.Text
customHeader = defaultHeader
customLevel = defaultLevel

keepHidden = false
rgbThread = nil


SettingsTab:CreateInput({
	Name = "Hide Name",
	Placeholder = "Input Name",
	   Default = defaultHeader,
    Callback = function(value)
        customHeader = value
        if keepHidden then
            header.Text = customHeader
        end
    end
})
SettingsTab:CreateInput({
	Name = "Hide Level",
	Placeholder = "Input Level",
	   Default = defaultLevel,
    Callback = function(value)
        customLevel = value
        if keepHidden then
            levelLabel.Text = customLevel
        end
    end
})


SettingsTab:CreateToggle({
	Name = "Hide Identity (RGB Blink)",
	Default = false,
	  Callback = function(state)
        keepHidden = state

        if state then
            header.Text = customHeader
            levelLabel.Text = customLevel

            if rgbThread then
                task.cancel(rgbThread)
            end

            rgbThread = task.spawn(function()
                local hue = 0
                while keepHidden do
                    hue = (hue + 0.003) % 1

                    -- Warna pastel 100% terang
                    local color = Color3.fromHSV(hue, 0.35, 1)
                    -- Saturation 0.35 = hindari warna gelap
                    -- Value 1 = selalu terang

                    pcall(function()
                        header.TextColor3 = color
                        levelLabel.TextColor3 = color
                    end)

                    task.wait(0.03)
                end
            end)
        else
            if rgbThread then
                task.cancel(rgbThread)
                rgbThread = nil
            end

            header.Text = defaultHeader
            levelLabel.Text = defaultLevel

            header.TextColor3 = Color3.new(1,1,1)
            levelLabel.TextColor3 = Color3.new(1,1,1)
        end
    end
})

player.CharacterAdded:Connect(function(newChar)
    local overhead = getOverhead(newChar)
    header = overhead.Content.Header
    levelLabel = overhead.LevelContainer.Label

    if keepHidden then
        header.Text = customHeader
        levelLabel.Text = customLevel
    end
end)

SettingsTab:CreateSection({ Name = "Server", Icon = "rbxassetid://7733955511" })

SettingsTab:CreateButton({
	Name = "Rejoin Server",
	SubText = "Reconnect to current server",
	Icon = "rbxassetid://7733920644",
 Callback = function()
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, game.Players.LocalPlayer)
    end
})

SettingsTab:CreateButton({
	Name = "Server Hop",
	SubText = "Switch to another server",
	Icon = "rbxassetid://7733920644",
	 Callback = function()
        local HttpService = game:GetService("HttpService")
        local TeleportService = game:GetService("TeleportService")
        
        local function GetServers()
            local url = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=100"
            local response = HttpService:JSONDecode(game:HttpGet(url))
            return response.data
        end

        local function FindBestServer(servers)
            for _, server in ipairs(servers) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    return server.id
                end
            end
            return nil
        end
        local servers = GetServers()
        local serverId = FindBestServer(servers)
        if serverId then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, serverId, game.Players.LocalPlayer)
        else
            warn("⚠️ No suitable server found!")
        end
    end
})

-- CONFIG TAB UI
ConfigTab:CreateSection({ Name = "Config Management", Icon = "rbxassetid://7734053426" })

configNameInput = ""
configDropdown = nil
selectedConfigToLoad = ""

-- Create dropdown first so it exists when Save button is clicked
savedConfigs = getConfigList()
selectedConfigToLoad = savedConfigs[1] or ""
if ConfigData["Select Config"] and table.find(savedConfigs, ConfigData["Select Config"]) then
    selectedConfigToLoad = ConfigData["Select Config"]
end

configDropdown = ConfigTab:CreateDropdown({
	Name = "Select Config",
	Items = savedConfigs,
	Default = selectedConfigToLoad,
	Callback = function(selected)
		selectedConfigToLoad = selected
	end
})

local configNameInputObject = ConfigTab:CreateInput({
	Name = "Config Name",
	SideLabel = "Name",
	Placeholder = "Enter config name...",
	Default = "",
	Callback = function(txt)
		configNameInput = txt
	end
})

ConfigTab:CreateButton({
	Name = "Save Config",
	SubText = "Save current settings (Manual save only)",
	Icon = "rbxassetid://7734068321",
	Callback = function()
        -- Fallback to selected config if input is empty
        if configNameInput == "" and selectedConfigToLoad ~= "" then
            configNameInput = selectedConfigToLoad
            if configNameInputObject then
                configNameInputObject:Set(configNameInput)
            end
        end

		if configNameInput == "" then
			Window:Notify({
				Title = "Error",
				Content = "Please enter a config name!",
				Duration = 3
			})
			return
		end
		
		-- Sanitize and validate config name
		local originalName = configNameInput
		local sanitizedName = configNameInput:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
		
		if sanitizedName == "" then
			Window:Notify({
				Title = "✗ Error",
				Content = "Invalid config name! Use only letters, numbers, spaces, - or _",
				Duration = 4
			})
			return
		end
		
		-- Warn if name was modified
		if sanitizedName ~= originalName then
			Window:Notify({
				Title = "⚠ Warning",
				Content = "Config name sanitized to: '" .. sanitizedName .. "'",
				Duration = 3
			})
			configNameInput = sanitizedName
            if configNameInputObject then
                configNameInputObject:Set(configNameInput)
            end
		end
		
		-- Collect current values from all UI elements before saving
		if Window and Window.Elements then
			for key, element in pairs(Window.Elements) do
				if element.Object and element.Object.Value ~= nil then
					ConfigData[key] = element.Object.Value
				elseif element.Object and element.Object.Values ~= nil then
					-- For MultiDropdown
					ConfigData[key] = element.Object.Value or {}
				end
			end
		end
		
		-- Disable auto-save temporarily to prevent conflicts
		AutoSaveEnabled = false
		
		local success, err = saveConfigWithName(configNameInput)
		if success then
            CurrentConfigName = configNameInput -- UPDATE CURRENT CONFIG NAME
			Window:Notify({
				Title = "✓ Success",
				Content = "Config '" .. configNameInput .. "' saved successfully!",
				Duration = 3
			})
			
			-- Reset unsaved changes flag
			HasUnsavedChanges = false
			
			-- Refresh dropdown with new config list
			if configDropdown then
				local newConfigList = getConfigList()
				configDropdown:Refresh(newConfigList)
				-- Set to the config that was just saved
				if table.find(newConfigList, configNameInput) then
					configDropdown:Set(configNameInput)
				end
			end
		else
			Window:Notify({
				Title = "✗ Error",
				Content = "Failed to save: " .. (err or "Unknown error"),
				Duration = 4
			})
		end
		
		-- Keep auto-save disabled (manual save only)
		task.delay(1, function()
			AutoSaveEnabled = false
		end)
	end
})


ConfigTab:CreateButton({
	Name = "Load Config",
	SubText = "Load selected configuration",
	Icon = "rbxassetid://7734053495",
	Callback = function()
		if not selectedConfigToLoad or selectedConfigToLoad == "" then
			Window:Notify({
				Title = "✗ Error",
				Content = "Please select a config to load!",
				Duration = 3
			})
			return
		end
		
		-- Disable auto-save during load to prevent conflicts
		AutoSaveEnabled = false
		
		local success, err = loadConfigByName(selectedConfigToLoad)
		if success then
            -- Update config name input to match loaded config
            configNameInput = selectedConfigToLoad
            if configNameInputObject then
                configNameInputObject:Set(selectedConfigToLoad)
            end

			-- Apply loaded config settings to UI elements
			if Window and Window.Elements then
				local loadedCount = 0
				local failedCount = 0
				
				for key, value in pairs(ConfigData) do
					if Window.Elements[key] and Window.Elements[key].Object then
						task.spawn(function()
							local elementSuccess = pcall(function()
								Window.Elements[key].Object:Set(value)
							end)
							
							if elementSuccess then
								loadedCount = loadedCount + 1
							else
								failedCount = failedCount + 1
							end
						end)
					end
				end
				
				-- Wait a bit for all elements to load
				task.wait(0.3)
				
				local message = "Config loaded! (" .. loadedCount .. " settings)"
				if failedCount > 0 then
					message = message .. " [" .. failedCount .. " failed]"
				end
				
				Window:Notify({
					Title = "✓ Success",
					Content = message,
					Duration = 3
				})
			else
				Window:Notify({
					Title = "⚠ Warning",
					Content = "Config loaded but Window.Elements is missing!",
					Duration = 4
				})
			end
		else
			Window:Notify({
				Title = "✗ Error",
				Content = "Failed to load: " .. (err or "Unknown error"),
				Duration = 4
			})
		end
		
		-- Keep auto-save disabled (manual save only)
		task.delay(1, function()
			AutoSaveEnabled = false
		end)
	end
})

ConfigTab:CreateButton({
	Name = "Refresh Config List",
	SubText = "Update available configs",
	Icon = "rbxassetid://7734056813",
	Callback = function()
		if configDropdown then
			configDropdown:Refresh(getConfigList())
			Window:Notify({
				Title = "Refreshed",
				Content = "Config list updated!",
				Duration = 2
			})
		end
	end
})

ConfigTab:CreateButton({
	Name = "Delete Config",
	SubText = "Delete selected config",
	Icon = "rbxassetid://7734053495",
	Callback = function()
		if not selectedConfigToLoad or selectedConfigToLoad == "" then
			Window:Notify({
				Title = "✗ Error",
				Content = "Please select a config to delete!",
				Duration = 3
			})
			return
		end
		
		local configToDelete = selectedConfigToLoad
		local success, err = deleteConfig(configToDelete)
		if success then
			Window:Notify({
				Title = "✓ Success",
				Content = "Config '" .. configToDelete .. "' deleted!",
				Duration = 3
			})
			
			-- Clear current config if it was the one deleted
			if CurrentConfigName == configToDelete then
				CurrentConfigName = ""
				ConfigData = {}
			end
			
			-- Clear selection
			selectedConfigToLoad = ""
			
			-- Refresh dropdown
			if configDropdown then
				local newConfigs = getConfigList()
				configDropdown:Refresh(newConfigs)
				if #newConfigs > 0 then
					configDropdown:Set(newConfigs[1])
					selectedConfigToLoad = newConfigs[1]
				end
			end
		else
			Window:Notify({
				Title = "✗ Error",
				Content = "Failed to delete: " .. (err or "Unknown error"),
				Duration = 4
			})
		end
	end
})

ConfigTab:CreateSection({ Name = "Info", Icon = "rbxassetid://7733964719" })

ConfigTab:CreateButton({
	Name = "Current Config",
	SubText = CurrentConfigName ~= "" and CurrentConfigName or "None loaded",
	Icon = "rbxassetid://7733964719",
	Callback = function()
		Window:Notify({
			Title = "Current Config",
			Content = CurrentConfigName ~= "" and CurrentConfigName or "No config loaded",
			Duration = 3
		})
	end
})

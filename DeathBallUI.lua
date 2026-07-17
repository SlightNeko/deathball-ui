--!native
--!optimize 2
if not game:IsLoaded() then game.Loaded:Wait() end

local cloneref = cloneref or clonereference or function(obj) return obj end
Services = setmetatable({}, {
	__index = function(self, name)
		local success, cache = pcall(function() return cloneref(game:GetService(name)) end)
		if success then
			rawset(self, name, cache)
			return cache
		else
			error("Invalid service: "..tostring(name))
		end
	end
})

local Players = Services.Players
local Workspace = Services.Workspace
local UserInputService = Services.UserInputService
local RunService = Services.RunService
local LocalPlayer = Players.LocalPlayer

-- ========== 原 DeathBallScripts 模块（内嵌，逻辑未修改） ==========
local DeathBallScript = {}
DeathBallScript.__index = DeathBallScript

local dbConnections = {}
local dbMainGui = nil
local dbStatusText = nil
local dbDistanceText = nil
local dbTargetBall = nil
local dbPrevBall = nil
local dbBallSwitchCooldown = 0
local dbIsEnabled = false
local dbCharacter = nil
local dbRootPart = nil

local function dbFindBall()
	local playerChar = LocalPlayer.Character
	local playerPos = playerChar and playerChar:FindFirstChild("HumanoidRootPart")

	-- 优先：workspace.Balls 容器（Death Ball 正规球存放处）
	local ballsFolder = Workspace:FindFirstChild("Balls")
	if ballsFolder then
		local best = nil
		local bestScore = -math.huge
		for _, child in pairs(ballsFolder:GetChildren()) do
			if child:IsA("BasePart") then
				local dist = playerPos and (child.Position - playerPos.Position).Magnitude or math.huge
				local sizeVol = child.Size.X * child.Size.Y * child.Size.Z
				-- 死亡球通常 > 1 stud 直径，且不会太小
				if sizeVol > 0.5 then
					local score = 100000 - dist + sizeVol * 10
					if score > bestScore then
						bestScore = score
						best = child
					end
				end
			end
		end
		if best then
			return best
		end
	end

	-- 兜底：扫 Workspace 顶层，找带 Highlight 的 Part
	for _, child in pairs(Workspace:GetChildren()) do
		if child.Name == "Part" and child:IsA("BasePart") and child:FindFirstChildOfClass("Highlight") then
			local dist = playerPos and (child.Position - playerPos.Position).Magnitude or math.huge
			return child
		end
	end

	return nil
end

local function dbUpdateBallReference()
	if dbTargetBall and dbTargetBall:IsDescendantOf(Workspace) then
		if dbBallSwitchCooldown > 0 then
			dbBallSwitchCooldown = dbBallSwitchCooldown - 1
			return
		end
		local candidate = dbFindBall()
		if candidate and candidate ~= dbTargetBall then
			-- 新球和旧球距离太远时保持旧球，防止在两个球之间跳变
			if dbPrevBall and dbPrevBall:IsDescendantOf(Workspace) then
				local distBetween = (candidate.Position - dbPrevBall.Position).Magnitude
				if distBetween > 30 then
					return
				end
			end
			dbTargetBall = candidate
			dbBallSwitchCooldown = 10
		end
		return
	end
	dbTargetBall = dbFindBall()
end

local function dbCreateUI()
	if dbMainGui then return end
	dbMainGui = Instance.new("ScreenGui")
	if syn and syn.protect_gui then
		syn.protect_gui(dbMainGui)
		dbMainGui.Parent = cloneref(game.CoreGui)
	else
		dbMainGui.Parent = gethui and gethui() or cloneref(game.CoreGui)
	end
	dbStatusText = Instance.new("TextLabel")
	dbStatusText.Parent = dbMainGui
	dbStatusText.Size = UDim2.new(0, 200, 0, 30)
	dbStatusText.Position = UDim2.new(0.5, -100, 0.1, 0)
	dbStatusText.BackgroundTransparency = 1
	dbStatusText.Text = "游戏未开始"
	dbStatusText.TextColor3 = Color3.fromRGB(230, 230, 250)
	dbStatusText.TextSize = 25
	dbStatusText.Font = Enum.Font.GothamBold
	dbDistanceText = Instance.new("TextLabel")
	dbDistanceText.Parent = dbMainGui
	dbDistanceText.Size = UDim2.new(0, 200, 0, 20)
	dbDistanceText.Position = UDim2.new(0.5, -100, 0.14, 0)
	dbDistanceText.BackgroundTransparency = 1
	dbDistanceText.Text = ""
	dbDistanceText.TextColor3 = Color3.fromRGB(166, 166, 166)
	dbDistanceText.TextSize = 15
end

local function dbHideUI()
	if dbMainGui then
		dbMainGui.Enabled = false
	end
end

local function dbShowUI()
	if dbMainGui then
		dbMainGui.Enabled = true
	end
end

local function dbDestroyUI()
	if dbMainGui then
		dbMainGui:Destroy()
		dbMainGui = nil
		dbStatusText = nil
		dbDistanceText = nil
	end
end

-- 公开：供 UI 按钮直接调用
function DeathBallScript.teleportToBallAndBack()
	if not dbTargetBall or not dbTargetBall:IsDescendantOf(Workspace) then
		return
	end
	if not dbRootPart or not dbRootPart.Parent then
		return
	end

	local currentCFrame = dbRootPart.CFrame
	local ballCFrame = dbTargetBall.CFrame

	local ballSize = dbTargetBall.Size
	local radius = (ballSize.X + ballSize.Y + ballSize.Z) / 6
	local offset = radius + 2

	Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, cloneref(game))
	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end

	local direction = (currentCFrame.Position - ballCFrame.Position).Unit
	local newPos = ballCFrame.Position + direction * offset
	local newCFrame = CFrame.new(newPos, ballCFrame.Position)

	dbRootPart.CFrame = newCFrame

	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end

	Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, cloneref(game))

	dbRootPart.CFrame = currentCFrame
end

local function dbUpdateUI()
	local ball = dbTargetBall
	local playerChar = LocalPlayer.Character
	local playerPos = playerChar and playerChar:FindFirstChild("HumanoidRootPart")

	if not ball or not playerPos then
		if dbStatusText then
			dbStatusText.Text = "游戏未开始"
			dbStatusText.TextColor3 = Color3.fromRGB(230, 230, 250)
		end
		if dbDistanceText then
			dbDistanceText.Text = ""
		end
		return
	end

	local isSpectating = playerPos.Position.Z < -767.55 and playerPos.Position.Y > 279.17
	if isSpectating then
		if dbStatusText then
			dbStatusText.Text = "观战中"
			dbStatusText.TextColor3 = Color3.fromRGB(230, 230, 250)
		end
		if dbDistanceText then
			dbDistanceText.Text = ""
		end
	else
		local isLocked = ball.Highlight and ball.Highlight.FillColor ~= Color3.new(1, 1, 1)
		if dbStatusText then
			dbStatusText.Text = isLocked and "已被球锁定" or "未被球锁定"
			dbStatusText.TextColor3 = isLocked and Color3.fromRGB(238, 17, 17) or Color3.fromRGB(17, 238, 17)
		end
		local distance = (ball.Position - playerPos.Position).Magnitude
		if dbDistanceText then
			dbDistanceText.Text = string.format("%.0f", distance)
		end
	end
end

function DeathBallScript:Enable()
	if dbIsEnabled then
		return
	end

	dbCharacter = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	dbRootPart = dbCharacter:WaitForChild("HumanoidRootPart")

	dbCreateUI()
	dbShowUI()
	dbUpdateBallReference()

	table.insert(dbConnections, Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Part" and child:IsA("BasePart") then
			local size = child.Size.X * child.Size.Y * child.Size.Z
			if size > 5 and size < 5000 then
				dbTargetBall = child
			end
		end
	end))

	table.insert(dbConnections, Workspace.ChildRemoved:Connect(function(child)
		if child == dbTargetBall then
			dbTargetBall = nil
		end
	end))

	local bindConnection = ContextActionService:BindAction("TeleportToBall", function(actionName, inputState)
		if inputState == Enum.UserInputState.Begin then
			DeathBallScript.teleportToBallAndBack()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R)
	table.insert(dbConnections, bindConnection)

	table.insert(dbConnections, RunService.Heartbeat:Connect(function()
		if dbIsEnabled then
			dbPrevBall = dbTargetBall
			dbUpdateUI()
		end
	end))

	table.insert(dbConnections, LocalPlayer.CharacterAdded:Connect(function(newChar)
		if dbIsEnabled then
			dbCharacter = newChar
			dbRootPart = dbCharacter:WaitForChild("HumanoidRootPart")
		end
	end))

	dbIsEnabled = true
end

function DeathBallScript:Disable()
	if not dbIsEnabled then
		return
	end

	for _, connection in ipairs(dbConnections) do
		if connection then
			if connection.Disconnect then
				connection:Disconnect()
			elseif connection.Unbind then
				connection:Unbind()
			end
		end
	end
	dbConnections = {}

	dbHideUI()
	dbIsEnabled = false
	dbCharacter = nil
	dbRootPart = nil
	dbTargetBall = nil
end

function DeathBallScript:Unload()
	self:Disable()
	dbDestroyUI()
	ContextActionService:UnbindAction("TeleportToBall")
	_G.DeathBallScriptLoaded = false
end

_G.DeathBallScript = DeathBallScript

-- ========== ChronixUI 加载 ==========
local ChronixUI = loadstring(game:HttpGet("https://raw.atomgit.com/Furrycalin/ChronixHub/raw/main/modules/ChronixUI%20Lib.lua"))()

-- ========== UI 逻辑 ==========
local windowData = nil
local isEnabled = false
local autoBlockEnabled = false
local autoBlockDistance = 12
local autoBlockHysteresis = 2
local autoBlockPressed = false
local autoBlockSmoothDist = nil
local autoBlockSpeed = nil
local autoBlockLockFrames = 0
local autoBlockUnlockFrames = 0
local autoBlockLockDebounce = 2
local autoBlockUnlockDebounce = 2
local uiSmoothDistance = nil
local statusLabel = nil
local distanceLabel = nil
local heartbeatConnection = nil
local autoBlockConnection = nil

local function updateUI()
	if not statusLabel or not distanceLabel then
		return
	end

	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local ball = dbTargetBall

	if not ball or not rootPart then
		statusLabel.Text = "游戏未开始"
		statusLabel.TextColor3 = Color3.fromRGB(230, 230, 250)
		distanceLabel.Text = ""
		return
	end

	local isSpectating = rootPart.Position.Z < -767.55 and rootPart.Position.Y > 279.17
	if isSpectating then
		statusLabel.Text = "观战中"
		statusLabel.TextColor3 = Color3.fromRGB(230, 230, 250)
		distanceLabel.Text = ""
		return
	end

	local isLocked = ball.Highlight and ball.Highlight.FillColor ~= Color3.new(1, 1, 1)
	statusLabel.Text = isLocked and "已被球锁定" or "未被球锁定"
	statusLabel.TextColor3 = isLocked and Color3.fromRGB(238, 17, 17) or Color3.fromRGB(17, 238, 17)

	local rawDistance = (ball.Position - rootPart.Position).Magnitude
	if not uiSmoothDistance or math.abs(uiSmoothDistance - rawDistance) > 3 then
		uiSmoothDistance = rawDistance
	else
		uiSmoothDistance = 0.2 * rawDistance + 0.8 * uiSmoothDistance
	end
	distanceLabel.Text = string.format("%.0f", uiSmoothDistance or rawDistance)
end

local function doTeleport()
	if not isEnabled then
		return
	end
	pcall(function()
		DeathBallScript.teleportToBallAndBack()
	end)
end

local function autoBlockPress()
	if not isEnabled or not autoBlockEnabled then
		if autoBlockPressed then
			Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, cloneref(game))
			autoBlockPressed = false
		end
		return
	end

	local ball = dbTargetBall
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not ball or not ball:IsDescendantOf(Workspace) or not rootPart then
		if autoBlockPressed then
			Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, cloneref(game))
			autoBlockPressed = false
		end
		return
	end

	local isSpectating = rootPart.Position.Z < -767.55 and rootPart.Position.Y > 279.17
	if isSpectating then
		if autoBlockPressed then
			Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, cloneref(game))
			autoBlockPressed = false
		end
		return
	end

	local isLocked = ball.Highlight and ball.Highlight.FillColor ~= Color3.new(1, 1, 1)
	local rawDistance = (ball.Position - rootPart.Position).Magnitude

	-- 速度检测（时间判定核心）
	local speed = 0
	if ball:FindFirstChild("zoomies") and ball.zoomies:FindFirstChild("VectorVelocity") then
		speed = ball.zoomies.VectorVelocity.Magnitude
	elseif ball.AssemblyLinearVelocity then
		speed = ball.AssemblyLinearVelocity.Magnitude
	end

	-- 平滑距离和速度
	if not autoBlockSmoothDist or math.abs(autoBlockSmoothDist - rawDistance) > 3 then
		autoBlockSmoothDist = rawDistance
	else
		autoBlockSmoothDist = 0.3 * rawDistance + 0.7 * autoBlockSmoothDist
	end
	if not autoBlockSpeed or math.abs(autoBlockSpeed - speed) > 5 then
		autoBlockSpeed = speed
	else
		autoBlockSpeed = 0.3 * speed + 0.7 * autoBlockSpeed
	end

	local distance = autoBlockSmoothDist
	local effectiveSpeed = autoBlockSpeed

	-- 时间判定：Distance / Speed <= threshold（借鉴 Phantom 思路）
	-- 速度太低时回退到纯距离判定，避免除以零或极慢球误判
	local timeToHit = effectiveSpeed > 0.5 and distance / effectiveSpeed or math.huge
	local distanceThreshold = autoBlockDistance

	-- 锁定/未锁定帧计数
	if isLocked then
		autoBlockLockFrames = autoBlockLockFrames + 1
		autoBlockUnlockFrames = 0
	else
		autoBlockUnlockFrames = autoBlockUnlockFrames + 1
		autoBlockLockFrames = 0
	end

	-- 自动挡逻辑：
	-- 1. 锁定 + (距离足够近 OR 时间足够近) -> 按 F
	-- 2. 解锁 + 距离超出 + 未锁定持续帧数满足 -> 松 F
	local shouldPress = isLocked and (distance <= distanceThreshold or timeToHit <= 0.55) and autoBlockLockFrames >= autoBlockLockDebounce
	local hysteresisDist = distanceThreshold + autoBlockHysteresis
	local shouldRelease = not isLocked or (distance > hysteresisDist and timeToHit > 0.7) or autoBlockUnlockFrames >= autoBlockUnlockDebounce

	if shouldPress and not autoBlockPressed then
		Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, cloneref(game))
		autoBlockPressed = true
	elseif shouldRelease and autoBlockPressed then
		Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, cloneref(game))
		autoBlockPressed = false
	end
end

local function setAutoBlock(value)
	autoBlockEnabled = value
	autoBlockPressed = false
	autoBlockSmoothDist = nil
	autoBlockSpeed = nil
	autoBlockLockFrames = 0
	autoBlockUnlockFrames = 0
	uiSmoothDistance = nil
	if autoBlockConnection then
		autoBlockConnection:Disconnect()
		autoBlockConnection = nil
	end
	if autoBlockEnabled then
		autoBlockConnection = RunService.Heartbeat:Connect(function()
			autoBlockPress()
		end)
	end
end

local function createWindow()
	local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local windowSize = isMobile and UDim2.new(0, 360, 0, 320) or UDim2.new(0, 420, 0, 300)

	windowData = ChronixUI:CreateWindow({
		Name = "死亡球",
		WindowSize = windowSize,
	})

	local mainTab = windowData:CreateTab({ Name = "主界面", HasIcon = true, IconName = "crosshair" })

	mainTab:AddTitle("死亡球")
	mainTab:AddParagraph({
		Title = "说明",
		Content = "开启后按 R 反弹死亡球，也可点击按钮反弹。开启自动格挡会在球靠近时自动按住 F，不会移动角色。",
	})

	statusLabel = mainTab:AddLabel("状态：未开启")
	distanceLabel = mainTab:AddLabel("距离：--")

	mainTab:AddToggle({
		Label = "启用死亡球功能",
		Default = false,
		Callback = function(value)
			isEnabled = value
			if isEnabled then
				DeathBallScript:Enable()
				if not heartbeatConnection then
					heartbeatConnection = RunService.Heartbeat:Connect(function()
						if isEnabled then
							updateUI()
						end
					end)
				end
				ChronixUI:Notify({
					Title = "死亡球",
					Content = "已启用，按 R 反弹死亡球。",
					Type = "success",
					Duration = 3,
				})
			else
				if heartbeatConnection then
					heartbeatConnection:Disconnect()
					heartbeatConnection = nil
				end
				setAutoBlock(false)
				DeathBallScript:Disable()
				if statusLabel then
					statusLabel.Text = "状态：已关闭"
					statusLabel.TextColor3 = Color3.fromRGB(230, 230, 250)
				end
				if distanceLabel then
					distanceLabel.Text = "距离：--"
				end
				ChronixUI:Notify({
					Title = "死亡球",
					Content = "已关闭。",
					Type = "info",
					Duration = 3,
				})
			end
		end,
	})

	mainTab:AddToggle({
		Label = "自动格挡(靠近自动按F)",
		Default = false,
		Callback = function(value)
			setAutoBlock(value)
		end,
	})

	mainTab:AddInput({
		Label = "自动格挡距离",
		Default = tostring(autoBlockDistance),
		Placeholder = "触发距离(Studios)",
		Callback = function(text)
			local value = tonumber(text)
			if value and value > 0 then
				autoBlockDistance = value
			end
		end,
	})

	mainTab:AddButton({
		Text = "立即反弹",
		Callback = function()
			doTeleport()
		end,
	})

	mainTab:AddLabel("快捷键：R = 反弹   F = 格挡(自动)")
end

-- 启动界面
createWindow()

-- 初始刷新一次
task.spawn(function()
	task.wait(1)
	updateUI()
end)

-- 卸载清理
local function cleanup()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	setAutoBlock(false)
	if isEnabled then
		DeathBallScript:Disable()
	end
	if windowData and windowData.Gui then
		windowData:Destroy()
	end
end

if _G then
	local originalUnload = _G.DeathBallScript and _G.DeathBallScript.Unload
	if originalUnload then
		_G.DeathBallScript.Unload = function(self)
			cleanup()
			return originalUnload(self)
		end
	end
end

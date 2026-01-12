--[[
    Rubidium UI Library - Framework v1.8 (Animation Fix & Rail Sliding)
    
    保留功能：
    1. 移动端适配 (GetScale)
    2. 基础拖拽与吸附
    3. 动态布局核心
    
    本次更新：
    1. [Fix] 标题/副标题边距收紧 (Margin Tightening)。
    2. [Fix] 合并动画修复：引入 IsAnimating 锁，防止 RenderStepped 冲突。
    3. [New] 轨道拖拽 (Rail Drag)：分离模式下 Sidebar 强制贴边滑动。
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Camera = workspace.CurrentCamera
local Mouse = Players.LocalPlayer:GetMouse()

local function Create(className, properties, children)
    local instance = Instance.new(className)
    for k, v in pairs(properties or {}) do
        instance[k] = v
    end
    for _, child in pairs(children or {}) do
        child.Parent = instance
    end
    return instance
end

local Rubidium = {
    Name = "Rubidium",
    State = "Unified", 
    IsAnimating = false, -- [New] 动画锁状态
    ActiveWindows = {}, 
    Config = {
        ThemeColor = Color3.fromRGB(0, 170, 255),
        MainBg = Color3.fromRGB(20, 20, 20),
        SidebarBg = Color3.fromRGB(25, 25, 25),
        TextColor = Color3.fromRGB(240, 240, 240),
        SubTextColor = Color3.fromRGB(150, 150, 150),
        AnimSpeed = 0.5, -- 稍微调慢一点让动画更明显
        BaseSize = Vector2.new(600, 380), 
        SidebarWidth = 80
    }
}

function Rubidium:GetScale()
    local viewportSize = Camera.ViewportSize
    if viewportSize.X < 1000 then return 0.7 end
    return 1.0
end

-- ==========================================
-- 拖拽系统 (增强版：支持轨道滑动)
-- ==========================================
function Rubidium:MakeDraggable(target, draggingPart)
    draggingPart = draggingPart or target
    local dragging, dragInput, dragStart, startPos
    
    local function update(input)
        local delta = input.Position - dragStart
        local scale = self:GetScale()
        
        -- [Logic] 默认自由移动
        local newX = startPos.X.Offset + delta.X
        local newY = startPos.Y.Offset + delta.Y
        
        -- [Fix 2] 分离模式下 Sidebar 的轨道限制逻辑
        if self.State == "Detached" and target.Name == "Sidebar" then
            local screenWidth = Camera.ViewportSize.X
            local mouseX = input.Position.X
            
            -- 判断靠左还是靠右
            if mouseX < screenWidth / 2 then
                -- 锁定在左边缘 (留 10px 间隙)
                newX = 10 
            else
                -- 锁定在右边缘
                newX = screenWidth - (target.Size.X.Offset) - 10
            end
            
            -- Y轴允许自由滑动，但限制在屏幕内
            -- 这里可以加 Clamp，暂时保持自由
        end

        local newPos = UDim2.new(
            startPos.X.Scale, newX,
            startPos.Y.Scale, newY
        )
        
        -- 使用极短的 Tween 代替直接赋值，保持手感
        TweenService:Create(target, TweenInfo.new(0.05), {Position = newPos}):Play()
    end

    draggingPart.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    -- 拖拽结束时的吸附检查 (CheckSnap 依然保留用于处理特殊吸附动画)
                    if self.State == "Detached" and target.Name == "Sidebar" then
                        self:CheckSnap(target)
                    end
                end
            end)
        end
    end)

    draggingPart.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

-- ==========================================
-- 创建窗口 (UI 细节调整)
-- ==========================================
function Rubidium:CreateWindow(options)
    local scale = self:GetScale()
    local currentSize = self.Config.BaseSize * scale
    local sbWidth = self.Config.SidebarWidth * scale
    
    options = options or {}
    local title = options.Title or "Rubidium"
    local subtitle = options.Subtitle or "UI Library"
    
    local screenGui = Create("ScreenGui", {
        Name = "RubidiumGui",
        Parent = CoreGui,
        ResetOnSpawn = false
    })

    -- Sidebar (保持不变)
    local sidebarFrame = Create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = self.Config.SidebarBg,
        Size = UDim2.new(0, sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0, -150, 0.5, -currentSize.Y/2),
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
        Create("ImageLabel", {
            Name = "AppIcon",
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, -15 * scale, 0, 10 * scale),
            Size = UDim2.new(0, 30 * scale, 0, 30 * scale),
            Image = "rbxassetid://18867303038",
            ImageColor3 = self.Config.ThemeColor
        })
    })

    -- ToggleArrow (保持不变)
    local toggleArrow = Create("ImageButton", {
        Name = "ToggleArrow",
        BackgroundColor3 = self.Config.SidebarBg,
        Position = UDim2.new(1, -5, 0.5, -15), 
        Size = UDim2.new(0, 20, 0, 30),
        Visible = false, 
        ZIndex = 0, 
        Image = "rbxassetid://6031091004", 
        Parent = sidebarFrame
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 4)})
    })

    -- MainFrame (保持不变)
    local mainFrame = Create("Frame", {
        Name = "MainFrame",
        BackgroundColor3 = self.Config.MainBg,
        Size = UDim2.new(0, currentSize.X - sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0.5, (-currentSize.X/2) + sbWidth, 0.5, -currentSize.Y/2),
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)})
    })

    -- TitleBar (细节调整)
    local titleBar = Create("Frame", {
        Name = "TitleBar",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40 * scale),
        Parent = mainFrame
    }, {
        -- [Fix 3] 调整边距，从 20 改为 10，使其紧贴 UI 边缘
        Create("TextLabel", {
            Name = "Title",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10 * scale, 0, 5 * scale), -- Reduced padding
            Size = UDim2.new(0, 200, 0, 16 * scale),
            Font = Enum.Font.GothamBold,
            Text = title,
            TextColor3 = self.Config.TextColor,
            TextSize = 16 * scale,
            TextXAlignment = Enum.TextXAlignment.Left
        }),
        Create("TextLabel", {
            Name = "Subtitle",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10 * scale, 0, 22 * scale), -- Reduced padding
            Size = UDim2.new(0, 200, 0, 12 * scale),
            Font = Enum.Font.Gotham,
            Text = subtitle,
            TextColor3 = self.Config.SubTextColor,
            TextSize = 12 * scale,
            TextXAlignment = Enum.TextXAlignment.Left
        })
    })

    -- Controls (保持不变)
    local controls = Create("Frame", {
        Name = "Controls",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.new(0, 100 * scale, 1, 0),
        Parent = titleBar
    })
    
    local layout = Create("UIListLayout", {
        Parent = controls,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        HorizontalAlignment = Enum.HorizontalAlignment.Right
    })

    local function addBtn(id, icon, order, fn)
        local btn = Create("ImageButton", {
            Name = id,
            LayoutOrder = order,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 25 * scale, 0, 25 * scale),
            Image = icon,
            ImageColor3 = self.Config.SubTextColor,
            Parent = controls
        })
        btn.MouseButton1Click:Connect(fn)
    end

    addBtn("Detach", "rbxassetid://6031094678", 1, function() self:ToggleState() end) 
    addBtn("Fullscreen", "rbxassetid://6031094670", 2, function() 
        local win = self.ActiveWindows[1] 
        if win then
            win.IsFullscreen = not win.IsFullscreen
            self:SetFullscreen(win, win.IsFullscreen)
        end
    end)
    addBtn("Close", "rbxassetid://6031090990", 3, function() screenGui:Destroy() end)

    local windowObj = { Instance = mainFrame, Sidebar = sidebarFrame, ToggleArrow = toggleArrow, Scale = scale, IsFullscreen = false }
    table.insert(self.ActiveWindows, windowObj)

    self:MakeDraggable(sidebarFrame) 
    self:MakeDraggable(mainFrame, titleBar) 

    self:InitialLoad(mainFrame, sidebarFrame)
    return windowObj
end

-- ==========================================
-- 布局与状态管理
-- ==========================================
function Rubidium:UpdateLayout()
    local scale = self:GetScale()
    local bSize = self.Config.BaseSize * scale
    local sbWidth = self.Config.SidebarWidth * scale

    -- [Fix 1] 标记动画开始，阻止 RenderStepped 干扰
    self.IsAnimating = true 

    for i, win in ipairs(self.ActiveWindows) do
        if win.IsFullscreen then 
            self.IsAnimating = false
            return 
        end 

        local targetPos, targetSize
        local sbTargetPos, sbTargetSize

        if self.State == "Unified" then
            win.ToggleArrow.Visible = false 
            
            targetSize = UDim2.new(0, bSize.X - sbWidth, 0, bSize.Y)
            targetPos = UDim2.new(0.5, (-bSize.X/2) + sbWidth, 0.5, -bSize.Y/2)
            
            sbTargetSize = UDim2.new(0, sbWidth, 0, bSize.Y)
            -- 动画目标：精确计算合并位置
            sbTargetPos = UDim2.new(
                targetPos.X.Scale, targetPos.X.Offset - sbWidth + 5,
                targetPos.Y.Scale, targetPos.Y.Offset
            )

        else
            win.ToggleArrow.Visible = true 
            
            targetSize = UDim2.new(0, bSize.X * 0.9, 0, bSize.Y * 0.9)
            targetPos = UDim2.new(0.5, - (bSize.X * 0.9)/2, 0.5, - (bSize.Y * 0.9)/2)
            
            sbTargetSize = UDim2.new(0, 60 * scale, 0, 300 * scale)
            sbTargetPos = UDim2.new(0, 10, 0.5, -150 * scale) -- 默认飞向左侧
        end

        local tMain = TweenService:Create(win.Instance, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = targetPos,
            Size = targetSize
        })
        tMain:Play()

        local tSb = TweenService:Create(win.Sidebar, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = sbTargetPos,
            Size = sbTargetSize
        })
        tSb:Play()
        
        -- [Fix 1] 动画结束回调
        tSb.Completed:Connect(function()
            self.IsAnimating = false -- 释放锁，允许 RenderStepped 接管吸附
        end)
    end
end

function Rubidium:ToggleState()
    self.State = (self.State == "Unified") and "Detached" or "Unified"
    self:UpdateLayout()
end

-- ==========================================
-- RenderStepped 循环
-- ==========================================
RunService.RenderStepped:Connect(function()
    -- [Fix 1] 只有在 Unified 模式 且 不在动画中 时才执行强制吸附
    if Rubidium.State == "Unified" and not Rubidium.IsAnimating then
        for _, win in ipairs(Rubidium.ActiveWindows) do
            if not win.IsFullscreen then
                local mainPos = win.Instance.Position
                local sbWidth = win.Sidebar.Size.X.Offset
                -- 实时吸附
                win.Sidebar.Position = UDim2.new(
                    mainPos.X.Scale, mainPos.X.Offset - sbWidth + 5, 
                    mainPos.Y.Scale, mainPos.Y.Offset
                )
            end
        end
    end
end)

-- 保留辅助函数
function Rubidium:SetFullscreen(win, isFull)
    -- ... (保持之前的代码不变)
    local scale = self:GetScale()
    local targetSize = isFull and UDim2.new(1, 0, 1, 0) or UDim2.new(0, (self.Config.BaseSize.X - self.Config.SidebarWidth) * scale, 0, self.Config.BaseSize.Y * scale)
    local targetPos = isFull and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, (-self.Config.BaseSize.X/2 * scale) + (self.Config.SidebarWidth * scale), 0.5, -self.Config.BaseSize.Y/2 * scale)
    
    TweenService:Create(win.Instance, TweenInfo.new(0.3), {
        Size = targetSize,
        Position = targetPos
    }):Play()
    
    if isFull then
        TweenService:Create(win.Sidebar, TweenInfo.new(0.3), { Position = UDim2.new(0, -200, 0, 0) }):Play()
    else
        self:UpdateLayout()
    end
end

function Rubidium:CheckSnap(sidebar)
    local scale = self:GetScale()
    local screenWidth = Camera.ViewportSize.X
    local sbPos = sidebar.AbsolutePosition
    
    -- 简单的回弹修正，如果用户拖拽太快导致脱离轨道，这里可以纠正
    local targetPos = nil
    if sbPos.X < screenWidth/2 then
         targetPos = UDim2.new(0, 10, 0.5, -sidebar.Size.Y.Offset/2) -- 左吸附修正
    else
         targetPos = UDim2.new(1, -sidebar.Size.X.Offset - 10, 0.5, -sidebar.Size.Y.Offset/2) -- 右吸附修正
    end

    if targetPos then
        TweenService:Create(sidebar, TweenInfo.new(0.3, Enum.EasingStyle.Back), {Position = targetPos}):Play()
    end
end

function Rubidium:InitialLoad(main, side)
    -- ... (保持之前的代码不变)
    side.Position = UDim2.new(0, -150, 0.5, -side.Size.Y.Offset/2)
    main.BackgroundTransparency = 1
    
    local t1 = TweenService:Create(side, TweenInfo.new(0.6, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5, (-self.Config.BaseSize.X/2), 0.5, -self.Config.BaseSize.Y/2)
    })
    
    t1:Play()
    t1.Completed:Connect(function()
        self:UpdateLayout()
        TweenService:Create(main, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
    end)
end

return Rubidium

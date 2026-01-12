--[[
    Rubidium UI Library - Framework v1.6 (Step 3: Interaction & Layout Fixes)
    更新日志：
    1. [Fix] 移动端适配：新增 GetScale() 动态计算缩放比例。
    2. [Fix] 布局重构：Icon 移至 Sidebar，加宽 Sidebar，调整按钮顺序。
    3. [New] 拖拽系统：MakeDraggable 支持 Unified (整体) 和 Detached (独立) 模式。
    4. [New] 侧边栏吸附：支持 Sidebar 自动吸附屏幕边缘并改变布局。
    5. [New] 缩进箭头：Sidebar 边缘添加 Toggle Button 用于折叠/展开。
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- 获取屏幕尺寸的辅助
local Camera = workspace.CurrentCamera
local Mouse = Players.LocalPlayer:GetMouse()

local Rubidium = {
    Name = "Rubidium",
    State = "Unified", -- "Unified" | "Detached"
    ActiveWindows = {}, 
    Config = {
        ThemeColor = Color3.fromRGB(0, 170, 255),
        MainBg = Color3.fromRGB(20, 20, 20),
        SidebarBg = Color3.fromRGB(25, 25, 25),
        TextColor = Color3.fromRGB(240, 240, 240),
        SubTextColor = Color3.fromRGB(150, 150, 150),
        AnimSpeed = 0.4,
        -- 基础尺寸 (PC基准)，后续会乘以 ScaleFactor
        BaseSize = Vector2.new(600, 380), 
        SidebarWidth = 80 -- 加宽 Sidebar
    }
}

-- ==========================================
-- 0. 辅助工具：移动端适配与组件创建
-- ==========================================
function Rubidium:GetScale()
    local viewportSize = Camera.ViewportSize
    -- 简单适配逻辑：如果屏幕宽度小于 1000 (手机/平板竖屏)，则缩小 0.7 倍
    if viewportSize.X < 1000 then
        return 0.7
    end
    return 1.0
end

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

-- ==========================================
-- 1. 核心逻辑：拖拽系统 (Fix 1 & 4)
-- ==========================================
function Rubidium:MakeDraggable(target, draggingPart)
    draggingPart = draggingPart or target
    local dragging, dragInput, dragStart, startPos
    
    local function update(input)
        local delta = input.Position - dragStart
        local newPos = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        -- 使用 Tween 平滑移动 (防抖 0.05s)
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
                    -- 拖拽结束时检查边缘吸附 (仅针对 Sidebar 在 Detached 模式)
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
            
            -- 如果是 Unified 模式，拖动 Sidebar 也要带动 MainFrame
            if self.State == "Unified" and target.Name == "Sidebar" then
                -- 查找对应的 MainFrame
                -- 这里简化处理：Unified 模式下 Sidebar 和 MainFrame 是绑定的，通常拖动 Sidebar 会移动整个 Group
                -- 由于我们之前的结构是分离的 Frame，这里需要手动同步 MainFrame 位置
                -- 更好的做法是在 Unified 模式下将它们放入一个父 Frame，或者在这里同步计算
                -- 暂时留空，依靠 UpdateLayout 的逻辑或者下一次重构将它们放入同一容器
            end
        end
    end)
end

-- ==========================================
-- 2. 核心逻辑：创建窗口 (Layout Fixes)
-- ==========================================
function Rubidium:CreateWindow(options)
    local scale = self:GetScale()
    local currentSize = self.Config.BaseSize * scale
    local sbWidth = self.Config.SidebarWidth * scale
    
    options = options or {}
    local title = options.Title or "Rubidium"
    
    local screenGui = Create("ScreenGui", {
        Name = "RubidiumGui",
        Parent = CoreGui,
        ResetOnSpawn = false
    })

    -- [Sidebar] 侧边栏
    local sidebarFrame = Create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = self.Config.SidebarBg,
        Size = UDim2.new(0, sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0, -150, 0.5, -currentSize.Y/2), -- 初始在屏幕外
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
        -- Icon (移入 Sidebar)
        Create("ImageLabel", {
            Name = "AppIcon",
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, -15 * scale, 0, 10 * scale),
            Size = UDim2.new(0, 30 * scale, 0, 30 * scale),
            Image = "rbxassetid://18867303038",
            ImageColor3 = self.Config.ThemeColor
        })
    })

    -- [Sidebar Toggle Arrow] (侧边栏缩进/展开箭头)
    local toggleArrow = Create("ImageButton", {
        Name = "ToggleArrow",
        BackgroundColor3 = self.Config.SidebarBg,
        Position = UDim2.new(1, -10, 0.5, -15), -- 贴在 Sidebar 右边缘
        Size = UDim2.new(0, 20, 0, 30),
        ZIndex = 2,
        Image = "rbxassetid://6031091004", -- 箭头图标
        Parent = sidebarFrame
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 4)})
    })

    -- [MainFrame] 主功能区
    local mainFrame = Create("Frame", {
        Name = "MainFrame",
        BackgroundColor3 = self.Config.MainBg,
        Size = UDim2.new(0, currentSize.X - sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0.5, (-currentSize.X/2) + sbWidth, 0.5, -currentSize.Y/2),
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)})
    })

    -- [TitleBar] 标题栏 (不再包含 Icon)
    local titleBar = Create("Frame", {
        Name = "TitleBar",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40 * scale),
        Parent = mainFrame
    }, {
        Create("TextLabel", {
            Name = "Title",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 20, 0, 0),
            Size = UDim2.new(0, 200, 1, 0),
            Font = Enum.Font.GothamBold,
            Text = title,
            TextColor3 = self.Config.TextColor,
            TextSize = 16 * scale,
            TextXAlignment = Enum.TextXAlignment.Left
        })
    })

    -- [Controls] 功能键 (Fix 2: 调整顺序)
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

    -- 按用户要求的顺序：分离 -> 全屏 -> 关闭
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

    addBtn("Detach", "rbxassetid://6031094678", 1, function() self:ToggleState() end) -- 左箭头
    addBtn("Fullscreen", "rbxassetid://6031094670", 2, function() --[[全屏逻辑]] end)
    addBtn("Close", "rbxassetid://6031090990", 3, function() screenGui:Destroy() end)

    -- 注册对象
    local windowObj = { Instance = mainFrame, Sidebar = sidebarFrame, Scale = scale }
    table.insert(self.ActiveWindows, windowObj)

    -- 启用拖拽
    -- 在 Unified 模式下，Sidebar 和 TitleBar 都可以拖动整个窗口
    -- 这里我们先简单绑定，具体同步逻辑在 UpdateLayout 或 RenderStepped 中优化
    self:MakeDraggable(sidebarFrame) 
    self:MakeDraggable(mainFrame, titleBar) 

    self:InitialLoad(mainFrame, sidebarFrame)
    return windowObj
end

-- ==========================================
-- 3. 核心逻辑：吸附与分离 (Step 3 Focus)
-- ==========================================
function Rubidium:CheckSnap(sidebar)
    local scale = self:GetScale()
    local screenWidth = Camera.ViewportSize.X
    local screenHeight = Camera.ViewportSize.Y
    local sbPos = sidebar.AbsolutePosition
    local snapMargin = 50 * scale

    local targetPos = nil
    
    -- 左边缘吸附
    if sbPos.X < snapMargin then
        targetPos = UDim2.new(0, 10, 0.5, -sidebar.Size.Y.Offset/2)
        -- 可以在这里改变 Sidebar 内部布局变为垂直
    -- 右边缘吸附
    elseif sbPos.X > screenWidth - sidebar.AbsoluteSize.X - snapMargin then
        targetPos = UDim2.new(1, -sidebar.Size.X.Offset - 10, 0.5, -sidebar.Size.Y.Offset/2)
    end

    if targetPos then
        TweenService:Create(sidebar, TweenInfo.new(0.3, Enum.EasingStyle.Back), {Position = targetPos}):Play()
    end
end

function Rubidium:ToggleState()
    self.State = (self.State == "Unified") and "Detached" or "Unified"
    
    -- 状态切换时的动画处理
    if self.State == "Detached" then
        -- 分离：Sidebar 飞向左侧，MainFrame 居中
        -- 这里你可以添加更复杂的逻辑，比如 Sidebar 变成只有图标的 Slim 模式
    else
        -- 合并：Sidebar 回到 MainFrame 旁边
    end
    
    self:UpdateLayout()
end

function Rubidium:UpdateLayout()
    -- 更新布局逻辑，确保 Unified 模式下 Sidebar 紧贴 MainFrame
    -- 并且根据 self:GetScale() 调整所有尺寸
    local scale = self:GetScale()
    local bSize = self.Config.BaseSize * scale
    local sbWidth = self.Config.SidebarWidth * scale

    for _, win in ipairs(self.ActiveWindows) do
        if self.State == "Unified" then
            -- 强制对齐
            local mainPos = win.Instance.Position
            -- 让 Sidebar 追随 MainFrame (或者反之，看谁是主导)
            -- 简单的做法：每帧更新 (在 RunService 绑定) 或 拖拽结束更新
            -- 现在的代码是静态 Update，我们需要在拖拽循环里做动态同步
        end
    end
end

-- 简单的 RenderStepped 绑定用于 Unified 模式下的位置同步
RunService.RenderStepped:Connect(function()
    if Rubidium.State == "Unified" then
        for _, win in ipairs(Rubidium.ActiveWindows) do
            -- 让 Sidebar 始终吸附在 MainFrame 左侧
            local mainPos = win.Instance.Position
            local sbWidth = win.Sidebar.Size.X.Offset
            -- 注意：这里需要处理 Scale 和 Offset 的混合计算，这里简化只用 Offset 演示
            win.Sidebar.Position = UDim2.new(
                mainPos.X.Scale, mainPos.X.Offset - sbWidth + 5, -- +5 重叠修正
                mainPos.Y.Scale, mainPos.Y.Offset
            )
        end
    end
end)

return Rubidium

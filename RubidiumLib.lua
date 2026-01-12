--[[
    Rubidium UI Library - Framework v1.5 (Gemini Integrated)
    核心整合：
    1. 动态对齐算法：根据 ActiveWindows 数量自动计算 Position 和 Size (对称/堆叠)。
    2. 全屏/还原逻辑：支持窗口状态切换。
    3. 连接动画：初始加载时侧边栏与功能栏的撞击合并。
    4. 侧边栏吸附：支持 Detached 模式下的边缘吸附。
    5. 状态管理：Unified (统一) vs Detached (分离) 模式切换。
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

-- 简单的 UI 创建辅助函数
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
    State = "Unified", -- "Unified" | "Detached"
    ActiveWindows = {}, -- 存储窗口对象 {Instance=Frame, Sidebar=Frame, IsFullscreen=false}
    Config = {
        ThemeColor = Color3.fromRGB(0, 170, 255),
        MainBg = Color3.fromRGB(20, 20, 20),
        SidebarBg = Color3.fromRGB(25, 25, 25),
        TextColor = Color3.fromRGB(240, 240, 240),
        SubTextColor = Color3.fromRGB(150, 150, 150),
        AnimSpeed = 0.5,
        BaseSize = Vector2.new(500, 350), -- 稍微调大一点以容纳 Sidebar
        SidebarWidth = 60
    }
}

-- ==========================================
-- 核心逻辑：创建窗口
-- ==========================================
function Rubidium:CreateWindow(options)
    options = options or {}
    local title = options.Title or "Rubidium"
    local subtitle = options.Subtitle or "UI Library"
    
    -- 1. 保护容器
    local screenGui = Create("ScreenGui", {
        Name = "RubidiumGui",
        Parent = CoreGui,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    })

    -- 2. 侧边栏 (Tab Bar) - 初始位置设在屏幕外用于入场动画
    local sidebarFrame = Create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = self.Config.SidebarBg,
        BorderSizePixel = 0,
        Size = UDim2.new(0, self.Config.SidebarWidth, 0, self.Config.BaseSize.Y),
        Position = UDim2.new(0, -100, 0.5, -self.Config.BaseSize.Y/2),
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)})
    })
    
    -- 3. 主功能区 (Main Function Bar)
    local mainFrame = Create("Frame", {
        Name = "MainFrame",
        BackgroundColor3 = self.Config.MainBg,
        BorderSizePixel = 0,
        Size = UDim2.new(0, self.Config.BaseSize.X - self.Config.SidebarWidth, 0, self.Config.BaseSize.Y),
        Position = UDim2.new(0.5, (-self.Config.BaseSize.X/2) + self.Config.SidebarWidth, 0.5, -self.Config.BaseSize.Y/2),
        Parent = screenGui
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)})
    })

    -- 4. 标题栏 (TitleBar)
    local titleBar = Create("Frame", {
        Name = "TitleBar",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40),
        Parent = mainFrame
    }, {
        -- Icon
        Create("ImageLabel", {
            Name = "Icon",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10, 0, 5),
            Size = UDim2.new(0, 30, 0, 30),
            Image = "rbxassetid://18867303038", -- 示例 Icon (Rubidium Logo placeholder)
            ImageColor3 = self.Config.ThemeColor
        }),
        -- Title
        Create("TextLabel", {
            Name = "Title",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 50, 0, 4),
            Size = UDim2.new(0, 200, 0, 16),
            Font = Enum.Font.GothamBold,
            Text = title,
            TextColor3 = self.Config.TextColor,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left
        }),
        -- Subtitle
        Create("TextLabel", {
            Name = "Subtitle",
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 50, 0, 20),
            Size = UDim2.new(0, 200, 0, 14),
            Font = Enum.Font.Gotham,
            Text = subtitle,
            TextColor3 = self.Config.SubTextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left
        })
    })

    -- 5. 功能键区域 (Control Buttons)
    local controls = Create("Frame", {
        Name = "Controls",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.new(0, 90, 1, 0),
        Parent = titleBar
    })

    -- 辅助创建按钮函数
    local function createControlBtn(name, iconId, layoutOrder, callback)
        local btn = Create("ImageButton", {
            Name = name,
            LayoutOrder = layoutOrder,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 30, 0, 30),
            Image = iconId,
            ImageColor3 = self.Config.SubTextColor,
            Parent = controls
        })
        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    local layout = Create("UIListLayout", {
        Parent = controls,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5)
    })

    -- [Button 1: Detach/Attach] (分离/合并)
    local detachBtn = createControlBtn("Detach", "rbxassetid://6031094678", 1, function()
        self:ToggleState()
    end) -- 需替换为合适的分离图标
    
    -- [Button 2: Fullscreen] (全屏)
    local fullBtn = createControlBtn("Fullscreen", "rbxassetid://6031094670", 2, function()
        -- 查找当前窗口对象并切换
        for _, win in ipairs(self.ActiveWindows) do
            if win.Instance == mainFrame then
                win.IsFullscreen = not win.IsFullscreen
                self:SetFullscreen(win, win.IsFullscreen)
            end
        end
    end)

    -- [Button 3: Close] (关闭)
    local closeBtn = createControlBtn("Close", "rbxassetid://6031094678", 3, function()
        screenGui:Destroy()
    end) -- 需替换为 'X' 图标

    -- 注册窗口对象
    local windowObj = {
        Instance = mainFrame,
        Sidebar = sidebarFrame,
        IsFullscreen = false
    }
    table.insert(self.ActiveWindows, windowObj)

    -- 初始入场动画
    self:InitialLoad(mainFrame, sidebarFrame)

    return windowObj
end

-- ==========================================
-- 1. 【核心数学算法】多窗口对称对齐逻辑 (更新版)
-- ==========================================
function Rubidium:UpdateLayout()
    local count = #self.ActiveWindows
    if count == 0 then return end

    for i, win in ipairs(self.ActiveWindows) do
        local targetPos, targetSize
        local bSize = self.Config.BaseSize
        local sbWidth = self.Config.SidebarWidth

        if win.IsFullscreen then return end -- 全屏时不参与自动布局

        if self.State == "Unified" then
            -- [Unified 模式]
            -- 整体居中，Sidebar 紧贴 MainFrame 左侧
            -- 这里我们只移动 MainFrame，Sidebar 在 UpdateSidebar 中跟随
            local mainWidth = bSize.X - sbWidth
            targetSize = UDim2.new(0, mainWidth, 0, bSize.Y)
            -- 居中计算：考虑到 Sidebar 和 MainFrame 是视觉整体
            -- 整体宽度 = bSize.X. 中心点 x = 0.5.
            -- MainFrame 左边缘应在 (ScreenCenter - TotalWidth/2) + SidebarWidth
            targetPos = UDim2.new(0.5, (-bSize.X/2) + sbWidth, 0.5, -bSize.Y/2)

        else
            -- [Detached 模式]
            -- Sidebar 飞走，MainFrame 独立排列 (根据你的算法)
            if count == 1 then
                targetSize = UDim2.new(0, bSize.X * 0.9, 0, bSize.Y * 0.9)
                targetPos = UDim2.new(0.5, - (bSize.X * 0.9)/2, 0.5, - (bSize.Y * 0.9)/2)
            elseif count == 2 then
                -- 左右对称，缩小
                local scale = 0.9
                targetSize = UDim2.new(0, bSize.X * scale, 0, bSize.Y * scale)
                targetPos = (i == 1) 
                    and UDim2.new(0.35, - (bSize.X * scale)/2, 0.5, -(bSize.Y * scale)/2)
                    or UDim2.new(0.65, - (bSize.X * scale)/2, 0.5, -(bSize.Y * scale)/2)
            else
                -- 3个及以上：网格/对角堆叠逻辑
                local scale = 0.8
                targetSize = UDim2.new(0, bSize.X * scale, 0, bSize.Y * scale)
                local row = math.ceil(i/2)
                local col = (i-1)%2 + 1
                targetPos = UDim2.new(0.25 * (col * 1.3), -(bSize.X * scale)/2, 0.2 * (row * 1.5), -(bSize.Y * scale)/2)
            end
        end

        TweenService:Create(win.Instance, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = targetPos,
            Size = targetSize
        }):Play()

        -- 同时更新 Sidebar 位置
        self:UpdateSidebar(win, targetPos, targetSize)
    end
end

-- ==========================================
-- 2. 【侧边栏逻辑】跟随与吸附
-- ==========================================
function Rubidium:UpdateSidebar(win, mainTargetPos, mainTargetSize)
    local targetPos, targetSize
    local sbWidth = self.Config.SidebarWidth

    if self.State == "Unified" then
        -- [Unified]: Sidebar 吸附在 MainFrame 左侧
        -- 它的位置由 MainFrame 的目标位置反推
        targetSize = UDim2.new(0, sbWidth, mainTargetSize.Y.Scale, mainTargetSize.Y.Offset)
        
        -- MainFrame.Position 是它的左上角。Sidebar 应该在 MainFrame.X - SidebarWidth
        -- 注意：这里需要处理 UDim2 的 Scale 和 Offset 计算，简单起见我们假设 mainTargetPos 已经计算好了
        targetPos = UDim2.new(
            mainTargetPos.X.Scale, 
            mainTargetPos.X.Offset - sbWidth + 5, -- +5 制造一点重叠/连接感
            mainTargetPos.Y.Scale, 
            mainTargetPos.Y.Offset
        )
    else
        -- [Detached]: Sidebar 吸附在屏幕左边缘 (Icon Mode)
        -- 高度缩小以适应 Icon 列表
        targetSize = UDim2.new(0, 50, 0, 300) 
        targetPos = UDim2.new(0, 10, 0.5, -150)
    end

    TweenService:Create(win.Sidebar, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = targetPos,
        Size = targetSize
    }):Play()
end

-- ==========================================
-- 3. 【状态切换逻辑】
-- ==========================================
function Rubidium:ToggleState()
    if self.State == "Unified" then
        self.State = "Detached"
    else
        self.State = "Unified"
    end
    -- 触发重新布局
    self:UpdateLayout()
end

-- ==========================================
-- 4. 【加载动画】(保留原逻辑并微调)
-- ==========================================
function Rubidium:InitialLoad(mainFrame, sidebarFrame)
    -- 初始状态：Sidebar在左侧屏幕外，Main在中间透明
    sidebarFrame.Position = UDim2.new(0, -100, 0.5, -150)
    mainFrame.BackgroundTransparency = 1
    
    -- 1. Sidebar 飞入
    local t1 = TweenService:Create(sidebarFrame, TweenInfo.new(0.6, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5, (-self.Config.BaseSize.X/2), 0.5, -self.Config.BaseSize.Y/2) -- 临时位置
    })
    
    t1:Play()
    t1.Completed:Connect(function()
        -- 2. 立即刷新一次布局以确保对齐
        self:UpdateLayout()
        
        -- 3. “撞击”合并效果，MainFrame 显现
        TweenService:Create(mainFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
        
        -- 抖动反馈 (对 MainFrame 和 Sidebar 一起做)
        -- 这里简化，只让 UpdateLayout 的 easing 负责
    end)
end

-- ==========================================
-- 5. 【全屏逻辑】
-- ==========================================
function Rubidium:SetFullscreen(win, isFull)
    local targetSize = isFull and UDim2.new(1, 0, 1, 0) or UDim2.new(0, self.Config.BaseSize.X - self.Config.SidebarWidth, 0, self.Config.BaseSize.Y)
    local targetPos = isFull and UDim2.new(0, 0, 0, 0) or UDim2.new(0.5, (-self.Config.BaseSize.X/2) + self.Config.SidebarWidth, 0.5, -self.Config.BaseSize.Y/2)
    
    -- 全屏时，Sidebar 隐藏或移动到极左
    local sbTargetPos = isFull and UDim2.new(0, -100, 0, 0) or UDim2.new(0.5, -self.Config.BaseSize.X/2, 0.5, -self.Config.BaseSize.Y/2)

    TweenService:Create(win.Instance, TweenInfo.new(0.3), {
        Size = targetSize,
        Position = targetPos
    }):Play()
    
    if isFull then
        -- 隐藏 Sidebar
        TweenService:Create(win.Sidebar, TweenInfo.new(0.3), {
             Position = UDim2.new(0, -200, 0, 0)
        }):Play()
    else
        -- 恢复布局
        self:UpdateLayout()
    end
end

return Rubidium
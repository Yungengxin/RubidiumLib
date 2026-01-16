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
        GlowColor = Color3.fromRGB(130, 80, 255), -- [User Request] Purple/Blue-ish Glow
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
        -- [Fix] 全屏模式下禁止拖动
        for _, win in pairs(self.ActiveWindows) do
            if win.Instance == target or win.Sidebar == target then
                if win.IsFullscreen then return end
            end
        end

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
            -- Y轴保持自由
        elseif self.State == "Unified" and target.Name == "Sidebar" then
             -- [Logic] Unified 模式下 Sidebar 作为子级，不应独立拖拽
             -- 这里的拖拽事件应该转发给 MainFrame 或者直接忽略
             -- 暂时忽略，让 MainFrame 的拖拽接管
             return
        end

        local newPos = UDim2.new(
            startPos.X.Scale, newX,
            startPos.Y.Scale, newY
        )
        
        TweenService:Create(target, TweenInfo.new(0.05), {Position = newPos}):Play()
    end

    draggingPart.InputBegan:Connect(function(input)
        -- [Fix] 全屏模式下禁止拖动
        for _, win in pairs(self.ActiveWindows) do
            if win.IsFullscreen and (win.Instance == target or win.Sidebar == target) then
                return
            end
        end

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
-- [Helper] Create Multi-Layer Glow
-- ==========================================
function Rubidium:CreateNeonGlow(parent, color)
    -- [User Request Match] 使用参考代码中的 Shader 逻辑 (rbxassetid://6906809185)
    -- 这实际上是一个背景阴影/光晕图层，放置在 MainFrame/Sidebar 内容下方
    
    local shader = Create("ImageLabel", {
        Name = "Shader", -- 保持与参考代码一致的命名习惯
        BackgroundTransparency = 1,
        ImageColor3 = color, -- 使用用户指定的光晕颜色 (紫色)
        Size = UDim2.new(1.1, 0, 1.1, 0), -- 稍微比父级大一点，形成向外发散效果
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Image = "rbxassetid://6906809185", -- 核心素材
        Parent = parent,
        ZIndex = 0, -- 确保在背景下方 (Background ZIndex 应为 1 或更高)
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(99, 99, 99, 99) -- 经验值，针对此素材的常用 Slice
    })
    
    return shader
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

    -- MainFrame (容器)
    -- [Refactor] MainFrame 现在只是一个透明的容器，实际背景由 Background 子元素负责
    -- 这样 Glow 可以作为 Background 的同级或父级元素而不被 Clip
    local mainFrame = Create("Frame", {
        Name = "MainFrame",
        BackgroundTransparency = 1, -- 容器透明
        Size = UDim2.new(0, currentSize.X - sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0.5, (-currentSize.X/2) + sbWidth, 0.5, -currentSize.Y/2),
        Parent = screenGui,
        ClipsDescendants = false 
    }, {
        Create("Frame", {
            Name = "Background",
            BackgroundColor3 = self.Config.MainBg,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 1
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
            
            -- [New] Double Layer Neon Glow
            -- Layer 1: Inner Sharp Stroke (Brightness Core)
            Create("UIStroke", {
                Name = "GlowInner",
                Thickness = 1,
                Transparency = 0.2, -- 较不透明，明亮
                Color = self.Config.GlowColor,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Enabled = true
            }),
            -- Layer 2: Outer Soft Stroke (Diffusion Halo) - Needs a wrapper to stack strokes?
            -- Roblox UIStroke per instance limit. 
            -- Solution: Create a hidden frame behind Background just for the outer glow stroke.
        }),
        
        -- [New] Outer Glow Layer (Behind Background)
        Create("Frame", {
            Name = "GlowLayer",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            ZIndex = 0
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
            Create("UIStroke", {
                Name = "GlowOuter",
                Thickness = 4, -- 更宽的扩散
                Transparency = 0.6, -- 较透明，柔和
                Color = self.Config.GlowColor,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            })
        })
    })

    -- Sidebar (初始父级设为 mainFrame)
    local sidebarFrame = Create("Frame", {
        Name = "Sidebar",
        BackgroundTransparency = 1, -- 容器透明
        Size = UDim2.new(0, sbWidth, 1, 0), 
        Position = UDim2.new(0, -sbWidth + 5, 0, 0), 
        Parent = mainFrame, 
        ZIndex = 2
    }, {
        -- [New] Actual Background
        Create("Frame", {
            Name = "Background",
            BackgroundColor3 = self.Config.SidebarBg,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 2
        }, {
             Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
             
             -- [New] Inner Glow
             Create("UIStroke", {
                Name = "GlowInner",
                Thickness = 1,
                Transparency = 0.2,
                Color = self.Config.GlowColor,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Enabled = false
             }),
             
             Create("ImageLabel", {
                Name = "AppIcon",
                BackgroundTransparency = 1,
                Position = UDim2.new(0.5, -15 * scale, 0, 10 * scale),
                Size = UDim2.new(0, 30 * scale, 0, 30 * scale),
                Image = "rbxassetid://18867303038",
                ImageColor3 = self.Config.ThemeColor,
                ZIndex = 3
            })
        }),
        
        -- [New] Outer Glow Layer (Behind Background)
        Create("Frame", {
            Name = "GlowLayer",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            ZIndex = 1 -- Sidebar Background is ZIndex 2
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
            Create("UIStroke", {
                Name = "GlowOuter",
                Thickness = 4,
                Transparency = 0.6,
                Color = self.Config.GlowColor,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                Enabled = false
            })
        })
    })

    -- [New] RightPatch: 用于遮挡侧边栏右侧圆角的补丁块
    -- 需要移动到 Background 内部或者作为 Background 的同级并保证 ZIndex 正确
    local rightPatch = Create("Frame", {
        Name = "RightPatch",
        BackgroundColor3 = self.Config.SidebarBg,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 10, 1, 0),
        Position = UDim2.new(1, -5, 0, 0), 
        Parent = sidebarFrame:FindFirstChild("Background"), -- Parent to Background
        ZIndex = 2, -- Same as Background
        Visible = true 
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
        Parent = sidebarFrame -- Parent to container is fine, or move to background?
                              -- ToggleArrow usually sticks out. Let's keep it on container for now, 
                              -- but it might need to be on top of background.
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 4)})
    })
    
    -- Fix ToggleArrow ZIndex to be above Glow but maybe below or above background?
    toggleArrow.ZIndex = 3

    -- TitleBar (Parent to MainFrame Container)
    local titleBar = Create("Frame", {
        Name = "TitleBar",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 40 * scale),
        Parent = mainFrame,
        ZIndex = 5 -- Ensure on top
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
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 5
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
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 5
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

    local controlBtns = {}
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
        controlBtns[id] = btn
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

    local windowObj = { 
        Instance = mainFrame, 
        Sidebar = sidebarFrame, 
        ToggleArrow = toggleArrow, 
        ControlBtns = controlBtns, -- Store buttons
        Scale = scale, 
        IsFullscreen = false,
        Tabs = {},
        CurrentTab = nil
    }

    -- [UI] Content Container (Main Content Area)
    local contentContainer = Create("Frame", {
        Name = "ContentContainer",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 40 * scale), -- Below TitleBar
        Size = UDim2.new(1, 0, 1, -40 * scale),
        Parent = mainFrame,
        ClipsDescendants = true
    }, {
        Create("UIPadding", {
            PaddingTop = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 10)
        })
    })

    -- [UI] Tab List Container (In Sidebar)
    
    -- [Visual] Divider Line
    local divider = Create("Frame", {
        Name = "Divider",
        BackgroundColor3 = Color3.fromRGB(50, 50, 50),
        BorderSizePixel = 0,
        Position = UDim2.new(0.1, 0, 0, 50 * scale),
        Size = UDim2.new(0.8, 0, 0, 1), -- Thin line
        Parent = sidebarFrame:FindFirstChild("Background"), -- Parent to Background
        ZIndex = 3
    })

    local tabList = Create("ScrollingFrame", {
        Name = "TabList",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 60 * scale), -- Below Divider
        Size = UDim2.new(1, 0, 1, -60 * scale),
        ScrollBarThickness = 0, -- Hide scrollbar for clean look
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = sidebarFrame:FindFirstChild("Background"), -- Parent to Background
        ZIndex = 3
    }, {
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            HorizontalAlignment = Enum.HorizontalAlignment.Center
        })
    })

    -- [Method] CreateTab
    function windowObj:CreateTab(name, iconId)
        local tabId = #self.Tabs + 1
        
        -- 1. Create Tab Button (Sidebar) - Icon Only
        local tabBtn = Create("ImageButton", {
            Name = name .. "_Btn",
            BackgroundColor3 = Rubidium.Config.SidebarBg, 
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 40 * scale, 0, 40 * scale), -- Square
            Image = "", -- Container
            AutoButtonColor = false,
            Parent = tabList,
            LayoutOrder = tabId,
            ZIndex = 4
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 8)}),
            -- Center Icon
            Create("ImageLabel", {
                Name = "Icon",
                BackgroundTransparency = 1,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(0, 24 * scale, 0, 24 * scale),
                Image = iconId or "rbxassetid://6031094678", 
                ImageColor3 = Rubidium.Config.SubTextColor,
                ZIndex = 5
            })
        })

        -- 2. Create Tab Content Page (Main)
        local tabPage = Create("ScrollingFrame", {
            Name = name .. "_Page",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Visible = false,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Rubidium.Config.ThemeColor,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            Parent = contentContainer
        }, {
            Create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
                HorizontalAlignment = Enum.HorizontalAlignment.Center
            }),
            Create("UIPadding", {
                PaddingTop = UDim.new(0, 2),
                PaddingBottom = UDim.new(0, 2)
            })
        })
        
        -- Auto Resize Canvas
        tabPage.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            tabPage.CanvasSize = UDim2.new(0, 0, 0, tabPage.UIListLayout.AbsoluteContentSize.Y + 10)
        end)

        local tabObj = { Button = tabBtn, Page = tabPage, Components = {} }

        -- [Logic] Switch Tab Function
        local function Activate()
            if self.CurrentTab == tabObj then return end
            
            -- Deactivate old
            if self.CurrentTab then
                local old = self.CurrentTab
                TweenService:Create(old.Button.Icon, TweenInfo.new(0.2), {ImageColor3 = Rubidium.Config.SubTextColor}):Play()
                TweenService:Create(old.Button, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
                old.Page.Visible = false
            end
            
            -- Activate new
            self.CurrentTab = tabObj
            tabObj.Page.Visible = true
            TweenService:Create(tabObj.Button.Icon, TweenInfo.new(0.2), {ImageColor3 = Rubidium.Config.ThemeColor}):Play()
            TweenService:Create(tabObj.Button, TweenInfo.new(0.2), {BackgroundTransparency = 0.9}):Play() -- Light highlight
        end

        tabBtn.MouseButton1Click:Connect(Activate)
        
        -- Select first tab automatically
        if #self.Tabs == 0 then Activate() end
        table.insert(self.Tabs, tabObj)

        -- [Component System Temporarily Removed]
        -- 等待后续指令逐步添加
        
        return tabObj
    end

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

        local screenGui = win.Instance.Parent -- MainFrame 的父级 (ScreenGui)
        local sbBackground = win.Sidebar:FindFirstChild("Background")
        local rightPatch = sbBackground and sbBackground:FindFirstChild("RightPatch")
        
        -- [Safe] 确保 ScreenGui 存在，防止已销毁报错
        if not screenGui then return end

        if self.State == "Unified" then
            -- [Logic] 切换到 Unified 模式
            win.ToggleArrow.Visible = false 
            
            -- [UI] 恢复按钮显示状态
            if win.ControlBtns["Fullscreen"] then win.ControlBtns["Fullscreen"].Visible = true end
            if win.ControlBtns["Detach"] then 
                win.ControlBtns["Detach"].LayoutOrder = 1 -- Reset position
                win.ControlBtns["Detach"].Image = "rbxassetid://6031094678" -- Detach Icon
            end

            -- [Animation Logic Fix]
            -- 不直接 Reparent，而是先计算 MainFrame 最终的位置，然后计算 Sidebar 应该去哪
            
            -- 1. MainFrame 的目标位置和大小
            local mainTargetSize = UDim2.new(0, bSize.X - sbWidth, 0, bSize.Y)
            local mainTargetPos = UDim2.new(0.5, (-bSize.X/2) + sbWidth, 0.5, -bSize.Y/2)
            
            if win.Sidebar.Parent == win.Instance then
                -- [Fix] 已经是父子关系 (如从全屏 Unified 返回)
                -- 直接 Tween 相对坐标，无需绝对坐标转换
                TweenService:Create(win.Instance, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = mainTargetPos,
                    Size = mainTargetSize
                }):Play()

                local tSb = TweenService:Create(win.Sidebar, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = UDim2.new(0, -sbWidth + 5, 0, 0), -- 恢复重叠偏移
                    Size = UDim2.new(0, sbWidth, 1, 0)
                })
                tSb:Play()
                
                tSb.Completed:Connect(function() 
                    self.IsAnimating = false 
                    if rightPatch then rightPatch.Visible = true end
                    
                    self:UpdateGlow(win) -- 确保动画结束更新光晕

                    -- [Fix Title] 调整标题位置
                    local titleBar = win.Instance:FindFirstChild("TitleBar")
                    if titleBar then
                        local title = titleBar:FindFirstChild("Title")
                        local subtitle = titleBar:FindFirstChild("Subtitle")
                        if title then 
                            TweenService:Create(title, TweenInfo.new(0.3), {Position = UDim2.new(0, 20 * scale, 0, 5 * scale)}):Play()
                        end
                        if subtitle then 
                            TweenService:Create(subtitle, TweenInfo.new(0.3), {Position = UDim2.new(0, 20 * scale, 0, 22 * scale)}):Play()
                        end
                    end
                end)
            else
                -- [Logic] Detached -> Unified (Sidebar 还在 ScreenGui)
                -- 2. Sidebar 在 Unified 模式下相对于 MainFrame 的偏移
                -- 它是 MainFrame 的子级，位置是 (-sbWidth + 5, 0)
                -- 我们需要算出这个相对位置在屏幕上的绝对坐标
                
                -- 由于 MainFrame 也是在缩放和移动，我们很难直接拿到它的 AbsolutePosition (因为它是 Tween 的目标)
                -- 我们可以通过视口大小计算出 MainFrame 的绝对目标位置
                -- [Fix] 使用 ScreenGui.AbsoluteSize 修复 TopBar 偏移问题
                local guiSize = screenGui.AbsoluteSize
                local mainAbsX = (guiSize.X * 0.5) + ((-bSize.X/2) + sbWidth) 
                local mainAbsY = (guiSize.Y * 0.5) - (bSize.Y/2)
                
                -- Sidebar 的目标绝对位置
                -- [Adjustment] 微调Y轴偏移，确保对齐
                local sbAbsX = mainAbsX + (-sbWidth + 5)
                local sbAbsY = mainAbsY
                local finalAbsPos = UDim2.new(0, sbAbsX, 0, sbAbsY)
                
                local sbTargetSize = UDim2.new(0, sbWidth, 0, bSize.Y) -- 此时高度跟随 MainFrame

                -- 执行动画
                TweenService:Create(win.Instance, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = mainTargetPos,
                    Size = mainTargetSize
                }):Play()

                local tSb = TweenService:Create(win.Sidebar, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = finalAbsPos,
                    Size = sbTargetSize
                })
                tSb:Play()
                
                -- [Fix] 动画结束后再 Reparent，保证平滑
                tSb.Completed:Connect(function() 
                    if self.State == "Unified" then
                        -- 恢复父子关系
                        win.Sidebar.Parent = win.Instance
                        -- 恢复相对坐标
                        win.Sidebar.Position = UDim2.new(0, -sbWidth + 5, 0, 0)
                        win.Sidebar.Size = UDim2.new(0, sbWidth, 1, 0)
                        
                        -- 显示遮罩
                        if rightPatch then rightPatch.Visible = true end
                        
                        -- 更新光晕状态
                        self:UpdateGlow(win)
                        
                        -- [Fix Title] 调整标题位置
                        local titleBar = win.Instance:FindFirstChild("TitleBar")
                        if titleBar then
                            local title = titleBar:FindFirstChild("Title")
                            local subtitle = titleBar:FindFirstChild("Subtitle")
                            if title then 
                                TweenService:Create(title, TweenInfo.new(0.3), {Position = UDim2.new(0, 20 * scale, 0, 5 * scale)}):Play()
                            end
                            if subtitle then 
                                TweenService:Create(subtitle, TweenInfo.new(0.3), {Position = UDim2.new(0, 20 * scale, 0, 22 * scale)}):Play()
                            end
                        end
                    end
                    self.IsAnimating = false 
                end)
            end

        else
            -- [Logic] 切换到 Detached 模式
            win.ToggleArrow.Visible = true 
            
            -- [UI] 隐藏全屏按钮，移动分离按钮
            if win.ControlBtns["Fullscreen"] then win.ControlBtns["Fullscreen"].Visible = false end
            if win.ControlBtns["Detach"] then 
                win.ControlBtns["Detach"].LayoutOrder = 2 -- Move to Fullscreen slot
                win.ControlBtns["Detach"].Image = "rbxassetid://6031094678" -- Keep Detach Icon (or change to Merge icon if preferred?)
                -- User said: "left merge button moves to fullscreen button position... converts to detach button"
                -- Wait, user said "from detached back to merged, merge button converts to detach button".
                -- So in Detached mode, it should be a "Merge" button conceptually, but user calls it "left merge button".
                -- Let's stick to the button logic: Detach button toggles state.
            end
            
            -- [Logic] 分离时，Sidebar 已经在 MainFrame 里，我们需要先把它拿出来放到 ScreenGui
            -- 并计算出它在屏幕上的绝对位置，让视觉上没有跳变
            
            local absPos = win.Sidebar.AbsolutePosition
            local absSize = win.Sidebar.AbsoluteSize
            
            -- 1. Reparent to ScreenGui
            win.Sidebar.Parent = screenGui 
            win.Sidebar.Position = UDim2.new(0, absPos.X, 0, absPos.Y)
            win.Sidebar.Size = UDim2.new(0, absSize.X, 0, absSize.Y)

            -- 2. 隐藏 RightPatch (恢复圆角)
            if rightPatch then rightPatch.Visible = false end
            
            -- [Fix Title] 恢复标题位置
            local titleBar = win.Instance:FindFirstChild("TitleBar")
            if titleBar then
                local title = titleBar:FindFirstChild("Title")
                local subtitle = titleBar:FindFirstChild("Subtitle")
                if title then title.Position = UDim2.new(0, 10 * scale, 0, 5 * scale) end
                if subtitle then subtitle.Position = UDim2.new(0, 10 * scale, 0, 22 * scale) end
            end

            -- 3. 动画目标
            local targetSize = UDim2.new(0, bSize.X * 0.9, 0, bSize.Y * 0.9)
            local targetPos = UDim2.new(0.5, - (bSize.X * 0.9)/2, 0.5, - (bSize.Y * 0.9)/2)
            
            -- Sidebar 飞向左侧
            local sbTargetSize = UDim2.new(0, 60 * scale, 0, 300 * scale)
            local sbTargetPos = UDim2.new(0, 10, 0.5, -150 * scale) 

            -- 执行动画
            TweenService:Create(win.Instance, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = targetPos,
                Size = targetSize
            }):Play()

            local tSb = TweenService:Create(win.Sidebar, TweenInfo.new(self.Config.AnimSpeed, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = sbTargetPos,
                Size = sbTargetSize
            })
            tSb:Play()
            tSb.Completed:Connect(function() 
                self.IsAnimating = false 
                self:UpdateGlow(win) -- 动画结束更新光晕
            end)
        end
    end
end

function Rubidium:ToggleState()
    self.State = (self.State == "Unified") and "Detached" or "Unified"
    self:UpdateLayout()
end

    function Rubidium:UpdateGlow(win)
        -- [New] 动态光晕更新 (Shader Logic)
        local mainShader = win.Instance:FindFirstChild("Shader")
        local sbShader = win.Sidebar:FindFirstChild("Shader")
        
        if not mainShader or not sbShader then return end
        
        if self.State == "Unified" and not self.IsAnimating then
             mainShader.Visible = true
             sbShader.Visible = false
             mainShader.ImageColor3 = self.Config.GlowColor
             mainShader.ImageTransparency = 0 -- 核心不透明度，可调
        elseif self.State == "Detached" and not self.IsAnimating then
             mainShader.Visible = true
             sbShader.Visible = true
             mainShader.ImageColor3 = self.Config.GlowColor
             sbShader.ImageColor3 = self.Config.GlowColor
             mainShader.ImageTransparency = 0
             sbShader.ImageTransparency = 0
        end
    end

    -- ==========================================
    -- RenderStepped 循环 (处理动态光晕)
    -- ==========================================
    RunService.RenderStepped:Connect(function()
        for _, win in pairs(Rubidium.ActiveWindows) do
            if Rubidium.IsAnimating then
                local mainShader = win.Instance:FindFirstChild("Shader")
                local sbShader = win.Sidebar:FindFirstChild("Shader")
                
                if mainShader and sbShader then
                    -- 计算距离
                    local sbPos = win.Sidebar.AbsolutePosition
                    local mainPos = win.Instance.AbsolutePosition
                    local dist = (Vector2.new(sbPos.X, sbPos.Y) - Vector2.new(mainPos.X, mainPos.Y)).Magnitude
                    
                    local maxDist = 300
                    local alpha = math.clamp(dist / maxDist, 0, 1)
                    
                    -- 动态调整
                    -- 分离时（Alpha -> 1）：变淡
                    -- 合并时（Alpha -> 0）：变亮（不透明）
                    local targetTrans = 0 + (0.5 * alpha) 
                    
                    mainShader.Visible = true
                    sbShader.Visible = true
                    
                    mainShader.ImageTransparency = targetTrans
                    sbShader.ImageTransparency = targetTrans
                    mainShader.ImageColor3 = Rubidium.Config.GlowColor
                    sbShader.ImageColor3 = Rubidium.Config.GlowColor
                end
            else
                 Rubidium:UpdateGlow(win)
            end
        end
    end)

    function Rubidium:SetFullscreen(win, isFull)
    local scale = self:GetScale()
    local sbWidth = self.Config.SidebarWidth * scale
    
    if not isFull then
        self:UpdateLayout()
        -- Restore buttons
        if self.State == "Unified" then
            if win.ControlBtns["Detach"] then win.ControlBtns["Detach"].Visible = true end
        end
        return
    end

    -- Fullscreen Logic
    -- User Request: Unified mode fullscreen should KEEP sidebar
    
    if self.State == "Unified" then
        -- [Fix] Unified Fullscreen Layout
        -- MainFrame 偏移以避开 Sidebar，Sidebar 负向偏移贴边
        
        -- 1. Sidebar (Child of MainFrame)
        -- Relative position: -sbWidth (Visual: 0 on screen)
        local sbTargetPos = UDim2.new(0, -sbWidth, 0, 0)
        local sbTargetSize = UDim2.new(0, sbWidth, 1, 0)
        
        -- 2. MainFrame (Fills rest of screen)
        local mainTargetPos = UDim2.new(0, sbWidth, 0, 0)
        local mainTargetSize = UDim2.new(1, -sbWidth, 1, 0)
        
        TweenService:Create(win.Sidebar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = sbTargetPos,
            Size = sbTargetSize
        }):Play()
        
        TweenService:Create(win.Instance, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = mainTargetPos,
            Size = mainTargetSize
        }):Play()

        -- Hide Detach button in fullscreen
        if win.ControlBtns["Detach"] then win.ControlBtns["Detach"].Visible = false end

    else
        -- Detached Fullscreen (Fallback if triggered)
        -- Just maximize main frame, hide sidebar? 
        -- User said button is hidden, so this shouldn't happen often.
        local targetSize = UDim2.new(1, 0, 1, 0)
        local targetPos = UDim2.new(0, 0, 0, 0)
        
        TweenService:Create(win.Instance, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = targetSize,
            Position = targetPos
        }):Play()
        
        -- Move sidebar out of view
        TweenService:Create(win.Sidebar, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, -200 * scale, 0, 0)
        }):Play()
    end
end

function Rubidium:CheckSnap(sidebar)
    if self.State ~= "Detached" then return end
    
    local screenWidth = Camera.ViewportSize.X
    local sbPos = sidebar.AbsolutePosition
    local snapMargin = 20
    
    local targetPos = nil
    
    -- 边缘吸附判定
    if sbPos.X < snapMargin then
         targetPos = UDim2.new(0, 10, 0.5, -sidebar.Size.Y.Offset/2) 
    elseif sbPos.X > screenWidth - sidebar.AbsoluteSize.X - snapMargin then
         targetPos = UDim2.new(1, -sidebar.Size.X.Offset - 10, 0.5, -sidebar.Size.Y.Offset/2)
    end

    if targetPos then
        TweenService:Create(sidebar, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos}):Play()
    end
end

function Rubidium:InitialLoad(main, side)
    -- 初始入场动画
    local mainBg = main:FindFirstChild("Background")
    if mainBg then
        mainBg.BackgroundTransparency = 1
        -- 淡入效果
        TweenService:Create(mainBg, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0
        }):Play()
    end
    
    -- 强制刷新一次布局以确保位置正确
    self:UpdateLayout()
end

return Rubidium

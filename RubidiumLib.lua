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

    -- MainFrame (容器)
    local mainFrame = Create("Frame", {
        Name = "MainFrame",
        BackgroundColor3 = self.Config.MainBg,
        Size = UDim2.new(0, currentSize.X - sbWidth, 0, currentSize.Y),
        Position = UDim2.new(0.5, (-currentSize.X/2) + sbWidth, 0.5, -currentSize.Y/2),
        Parent = screenGui,
        ClipsDescendants = false -- 允许子元素(如侧边栏)在动画时超出边界
    }, {
        Create("UICorner", {CornerRadius = UDim.new(0, 8)})
    })

    -- Sidebar (初始父级设为 mainFrame)
    local sidebarFrame = Create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = self.Config.SidebarBg,
        Size = UDim2.new(0, sbWidth, 1, 0), -- 高度填满 MainFrame
        Position = UDim2.new(0, -sbWidth + 5, 0, 0), -- 初始位置在 MainFrame 左侧重叠
        Parent = mainFrame, -- [Change] 初始作为子级
        ZIndex = 2
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

    -- [New] RightPatch: 用于遮挡侧边栏右侧圆角的补丁块
    local rightPatch = Create("Frame", {
        Name = "RightPatch",
        BackgroundColor3 = self.Config.SidebarBg,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 10, 1, 0),
        Position = UDim2.new(1, -5, 0, 0), -- 盖在 Sidebar 右边缘
        Parent = sidebarFrame,
        ZIndex = 2,
        Visible = true -- 初始 Unified 状态下可见
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

    local windowObj = { 
        Instance = mainFrame, 
        Sidebar = sidebarFrame, 
        ToggleArrow = toggleArrow, 
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
    local tabList = Create("ScrollingFrame", {
        Name = "TabList",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 50 * scale), -- Below AppIcon
        Size = UDim2.new(1, 0, 1, -50 * scale),
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.Config.ThemeColor,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Parent = sidebarFrame
    }, {
        Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            HorizontalAlignment = Enum.HorizontalAlignment.Center
        })
    })

    -- [Method] CreateTab
    function windowObj:CreateTab(name, iconId)
        local tabId = #self.Tabs + 1
        
        -- 1. Create Tab Button (Sidebar)
        local tabBtn = Create("TextButton", {
            Name = name .. "_Btn",
            BackgroundColor3 = Rubidium.Config.SidebarBg, -- Default
            BackgroundTransparency = 1,
            Size = UDim2.new(0.8, 0, 0, 30 * scale),
            Text = "",
            AutoButtonColor = false,
            Parent = tabList,
            LayoutOrder = tabId
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
            Create("TextLabel", {
                Name = "Title",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 30 * scale, 0, 0),
                Size = UDim2.new(1, -30 * scale, 1, 0),
                Font = Enum.Font.GothamMedium,
                Text = name,
                TextColor3 = Rubidium.Config.SubTextColor,
                TextSize = 12 * scale,
                TextXAlignment = Enum.TextXAlignment.Left
            }),
            Create("ImageLabel", {
                Name = "Icon",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 5 * scale, 0.5, -8 * scale),
                Size = UDim2.new(0, 16 * scale, 0, 16 * scale),
                Image = iconId or "rbxassetid://6031094678", -- Default Icon
                ImageColor3 = Rubidium.Config.SubTextColor
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
                TweenService:Create(old.Button.Title, TweenInfo.new(0.2), {TextColor3 = Rubidium.Config.SubTextColor}):Play()
                TweenService:Create(old.Button.Icon, TweenInfo.new(0.2), {ImageColor3 = Rubidium.Config.SubTextColor}):Play()
                TweenService:Create(old.Button, TweenInfo.new(0.2), {BackgroundTransparency = 1}):Play()
                old.Page.Visible = false
            end
            
            -- Activate new
            self.CurrentTab = tabObj
            tabObj.Page.Visible = true
            TweenService:Create(tabObj.Button.Title, TweenInfo.new(0.2), {TextColor3 = Rubidium.Config.ThemeColor}):Play()
            TweenService:Create(tabObj.Button.Icon, TweenInfo.new(0.2), {ImageColor3 = Rubidium.Config.ThemeColor}):Play()
            TweenService:Create(tabObj.Button, TweenInfo.new(0.2), {BackgroundTransparency = 0.9}):Play() -- Light highlight
        end

        tabBtn.MouseButton1Click:Connect(Activate)
        
        -- Select first tab automatically
        if #self.Tabs == 0 then Activate() end
        table.insert(self.Tabs, tabObj)

        -- ==========================================
        -- Component System (Inside Tab)
        -- ==========================================
        
        -- [Component] Button
        function tabObj:CreateButton(text, callback)
            callback = callback or function() end
            
            local btnFrame = Create("Frame", {
                Name = "ButtonFrame",
                BackgroundColor3 = Rubidium.Config.SidebarBg, -- Darker shade
                Size = UDim2.new(1, -10, 0, 32 * scale),
                Parent = tabPage
            }, {
                Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
                Create("UIStroke", {
                    Color = Rubidium.Config.ThemeColor,
                    Transparency = 0.8,
                    Thickness = 1,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                })
            })

            local btn = Create("TextButton", {
                Name = "Button",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Font = Enum.Font.Gotham,
                Text = text,
                TextColor3 = Rubidium.Config.TextColor,
                TextSize = 13 * scale,
                Parent = btnFrame
            })

            -- Animation
            btn.MouseButton1Down:Connect(function()
                TweenService:Create(btnFrame, TweenInfo.new(0.1), {BackgroundColor3 = Rubidium.Config.ThemeColor}):Play()
            end)
            
            btn.MouseButton1Up:Connect(function()
                TweenService:Create(btnFrame, TweenInfo.new(0.2), {BackgroundColor3 = Rubidium.Config.SidebarBg}):Play()
                callback()
            end)
            
            btn.MouseLeave:Connect(function()
                TweenService:Create(btnFrame, TweenInfo.new(0.2), {BackgroundColor3 = Rubidium.Config.SidebarBg}):Play()
            end)
            
            return btn
        end

        -- [Component] Toggle
        function tabObj:CreateToggle(text, default, callback)
            default = default or false
            callback = callback or function() end
            
            local toggled = default
            
            local toggleFrame = Create("Frame", {
                Name = "ToggleFrame",
                BackgroundColor3 = Rubidium.Config.SidebarBg,
                Size = UDim2.new(1, -10, 0, 32 * scale),
                Parent = tabPage
            }, {
                Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
                Create("UIStroke", {
                    Color = Rubidium.Config.ThemeColor,
                    Transparency = 0.9,
                    Thickness = 1
                }),
                Create("TextLabel", {
                    Name = "Label",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 0),
                    Size = UDim2.new(0.7, 0, 1, 0),
                    Font = Enum.Font.Gotham,
                    Text = text,
                    TextColor3 = Rubidium.Config.TextColor,
                    TextSize = 13 * scale,
                    TextXAlignment = Enum.TextXAlignment.Left
                })
            })
            
            local indicator = Create("Frame", {
                Name = "Indicator",
                BackgroundColor3 = toggled and Rubidium.Config.ThemeColor or Color3.fromRGB(50, 50, 50),
                Position = UDim2.new(1, -45 * scale, 0.5, -10 * scale),
                Size = UDim2.new(0, 35 * scale, 0, 20 * scale),
                Parent = toggleFrame
            }, {
                Create("UICorner", {CornerRadius = UDim.new(1, 0)})
            })
            
            local circle = Create("Frame", {
                Name = "Circle",
                BackgroundColor3 = Color3.new(1,1,1),
                Position = toggled and UDim2.new(1, -18 * scale, 0.5, -8 * scale) or UDim2.new(0, 2 * scale, 0.5, -8 * scale),
                Size = UDim2.new(0, 16 * scale, 0, 16 * scale),
                Parent = indicator
            }, {
                Create("UICorner", {CornerRadius = UDim.new(1, 0)})
            })

            local btn = Create("TextButton", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                Parent = toggleFrame
            })
            
            local function update()
                local targetColor = toggled and Rubidium.Config.ThemeColor or Color3.fromRGB(50, 50, 50)
                local targetPos = toggled and UDim2.new(1, -18 * scale, 0.5, -8 * scale) or UDim2.new(0, 2 * scale, 0.5, -8 * scale)
                
                TweenService:Create(indicator, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()
                TweenService:Create(circle, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = targetPos}):Play()
                
                callback(toggled)
            end
            
            btn.MouseButton1Click:Connect(function()
                toggled = not toggled
                update()
            end)
            
            -- Init call if default is true, but usually we just set visual state
            if default then 
                -- Just set visuals, avoid callback spam on init unless needed
                -- update() -- Call update to ensure correct state visual
            end
            
            return {
                Set = function(self, val) 
                    toggled = val 
                    update() 
                end
            }
        end
        
        -- [Component] Slider
        function tabObj:CreateSlider(text, min, max, default, callback)
            min = min or 0
            max = max or 100
            default = default or min
            callback = callback or function() end
            
            local dragging = false
            local value = default

            local sliderFrame = Create("Frame", {
                Name = "SliderFrame",
                BackgroundColor3 = Rubidium.Config.SidebarBg,
                Size = UDim2.new(1, -10, 0, 45 * scale),
                Parent = tabPage
            }, {
                Create("UICorner", {CornerRadius = UDim.new(0, 6)}),
                Create("TextLabel", {
                    Name = "Label",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 5),
                    Size = UDim2.new(1, -20, 0, 15),
                    Font = Enum.Font.Gotham,
                    Text = text,
                    TextColor3 = Rubidium.Config.TextColor,
                    TextSize = 13 * scale,
                    TextXAlignment = Enum.TextXAlignment.Left
                }),
                Create("TextLabel", {
                    Name = "ValueLabel",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -60, 0, 5),
                    Size = UDim2.new(0, 50, 0, 15),
                    Font = Enum.Font.GothamBold,
                    Text = tostring(default),
                    TextColor3 = Rubidium.Config.ThemeColor,
                    TextSize = 13 * scale,
                    TextXAlignment = Enum.TextXAlignment.Right
                })
            })
            
            local bar = Create("Frame", {
                Name = "Bar",
                BackgroundColor3 = Color3.fromRGB(40, 40, 40),
                Position = UDim2.new(0, 10, 0, 30 * scale),
                Size = UDim2.new(1, -20, 0, 4 * scale),
                Parent = sliderFrame
            }, {
                Create("UICorner", {CornerRadius = UDim.new(0, 2)})
            })
            
            local fill = Create("Frame", {
                Name = "Fill",
                BackgroundColor3 = Rubidium.Config.ThemeColor,
                Size = UDim2.new((default - min)/(max - min), 0, 1, 0),
                Parent = bar
            }, {
                Create("UICorner", {CornerRadius = UDim.new(0, 2)})
            })
            
            local trigger = Create("TextButton", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Position = UDim2.new(0,0,0,-10), -- Make hit area larger
                Text = "",
                Parent = bar
            })
            
            local valLabel = sliderFrame.ValueLabel
            
            local function update(input)
                local posX = input.Position.X
                local barAbsPos = bar.AbsolutePosition.X
                local barAbsSize = bar.AbsoluteSize.X
                
                local percent = math.clamp((posX - barAbsPos) / barAbsSize, 0, 1)
                value = math.floor(min + (max - min) * percent)
                
                TweenService:Create(fill, TweenInfo.new(0.05), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
                valLabel.Text = tostring(value)
                callback(value)
            end
            
            trigger.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    update(input)
                end
            end)
            
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = false
                end
            end)
            
            UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    update(input)
                end
            end)
            
            return {
                Set = function(self, val)
                    value = math.clamp(val, min, max)
                    local percent = (value - min) / (max - min)
                    TweenService:Create(fill, TweenInfo.new(0.2), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
                    valLabel.Text = tostring(value)
                    callback(value)
                end
            }
        end

        -- [Component] Label
        function tabObj:CreateLabel(text)
            local label = Create("TextLabel", {
                Name = "Label",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -10, 0, 20 * scale),
                Font = Enum.Font.Gotham,
                Text = text,
                TextColor3 = Rubidium.Config.SubTextColor,
                TextSize = 13 * scale,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = tabPage
            })
            return label
        end

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
        local rightPatch = win.Sidebar:FindFirstChild("RightPatch")
        
        -- [Safe] 确保 ScreenGui 存在，防止已销毁报错
        if not screenGui then return end

        if self.State == "Unified" then
            -- [Logic] 切换到 Unified 模式
            win.ToggleArrow.Visible = false 
            
            -- 1. Reparent: 先将 Sidebar 放回 MainFrame
            win.Sidebar.Parent = win.Instance
            
            -- 2. 设置 RightPatch 可见 (遮挡圆角)
            if rightPatch then rightPatch.Visible = true end

            -- 3. 动画目标
            local targetSize = UDim2.new(0, bSize.X - sbWidth, 0, bSize.Y)
            local targetPos = UDim2.new(0.5, (-bSize.X/2) + sbWidth, 0.5, -bSize.Y/2)
            
            -- Sidebar 在 Unified 模式下相对于 MainFrame 的位置
            -- 高度填满，宽度固定，位于左侧稍微重叠
            local sbTargetSize = UDim2.new(0, sbWidth, 1, 0)
            local sbTargetPos = UDim2.new(0, -sbWidth + 5, 0, 0)

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
            tSb.Completed:Connect(function() self.IsAnimating = false end)

        else
            -- [Logic] 切换到 Detached 模式
            win.ToggleArrow.Visible = true 
            
            -- 1. Reparent: 将 Sidebar 移出到 ScreenGui (或原父级)
            -- 为了保证动画连贯，我们需要先计算绝对位置，转换坐标系，再 Reparent
            local absPos = win.Sidebar.AbsolutePosition
            local absSize = win.Sidebar.AbsoluteSize
            
            -- 设置为 ScreenGui 的子级
            win.Sidebar.Parent = screenGui 
            -- 临时保持位置不变，避免跳变 (Position 使用 Offset)
            win.Sidebar.Position = UDim2.new(0, absPos.X, 0, absPos.Y)
            win.Sidebar.Size = UDim2.new(0, absSize.X, 0, absSize.Y)

            -- 2. 隐藏 RightPatch (恢复圆角)
            if rightPatch then rightPatch.Visible = false end

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
            tSb.Completed:Connect(function() self.IsAnimating = false end)
        end
    end
end

function Rubidium:ToggleState()
    self.State = (self.State == "Unified") and "Detached" or "Unified"
    self:UpdateLayout()
end

-- ==========================================
-- RenderStepped 循环 (预留)
-- ==========================================
-- 暂时不需要高频循环，为了性能优化将其移除，如有物理需求可解除注释
-- RunService.RenderStepped:Connect(function() end)

function Rubidium:SetFullscreen(win, isFull)
    local scale = self:GetScale()
    local viewport = Camera.ViewportSize
    
    if not isFull then
        self:UpdateLayout()
        return
    end

    -- 全屏模式逻辑
    local targetSize = UDim2.new(1, 0, 1, 0)
    local targetPos = UDim2.new(0, 0, 0, 0)
    
    local t = TweenService:Create(win.Instance, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = targetSize,
        Position = targetPos
    })
    t:Play()
    
    -- 全屏时隐藏 Sidebar
    local sideT = TweenService:Create(win.Sidebar, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, -150 * scale, 0, 0) -- 移出屏幕
    })
    sideT:Play()
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
    main.BackgroundTransparency = 1
    
    -- 强制刷新一次布局以确保位置正确
    self:UpdateLayout()
    
    -- 淡入效果
    TweenService:Create(main, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0
    }):Play()
end

return Rubidium

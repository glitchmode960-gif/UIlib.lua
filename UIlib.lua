--[[
	UILib (Hub style) — UI-библиотека для Roblox, как на твоих скриншотах:
	  • тёмное окно с боковым меню (вкладки)
	  • кнопки окна: свернуть / развернуть / закрыть
	  • свёрнутый вид — маленькая "таблетка" с градиентной рамкой
	  • секции с карточками: Info, Input, Button, Toggle, Slider, Dropdown

	Работает в Studio (ModuleScript) и в executor (gethui / CoreGui).

	ПРИМЕР:

	local UILib = require(game.ReplicatedStorage.UILib) -- в executor: вставь код выше и убери require

	local window = UILib.new({
		Title = "Camera TD Hub",
		Subtitle = "Kero",
		Icon = "◉",                  -- или rbxassetid://123456
	})

	window:AddTab("Lobby", "⌂")
	window:AddTab("Match", "▦")
	window:AddTab("Auto Play", "▷")

	local macros = window:AddTab("Macros", "▣")
	local section = macros:AddSection("Macro State")

	local state = section:AddInfo("State: Playback armed", "Loaded desert | 65 actions")
	section:AddInput("Create Macro", "New desert", function(text) print(text) end)
	section:AddButton("Create New Macro", "＋", function() print("создано") end)
	section:AddDropdown("Select Macro", { "desert", "forest" }, "desert", function(v) print(v) end)
	section:AddToggle("Auto Skip", false, function(on) print(on) end)
	section:AddSlider("Speed", 1, 3, 1, function(v) print(v) end)

	state:SetTitle("State: Recording")   -- обновление текста на лету
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local UILib = {}
UILib.__index = UILib

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

UILib.Theme = {
	Background = Color3.fromRGB(22, 22, 25),
	Panel = Color3.fromRGB(28, 28, 32),
	Card = Color3.fromRGB(36, 36, 40),
	CardHover = Color3.fromRGB(46, 46, 52),
	Element = Color3.fromRGB(50, 50, 56),
	TabActive = Color3.fromRGB(46, 46, 52),
	Text = Color3.fromRGB(240, 240, 244),
	SubText = Color3.fromRGB(150, 150, 162),
	Accent = Color3.fromRGB(124, 92, 255),
	AccentAlt = Color3.fromRGB(60, 170, 255),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}

local SIDEBAR_WIDTH = 150
local TOPBAR_HEIGHT = 40

---------------------------------------------------------------------
-- Вспомогательные функции
---------------------------------------------------------------------

local function create(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function round(inst, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local function tween(inst, props, duration)
	local t = TweenService:Create(inst, TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quad), props)
	t:Play()
	return t
end

local function isPointerInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- gethui() -> CoreGui -> PlayerGui
local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end

	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		local test = Instance.new("Folder")
		local canParent = pcall(function()
			test.Parent = coreGui
		end)
		test:Destroy()
		if canParent then
			return coreGui
		end
	end

	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Иконка: текстовый символ или rbxassetid://
local function makeIcon(parent, icon, size, color, position)
	if type(icon) == "number" then
		icon = "rbxassetid://" .. icon
	end

	if type(icon) == "string" and string.find(icon, "rbxasset", 1, true) then
		return create("ImageLabel", {
			BackgroundTransparency = 1,
			Image = icon,
			ImageColor3 = color,
			Size = UDim2.fromOffset(size, size),
			Position = position,
		}, parent)
	end

	return create("TextLabel", {
		BackgroundTransparency = 1,
		Text = icon or "•",
		TextColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = size - 2,
		Size = UDim2.fromOffset(size, size),
		Position = position,
	}, parent)
end

local function colorProp(inst)
	return inst:IsA("ImageLabel") and "ImageColor3" or "TextColor3"
end

-- Перетаскивание target за handle
local function makeDraggable(handle, target, connections)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil

	table.insert(connections, handle.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dragging = true
			dragInput = input
			dragStart = input.Position
			startPos = target.Position
		end
	end))

	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input == dragInput or isPointerInput(input) then
			dragging = false
		end
	end))
end

---------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------

function UILib.new(options)
	if type(options) == "string" then
		options = { Title = options }
	end
	options = options or {}

	local theme = UILib.Theme
	local self = setmetatable({}, UILib)
	self._connections = {}
	self._tabs = {}
	self._activeTab = nil
	self._maximized = false
	self._normalSize = options.Size or UDim2.fromOffset(520, 320)
	self._normalPos = UDim2.fromScale(0.5, 0.5)
	self.Title = options.Title or "Window"
	self.Subtitle = options.Subtitle or ""
	local icon = options.Icon or "◉"

	self.Gui = create("ScreenGui", {
		Name = "UILib_" .. tostring(self.Title),
		ResetOnSpawn = false,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, getGuiParent())

	-- Главное окно
	self.Main = create("Frame", {
		Size = self._normalSize,
		Position = self._normalPos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
	}, self.Gui)
	round(self.Main, 12)
	create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Transparency = 0.92,
		Thickness = 1,
	}, self.Main)

	-- Зона перетаскивания (верхняя полоса)
	local dragArea = create("Frame", {
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
	}, self.Main)
	makeDraggable(dragArea, self.Main, self._connections)

	-- Шапка боковой панели
	makeIcon(self.Main, icon, 24, theme.Text, UDim2.fromOffset(14, 12))
	self.TitleLabel = create("TextLabel", {
		Size = UDim2.fromOffset(SIDEBAR_WIDTH - 50, 18),
		Position = UDim2.fromOffset(46, 10),
		BackgroundTransparency = 1,
		Text = self.Title,
		TextColor3 = theme.Text,
		Font = theme.FontBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, self.Main)
	self.SubtitleLabel = create("TextLabel", {
		Size = UDim2.fromOffset(SIDEBAR_WIDTH - 50, 14),
		Position = UDim2.fromOffset(46, 28),
		BackgroundTransparency = 1,
		Text = self.Subtitle,
		TextColor3 = theme.SubText,
		Font = theme.Font,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, self.Main)

	-- Кнопки окна
	local controls = create("Frame", {
		Size = UDim2.fromOffset(108, 28),
		Position = UDim2.new(1, -116, 0, 6),
		BackgroundTransparency = 1,
	}, self.Main)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, controls)

	local function controlButton(glyph, order, callback)
		local button = create("TextButton", {
			Size = UDim2.fromOffset(32, 28),
			BackgroundColor3 = theme.Element,
			BackgroundTransparency = 1,
			Text = glyph,
			TextColor3 = theme.SubText,
			Font = theme.FontBold,
			TextSize = 14,
			AutoButtonColor = false,
			LayoutOrder = order,
		}, controls)
		round(button, 6)
		table.insert(self._connections, button.MouseEnter:Connect(function()
			tween(button, { BackgroundTransparency = 0, TextColor3 = theme.Text })
		end))
		table.insert(self._connections, button.MouseLeave:Connect(function()
			tween(button, { BackgroundTransparency = 1, TextColor3 = theme.SubText })
		end))
		table.insert(self._connections, button.MouseButton1Click:Connect(callback))
		return button
	end

	controlButton("—", 1, function() self:Minimize() end)
	controlButton("▢", 2, function() self:ToggleMaximize() end)
	controlButton("✕", 3, function() self:Destroy() end)

	-- Список вкладок
	self.TabList = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, self.Main)
	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.TabList)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, self.TabList)

	-- Панель содержимого
	self.Panel = create("Frame", {
		Position = UDim2.fromOffset(SIDEBAR_WIDTH + 4, TOPBAR_HEIGHT + 2),
		Size = UDim2.new(1, -(SIDEBAR_WIDTH + 12), 1, -(TOPBAR_HEIGHT + 10)),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, self.Main)
	round(self.Panel, 10)

	-- Свёрнутый вид ("таблетка")
	self.Pill = create("Frame", {
		Size = UDim2.new(0, 0, 0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 22),
		BorderSizePixel = 0,
		Visible = false,
	}, self.Gui)
	round(self.Pill, 23)

	local stroke = create("UIStroke", {
		Thickness = 2,
		Color = Color3.new(1, 1, 1),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, self.Pill)
	create("UIGradient", {
		Color = ColorSequence.new(theme.Accent, theme.AccentAlt),
	}, stroke)

	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, self.Pill)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 18),
	}, self.Pill)

	local handle = create("TextButton", {
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
		Text = "✥",
		TextColor3 = theme.SubText,
		Font = theme.FontBold,
		TextSize = 18,
		AutoButtonColor = false,
		LayoutOrder = 1,
	}, self.Pill)
	makeDraggable(handle, self.Pill, self._connections)

	create("Frame", {
		Size = UDim2.fromOffset(1, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, self.Pill)

	local pillIcon = makeIcon(self.Pill, icon, 22, theme.Text, UDim2.new())
	pillIcon.LayoutOrder = 3

	local pillText = self.Subtitle ~= "" and (self.Subtitle .. " | " .. self.Title) or self.Title
	self.PillButton = create("TextButton", {
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = pillText,
		TextColor3 = theme.Text,
		Font = theme.FontBold,
		TextSize = 15,
		AutoButtonColor = false,
		LayoutOrder = 4,
	}, self.Pill)
	table.insert(self._connections, self.PillButton.MouseButton1Click:Connect(function()
		self:Restore()
	end))

	return self
end

---------------------------------------------------------------------
-- Управление окном
---------------------------------------------------------------------

function UILib:Minimize()
	self.Main.Visible = false
	self.Pill.Visible = true
end

function UILib:Restore()
	self.Pill.Visible = false
	self.Main.Visible = true
end

function UILib:ToggleMaximize()
	if self._maximized then
		self._maximized = false
		tween(self.Main, { Size = self._normalSize, Position = self._normalPos }, 0.2)
	else
		self._maximized = true
		self._normalPos = self.Main.Position
		tween(self.Main, {
			Size = UDim2.new(1, -40, 1, -40),
			Position = UDim2.fromScale(0.5, 0.5),
		}, 0.2)
	end
end

function UILib:SetVisible(visible)
	self.Gui.Enabled = visible
end

function UILib:SetTitle(title, subtitle)
	self.Title = tostring(title)
	self.TitleLabel.Text = self.Title
	if subtitle ~= nil then
		self.Subtitle = tostring(subtitle)
		self.SubtitleLabel.Text = self.Subtitle
	end
	self.PillButton.Text = self.Subtitle ~= "" and (self.Subtitle .. " | " .. self.Title) or self.Title
end

function UILib:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

---------------------------------------------------------------------
-- Вкладки
---------------------------------------------------------------------

function UILib:AddTab(name, icon)
	local theme = UILib.Theme
	local tab = setmetatable({}, Tab)
	tab.Window = self
	tab.Name = name
	tab._order = 0

	tab.Button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = theme.TabActive,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = #self._tabs + 1,
	}, self.TabList)
	round(tab.Button, 8)

	tab.Icon = makeIcon(tab.Button, icon or "•", 18, theme.SubText, UDim2.fromOffset(10, 8))
	tab.Label = create("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(36, 0),
		BackgroundTransparency = 1,
		Text = tostring(name),
		TextColor3 = theme.SubText,
		Font = theme.Font,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, tab.Button)

	tab.Page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, self.Panel)
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tab.Page)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 14),
	}, tab.Page)

	table.insert(self._connections, tab.Button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end))

	table.insert(self._tabs, tab)
	if not self._activeTab then
		self:SelectTab(tab)
	end

	return tab
end

function UILib:SelectTab(tab)
	local theme = UILib.Theme
	for _, t in ipairs(self._tabs) do
		local active = (t == tab)
		t.Page.Visible = active
		tween(t.Button, { BackgroundTransparency = active and 0 or 1 })
		tween(t.Label, { TextColor3 = active and theme.Text or theme.SubText })
		tween(t.Icon, { [colorProp(t.Icon)] = active and theme.Text or theme.SubText })
	end
	self._activeTab = tab
end

---------------------------------------------------------------------
-- Секции
---------------------------------------------------------------------

function Tab:AddSection(title)
	local theme = UILib.Theme
	local section = setmetatable({}, Section)
	section.Window = self.Window
	section._connections = self.Window._connections
	section._rows = 0
	section._lastDivider = nil

	self._order += 1
	section.TitleLabel = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = tostring(title),
		TextColor3 = theme.Text,
		Font = theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = self._order,
	}, self.Page)

	self._order += 1
	section.Card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.Card,
		BorderSizePixel = 0,
		LayoutOrder = self._order,
	}, self.Page)
	round(section.Card, 10)
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, section.Card)

	return section
end

function Section:_newRow(height, interactive)
	local theme = UILib.Theme

	-- у предыдущей строки показываем разделитель, у новой — нет
	if self._lastDivider then
		self._lastDivider.Visible = true
	end

	self._rows += 1
	local row = create(interactive and "TextButton" or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = theme.CardHover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = self._rows,
	}, self.Card)
	if interactive then
		row.Text = ""
		row.AutoButtonColor = false
	end
	round(row, 8)

	self._lastDivider = create("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.new(0, 12, 1, -1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		Visible = false,
	}, row)

	if interactive then
		table.insert(self._connections, row.MouseEnter:Connect(function()
			tween(row, { BackgroundTransparency = 0 })
		end))
		table.insert(self._connections, row.MouseLeave:Connect(function()
			tween(row, { BackgroundTransparency = 1 })
		end))
	end

	return row
end

local function rowTitle(row, text, reserve, height)
	local theme = UILib.Theme
	return create("TextLabel", {
		Size = UDim2.new(1, -reserve, 0, height),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Text = tostring(text),
		TextColor3 = theme.Text,
		Font = theme.Font,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
end

---------------------------------------------------------------------
-- Элементы
---------------------------------------------------------------------

-- Строка с заголовком и подписью (как "State: ..." на скриншоте)
function Section:AddInfo(title, subtitle)
	local theme = UILib.Theme
	local row = self:_newRow(58)

	local titleLabel = create("TextLabel", {
		Size = UDim2.new(1, -28, 0, 20),
		Position = UDim2.fromOffset(14, 9),
		BackgroundTransparency = 1,
		Text = tostring(title),
		TextColor3 = theme.Text,
		Font = theme.FontBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	local subLabel = create("TextLabel", {
		Size = UDim2.new(1, -28, 0, 16),
		Position = UDim2.fromOffset(14, 31),
		BackgroundTransparency = 1,
		Text = tostring(subtitle or ""),
		TextColor3 = theme.SubText,
		Font = theme.Font,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)

	return {
		Instance = row,
		SetTitle = function(_, text)
			titleLabel.Text = tostring(text)
		end,
		SetSubtitle = function(_, text)
			subLabel.Text = tostring(text)
		end,
	}
end

-- Строка с полем ввода справа
function Section:AddInput(title, default, callback)
	local theme = UILib.Theme
	local row = self:_newRow(54)
	rowTitle(row, title, 180, 54)

	local box = create("TextBox", {
		Size = UDim2.fromOffset(160, 32),
		Position = UDim2.new(1, -172, 0, 11),
		BackgroundColor3 = theme.Element,
		Text = tostring(default or ""),
		PlaceholderText = "...",
		PlaceholderColor3 = theme.SubText,
		TextColor3 = theme.Text,
		Font = theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
	}, row)
	round(box, 8)
	create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)

	table.insert(self._connections, box.FocusLost:Connect(function(enterPressed)
		if callback then
			task.spawn(callback, box.Text, enterPressed)
		end
	end))

	return {
		Instance = box,
		Get = function()
			return box.Text
		end,
		Set = function(_, text)
			box.Text = tostring(text)
		end,
	}
end

-- Кнопка-строка с иконкой справа
function Section:AddButton(title, icon, callback)
	local theme = UILib.Theme
	local row = self:_newRow(52, true)
	rowTitle(row, title, 60, 52)
	makeIcon(row, icon or "›", 20, theme.SubText, UDim2.new(1, -34, 0.5, -10))

	table.insert(self._connections, row.MouseButton1Click:Connect(function()
		if callback then
			task.spawn(callback)
		end
	end))

	return row
end

-- Переключатель
function Section:AddToggle(title, default, callback)
	local theme = UILib.Theme
	local state = default == true
	local row = self:_newRow(52, true)
	rowTitle(row, title, 80, 52)

	local track = create("Frame", {
		Size = UDim2.fromOffset(42, 22),
		Position = UDim2.new(1, -56, 0.5, -11),
		BackgroundColor3 = state and theme.Accent or theme.Element,
		BorderSizePixel = 0,
	}, row)
	round(track, 11)

	local knob = create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
		BackgroundColor3 = theme.Text,
		BorderSizePixel = 0,
	}, track)
	round(knob, 8)

	local function set(newState, silent)
		state = newState
		tween(track, { BackgroundColor3 = state and theme.Accent or theme.Element })
		tween(knob, { Position = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) })
		if callback and not silent then
			task.spawn(callback, state)
		end
	end

	table.insert(self._connections, row.MouseButton1Click:Connect(function()
		set(not state)
	end))

	return {
		Instance = row,
		Get = function()
			return state
		end,
		Set = function(_, value)
			set(value == true, true)
		end,
	}
end

-- Ползунок
function Section:AddSlider(title, min, max, default, callback)
	local theme = UILib.Theme
	local value = math.clamp(default or min, min, max)
	local row = self:_newRow(62)

	create("TextLabel", {
		Size = UDim2.new(1, -100, 0, 24),
		Position = UDim2.fromOffset(14, 8),
		BackgroundTransparency = 1,
		Text = tostring(title),
		TextColor3 = theme.Text,
		Font = theme.Font,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local valueLabel = create("TextLabel", {
		Size = UDim2.fromOffset(70, 24),
		Position = UDim2.new(1, -84, 0, 8),
		BackgroundTransparency = 1,
		TextColor3 = theme.SubText,
		Font = theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local hit = create("Frame", {
		Size = UDim2.new(1, -28, 0, 24),
		Position = UDim2.fromOffset(14, 34),
		BackgroundTransparency = 1,
	}, row)

	local bar = create("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		Position = UDim2.fromOffset(0, 8),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
	}, hit)
	round(bar, 4)

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
	}, bar)
	round(fill, 4)

	local function render()
		local alpha = (max > min) and (value - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(alpha, 1)
		valueLabel.Text = tostring(value)
	end

	local function setFromX(x)
		local alpha = math.clamp((x - hit.AbsolutePosition.X) / hit.AbsoluteSize.X, 0, 1)
		local newValue = math.round(min + (max - min) * alpha)
		if newValue ~= value then
			value = newValue
			render()
			if callback then
				task.spawn(callback, value)
			end
		end
	end

	local dragging, dragInput = false, nil

	table.insert(self._connections, hit.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dragging = true
			dragInput = input
			setFromX(input.Position.X)
		end
	end))
	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			setFromX(input.Position.X)
		end
	end))
	table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
		if input == dragInput or isPointerInput(input) then
			dragging = false
		end
	end))

	render()

	return {
		Instance = row,
		Get = function()
			return value
		end,
		Set = function(_, newValue)
			value = math.clamp(math.round(newValue), min, max)
			render()
		end,
	}
end

-- Выпадающий список (раскрывается прямо в строке)
function Section:AddDropdown(title, options, default, callback)
	local theme = UILib.Theme
	local HEADER, ITEM, MAX_VISIBLE = 52, 30, 5

	options = options or {}
	local current = default or options[1]
	local open = false

	local row = self:_newRow(HEADER)
	rowTitle(row, title, 200, HEADER)

	local header = create("TextButton", {
		Size = UDim2.fromOffset(180, 32),
		Position = UDim2.new(1, -192, 0, 10),
		BackgroundColor3 = theme.Element,
		Text = "",
		AutoButtonColor = false,
	}, row)
	round(header, 8)

	local valueLabel = create("TextLabel", {
		Size = UDim2.new(1, -36, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		Text = tostring(current or "—"),
		TextColor3 = theme.Text,
		Font = theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, header)

	local arrow = create("TextLabel", {
		Size = UDim2.fromOffset(24, 32),
		Position = UDim2.new(1, -28, 0, 0),
		BackgroundTransparency = 1,
		Text = "▾",
		TextColor3 = theme.SubText,
		Font = theme.FontBold,
		TextSize = 14,
	}, header)

	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(12, HEADER),
		Size = UDim2.new(1, -24, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, row)
	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local function listHeight()
		return math.min(#options, MAX_VISIBLE) * (ITEM + 4)
	end

	local function setOpen(state)
		open = state
		list.Size = UDim2.new(1, -24, 0, listHeight())
		tween(row, { Size = UDim2.new(1, 0, 0, HEADER + (state and listHeight() + 8 or 0)) })
		arrow.Text = state and "▴" or "▾"
	end

	local buildOptions

	local function select(value, silent)
		current = value
		valueLabel.Text = tostring(value)
		buildOptions()
		setOpen(false)
		if callback and not silent then
			task.spawn(callback, value)
		end
	end

	function buildOptions()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for index, option in ipairs(options) do
			local button = create("TextButton", {
				Size = UDim2.new(1, -4, 0, ITEM),
				BackgroundColor3 = theme.Element,
				Text = tostring(option),
				TextColor3 = (option == current) and theme.Accent or theme.Text,
				Font = theme.Font,
				TextSize = 13,
				AutoButtonColor = false,
				LayoutOrder = index,
			}, list)
			round(button, 6)
			table.insert(self._connections, button.MouseButton1Click:Connect(function()
				select(option)
			end))
		end
	end

	table.insert(self._connections, header.MouseButton1Click:Connect(function()
		setOpen(not open)
	end))

	buildOptions()

	return {
		Instance = row,
		Get = function()
			return current
		end,
		Set = function(_, value)
			select(value, true)
		end,
		SetOptions = function(_, newOptions, newDefault)
			options = newOptions or {}
			current = newDefault or options[1]
			valueLabel.Text = tostring(current or "—")
			buildOptions()
			if open then
				setOpen(true)
			end
		end,
	}
end

return UILib

-- The player's company (key K, server Services/Companies). Without one: the companies on every
-- server to join, and a form to found one. With one: its cash and share price, the player's
-- shares to buy or sell, the week's orders to deliver from the inventory, the members and what
-- happened lately. The founder can remove members and pay out a dividend once a day.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Items)
local Money = require(Shared.Money)
local Kit = require(script.Parent.Kit)
local ItemGrid = require(script.Parent.ItemGrid)
local Market = require(script.Parent.Market)
local Recipes = require(script.Parent.Recipes)
local Game = require(script.Parent.Parent.Game)

local Company = {}

local function box(parent, text, placeholder, width)
	return Kit.New("TextBox", {
		Size = UDim2.fromOffset(width, 30),
		BackgroundColor3 = Color3.fromRGB(24, 27, 33),
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = Kit.Colors.Text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Kit.Colors.Muted,
		Text = text,
		ClearTextOnFocus = false,
		Parent = parent,
	}, { Kit.Corner(6), Kit.New("UIStroke", { Color = Color3.fromRGB(90, 98, 115) }) })
end

local function heading(body, text, order)
	Kit.Label(body, text, { Font = Enum.Font.GothamBold, TextSize = 17, Size = UDim2.new(1, -8, 0, 28), LayoutOrder = order })
end

local function muted(body, text, order, height)
	Kit.Label(body, text, {
		TextSize = 13, TextColor3 = Kit.Colors.Muted, TextWrapped = true,
		Size = UDim2.new(1, -8, 0, height or 20), LayoutOrder = order,
	})
end

-- A button that asks once more before it acts: the first click turns it into "Na pewno?".
local function careful(parent, text, onConfirm, props)
	local armed = false
	local button
	button = Kit.Button(parent, text, function()
		if armed then
			onConfirm()
		else
			armed = true
			button.Text = "Na pewno? Kliknij"
			task.delay(4, function()
				if button.Parent then
					armed = false
					button.Text = text
				end
			end)
		end
	end, props)
	return button
end

local function timeLeft(seconds)
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	if days > 0 then
		return days .. " d " .. hours .. " h"
	end
	return hours .. " h " .. math.floor((seconds % 3600) / 60) .. " min"
end

-- Without a company: found one or join one.
local function outside(body, reply, call)
	muted(body, "Spółka to firma kilku graczy z różnych serwerów. Wspólnicy kupują udziały, razem wykonują cotygodniowe zlecenia i dzielą się dywidendą. Pociągi między wspólnikami są tańsze.", 1, 52)
	heading(body, "Załóż spółkę", 2)
	local row = Kit.Row(body, 44)
	row.LayoutOrder = 3
	local name = box(row, "", "Nazwa spółki", 260)
	Recipes.Action(row, "Załóż za " .. Money.Format(reply.foundingCents), Game.BalanceCents >= reply.foundingCents, function()
		call("CompanyCreate", { name = name.Text })
	end).Size = UDim2.fromOffset(220, 32)
	muted(body, "Wpłata trafia do kasy spółki, a Ty dostajesz za nią udziały.", 4)
	heading(body, "Spółki do dołączenia", 10)
	if #reply.list == 0 then
		muted(body, "Nie ma jeszcze żadnej spółki. Załóż pierwszą!", 11)
	end
	for i, c in ipairs(reply.list) do
		local r = Kit.Row(body, 38)
		r.LayoutOrder = 20 + i
		Kit.Label(r, "<b>" .. c.name .. "</b>   założyciel: " .. c.ownerName, { RichText = true, TextSize = 14, Size = UDim2.new(1, -110, 1, 0) })
		Kit.Button(r, "Dołącz", function()
			call("CompanyJoin", { id = c.id })
		end, { Size = UDim2.fromOffset(90, 28) })
	end
end

-- In a company.
local function inside(body, c, serverTime, call)
	local percent = c.shares > 0 and math.floor(c.myShares / c.shares * 1000 + 0.5) / 10 or 0
	local top = Kit.New("Frame", { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = Kit.Colors.Row, LayoutOrder = 1, Parent = body }, { Kit.Corner(8) })
	Kit.Label(top, c.name, { Font = Enum.Font.GothamBold, TextSize = 22, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 28) })
	Kit.Label(top, "Założyciel: " .. c.ownerName .. "   Wspólników: " .. #c.members .. "/" .. c.maxMembers, { TextSize = 14, TextColor3 = Kit.Colors.Muted, Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 20) })
	Kit.Label(top, "Kasa: <b>" .. Money.Format(c.cashCents) .. "</b>   Cena udziału: <b>" .. Money.Format(c.sharePriceCents) .. "</b>   Twoje udziały: <b>" .. c.myShares .. "</b> (" .. percent .. "%), warte " .. Money.Format(c.myValueCents), {
		RichText = true, TextSize = 14, TextColor3 = Kit.Colors.Money, TextWrapped = true, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 36),
	})

	heading(body, "Udziały", 10)
	local buy = Kit.Row(body, 40)
	buy.LayoutOrder = 11
	local cents = box(buy, "", "Kwota w $", 120)
	Kit.Button(buy, "Kup udziały", function()
		local value = Market.ParseCents(cents.Text)
		if value then
			call("CompanyDeposit", { cents = value })
		end
	end, { Size = UDim2.fromOffset(130, 28) })
	local shares = box(buy, "", "Ile udziałów", 120)
	Kit.Button(buy, "Sprzedaj", function()
		local n = math.floor(tonumber(shares.Text) or 0)
		if n > 0 then
			call("CompanySell", { shares = n })
		end
	end, { Size = UDim2.fromOffset(110, 28), BackgroundColor3 = Kit.Colors.ButtonAlt })
	muted(body, "Nowe udziały kupujesz po cenie udziału, a sprzedajesz spółce za " .. c.buybackPercent .. "% tej ceny.", 12)

	heading(body, "Zlecenia tygodnia (zostało " .. timeLeft(c.weekEndsAt - serverTime) .. ")", 20)
	muted(body, "Spółka dostaje za towar więcej niż u handlarza. Ty dostajesz udziały warte tyle, ile dałby handlarz, a reszta podnosi cenę udziałów wszystkich.", 21, 36)
	for i, o in ipairs(c.orders) do
		local r = Kit.Row(body, 46)
		r.LayoutOrder = 21 + i
		ItemGrid.Icon(Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(36, 36), Parent = r }), o.item)
		local done = o.left <= 0
		Kit.Label(r, "<b>" .. Items.Name(o.item) .. "</b>   " .. (o.quantity - o.left) .. " / " .. o.quantity .. "   płaci " .. Money.Format(o.rewardCents) .. " za sztukę", {
			RichText = true, TextSize = 14, Size = UDim2.new(1, -220, 1, 0),
		})
		local have = Game.Count(o.item)
		local give = math.min(have, o.left)
		Recipes.Action(r, done and "Wykonane" or (give > 0 and ("Oddaj " .. give) or "Nie masz"), not done and give > 0, function()
			if give > 0 then
				call("CompanyDeliver", { order = i, quantity = give })
			end
		end)
	end

	heading(body, "Wspólnicy", 40)
	for i, m in ipairs(c.members) do
		local r = Kit.Row(body, 34)
		r.LayoutOrder = 40 + i
		local share = c.shares > 0 and math.floor(m.shares / c.shares * 1000 + 0.5) / 10 or 0
		Kit.Label(r, "<b>" .. m.name .. "</b>" .. (m.owner and "  (założyciel)" or "") .. "   " .. m.shares .. " udziałów, " .. share .. "%", {
			RichText = true, TextSize = 14, Size = UDim2.new(1, -150, 1, 0),
		})
		if c.isOwner and not m.owner then
			careful(r, "Usuń", function()
				call("CompanyKick", { member = tonumber(m.id) })
			end, { Size = UDim2.fromOffset(130, 26), BackgroundColor3 = Kit.Colors.Danger })
		end
	end
	if c.isOwner then
		local r = Kit.Row(body, 40)
		r.LayoutOrder = 60
		Recipes.Action(r, "Wypłać dywidendę", c.dividendReady and c.dividendCents > 0, function()
			call("CompanyDividend")
		end).Size = UDim2.fromOffset(180, 30)
		Kit.Label(r, c.dividendReady and (c.dividendPercent .. "% kasy, " .. Money.Format(c.dividendCents) .. ", podzielone według udziałów") or "Dziś już wypłacona. Następna jutro.", {
			TextSize = 13, TextColor3 = Kit.Colors.Muted, Size = UDim2.new(1, -200, 1, 0),
		})
	end

	heading(body, "Ostatnio", 70)
	for i, entry in ipairs(c.log) do
		muted(body, entry.text, 70 + i)
	end
	local r = Kit.Row(body, 40)
	r.LayoutOrder = 100
	r.BackgroundTransparency = 1
	careful(r, c.isOwner and #c.members == 1 and "Zamknij spółkę" or "Odejdź ze spółki", function()
		call("CompanyLeave")
	end, { Size = UDim2.fromOffset(180, 30), BackgroundColor3 = Kit.Colors.Danger })
	Kit.Label(r, "Udziały sprzedasz spółce przy odejściu.", { TextSize = 13, TextColor3 = Kit.Colors.Muted, Size = UDim2.new(1, -200, 1, 0) })
end

function Company.Open(screen)
	local reply = Game.Call("CompanyGet")
	if reply == nil then
		return nil
	end
	local window, body = Kit.Window(screen, "Spółka", 720, 640)
	local render
	local function call(name, payload)
		local r = Game.Call(name, payload)
		if r then
			reply = r
			if window.Parent then
				render()
			end
		end
	end
	render = function()
		Kit.Clear(body)
		if reply.serverTime then
			Game.SyncTime(reply.serverTime)
		end
		if reply.company then
			inside(body, reply.company, reply.serverTime, call)
		else
			outside(body, reply, call)
		end
	end
	render()
	return window
end

return Company

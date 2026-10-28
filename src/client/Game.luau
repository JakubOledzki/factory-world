-- The client's view of the player: balance and inventory pushed by the server, requests to the
-- server, and the Polish text of every error code.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Game = {}

Game.BalanceCents = 0
Game.Inventory = {}
-- The inventory window's tiles: item ids, "" for an empty tile (server Inventory.Slots).
Game.Slots = {}
Game.Changed = Instance.new("BindableEvent")
Game.Toast = Instance.new("BindableEvent")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

Game.Errors = {
	bad_payload = "Nieprawidłowe dane.",
	not_loaded = "Postęp jeszcze się wczytuje.",
	too_fast = "Za szybko, poczekaj chwilę.",
	server_error = "Błąd serwera. Spróbuj ponownie.",
	too_far = "Podejdź bliżej.",
	not_owner = "To nie jest twoje.",
	not_sold = "Handlarz tego nie sprzedaje.",
	not_bought = "Handlarz tego nie kupuje.",
	not_enough_money = "Za mało pieniędzy.",
	not_enough_items = "Za mało przedmiotów.",
	mine_empty = "Kopalnia jest pusta.",
	furnace_full = "Piec jest pełny.",
	furnace_busy = "W piecu topi się inna ruda. Najpierw ją wyjmij.",
	not_smeltable = "Tego nie da się włożyć do pieca.",
	furnace_not_empty = "Najpierw opróżnij piec.",
	queue_full = "Kolejka stołu jest pełna.",
	unknown_recipe = "Nieznany przepis.",
	not_buildable = "Tego nie da się postawić na siatce.",
	outside_grid = "Stawiaj tylko na betonowej siatce na swojej działce.",
	tile_taken = "To miejsce jest zajęte.",
	tile_blocked = "Tu stoi kopalnia.",
	cut_tree = "Drzewo zetnij siekierą (przytrzymaj E).",
	chest_full = "Skrzynia jest pełna.",
	chest_empty = "Tego nie ma w skrzyni.",
	not_researched = "Najpierw to zbadaj (przycisk Badania).",
	research_done = "To już zbadane albo właśnie się bada.",
	research_busy = "Badasz już coś innego. Poczekaj, aż skończysz.",
	research_locked = "Najpierw zbadaj to, czego wymaga.",
	bad_recipe = "Ta maszyna tego nie robi.",
	machine_full = "Maszyna jest pełna.",
	machine_wrong_item = "Ta maszyna nie przyjmie tego przy tym przepisie.",
	no_recipe = "Najpierw wybierz, co maszyna ma robić.",
	not_fuel = "Generator pali tylko węgiel, drewno i pellet.",
	generator_busy = "W generatorze jest inne paliwo. Najpierw je wyjmij.",
	generator_full = "Generator jest pełny.",
	generator_empty = "W generatorze nie ma paliwa do wyjęcia.",
	market_busy = "Poprzednia transakcja na rynku jeszcze trwa.",
	market_unavailable = "Rynek chwilowo nie odpowiada. Nic nie przepadło, spróbuj za chwilę.",
	no_offer = "Tej oferty już nie ma.",
	own_offer = "To twoja własna oferta.",
	price_changed = "Cena tej oferty się zmieniła.",
	not_enough_offered = "W tej ofercie zostało mniej, niż chcesz.",
	too_many_offers = "Masz już najwięcej otwartych ofert. Anuluj którąś w „Moje oferty”.",
	nothing_owed = "Nic na ciebie nie czeka.",
	duplicate = "Ta transakcja już się odbyła.",
}

function Game.ErrorText(code)
	return Game.Errors[code] or ("Błąd: " .. tostring(code))
end

-- Calls the server; returns the reply, or nil after showing the error.
function Game.Call(name, payload)
	local remote = remotes:WaitForChild(name, 10)
	if remote == nil then
		Game.Toast:Fire(Game.ErrorText("server_error"))
		return nil
	end
	local ok, reply = pcall(function()
		return remote:InvokeServer(payload)
	end)
	if not ok or type(reply) ~= "table" then
		Game.Toast:Fire(Game.ErrorText("server_error"))
		return nil
	end
	if not reply.ok then
		Game.Toast:Fire(Game.ErrorText(reply.code))
		return nil
	end
	return reply
end

function Game.Count(item)
	return Game.Inventory[item] or 0
end

-- Server time now, from the time a reply carried and when it came.
local offset = 0
function Game.SyncTime(serverTime)
	offset = serverTime - Workspace:GetServerTimeNow()
end

function Game.Now()
	return Workspace:GetServerTimeNow() + offset
end

remotes:WaitForChild("State").OnClientEvent:Connect(function(state)
	Game.BalanceCents = state.balanceCents
	Game.Inventory = state.inventory or {}
	Game.Slots = state.slots or {}
	Game.Changed:Fire()
end)

remotes:WaitForChild("Toast").OnClientEvent:Connect(function(message)
	Game.Toast:Fire(message.text)
end)

return Game

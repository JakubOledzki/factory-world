-- The first steps of a new player (TutorialRules on main), one task after another: from the mine and
-- the trees, through the furnace and the first belts, to research, an order and the first harvest.
-- Each task pays its reward when done; some also give what the next one needs. The server tells the
-- tutorial what the player did (Note), so the services only report events and know nothing of tasks.
--
-- Events: "mine" (one load from a mine), "chop" (a tree cut), "sell" (anything sold to the merchant),
-- "craft" (a workbench order, item = what), "place" (put on the grid, item = what), "smelt" (ingots
-- taken from a furnace, amount = how many), "research" (a technology started), "contract" (an order
-- finished), "sow" (a field sown) and "reap" (a field reaped).
local Items = require(script.Parent.Items)

local Tutorial = {}

-- Ids are saved with the player: never rename one.
Tutorial.Steps = {
	{
		id = "mine", title = "Górnik", goal = 3, event = "mine", rewardCents = 2000,
		text = "Wykop urobek z kopalni na swojej działce 3 razy.",
		hint = "Podejdź do kopalni i przytrzymaj E. Kilof masz w ekwipunku.",
	},
	{
		id = "chop", title = "Drwal", goal = 3, event = "chop", rewardCents = 2000,
		text = "Zetnij 3 drzewa na działce.",
		hint = "Podejdź do drzewa i przytrzymaj E. Czasem wypada sadzonka.",
	},
	{
		id = "sell", title = "Pierwszy zarobek", goal = 1, event = "sell", rewardCents = 3000,
		text = "Sprzedaj coś handlarzowi na placu.",
		hint = "Handlarz stoi na placu pośrodku. E otwiera jego okno.",
	},
	{
		id = "craft_furnace", title = "Piec", goal = 1, event = "craft", item = Items.Furnace, rewardCents = 3000,
		rewardItems = { { Items.Coal, 5 } },
		text = "Zamów piec przy stole warsztatowym.",
		hint = "Stół stoi na placu obok fontanny. Piec kosztuje 20 kamieni.",
	},
	{
		id = "place_furnace", title = "Na siatce", goal = 1, event = "place", item = Items.Furnace, rewardCents = 2000,
		text = "Postaw piec na swojej działce.",
		hint = "B włącza budowanie: wybierz piec na pasku i kliknij wolne pole.",
	},
	{
		id = "smelt", title = "Hutnik", goal = 5, event = "smelt", rewardCents = 5000,
		rewardItems = { { Items.IronIngot, 4 } },
		text = "Wytop i wyjmij z pieca 5 sztabek.",
		hint = "E przy piecu: włóż rudę i węgiel (5 dostałeś w nagrodę), a gotowe sztabki kliknij.",
	},
	{
		id = "place_belts", title = "Taśmociąg", goal = 3, event = "place", item = Items.Belt, rewardCents = 3000,
		rewardItems = { { Items.Inserter, 1 }, { Items.WoodenChest, 1 } },
		text = "Postaw 3 taśmociągi na działce.",
		hint = "Taśmociągi zrobisz na stole (2 sztabki żelaza i drewno na 4) albo kupisz u handlarza.",
	},
	{
		id = "place_inserter", title = "Podajnik", goal = 1, event = "place", item = Items.Inserter, rewardCents = 5000,
		text = "Postaw podajnik między skrzynią a taśmą.",
		hint = "Podajnik i skrzynię dostałeś w nagrodę. Podajnik bierze z pola za sobą i kładzie przed sobą (R obraca).",
	},
	{
		id = "research", title = "Badania", goal = 1, event = "research", rewardCents = 5000,
		text = "Zacznij dowolne badanie.",
		hint = "T otwiera badania. Gospodarka leśna odblokuje tartak.",
	},
	{
		id = "contract", title = "Zlecenie", goal = 1, event = "contract", rewardCents = 10000,
		rewardItems = { { Items.Hoe, 1 } },
		text = "Wykonaj jedno zlecenie firmy.",
		hint = "J albo tablica zleceń na placu. Towar oddajesz z ekwipunku, także po trochu.",
	},
	{
		id = "sow", title = "Rolnik", goal = 1, event = "sow", rewardCents = 3000,
		text = "Zaorz pole motyką i coś zasiej.",
		hint = "Motykę dostałeś w nagrodę: wybierz ją przy budowaniu (B) i kliknij trawę. E na polu otwiera siew.",
	},
	{
		id = "reap", title = "Żniwa", goal = 1, event = "reap", rewardCents = 10000,
		text = "Zbierz dojrzałe plony.",
		hint = "Pszenica rośnie 5 minut. Dojrzałe plony zbierasz, przytrzymując E przy polu.",
	},
}

function Tutorial.New()
	return { step = 1, progress = 0 }
end

-- Counts what the player did. Returns the step it finished (its reward is the caller's to give), or nil.
function Tutorial.Note(state, event, item, amount)
	local step = Tutorial.Steps[state.step]
	if step == nil or step.event ~= event or (step.item ~= nil and step.item ~= item) then
		return nil
	end
	state.progress = state.progress + (amount or 1)
	if state.progress < step.goal then
		return nil
	end
	state.step = state.step + 1
	state.progress = 0
	return step
end

-- Ends the tutorial at once (the player chose to skip it).
function Tutorial.Skip(state)
	state.step = #Tutorial.Steps + 1
	state.progress = 0
end

-- What the client shows: the task at hand, or nil when the tutorial is over.
function Tutorial.View(state)
	local step = state and Tutorial.Steps[state.step]
	if step == nil then
		return nil
	end
	return {
		number = state.step,
		count = #Tutorial.Steps,
		title = step.title,
		text = step.text,
		hint = step.hint,
		progress = state.progress,
		goal = step.goal,
		rewardCents = step.rewardCents,
		rewardItems = step.rewardItems,
	}
end

return Tutorial

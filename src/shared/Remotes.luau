-- Names of the RemoteFunctions the server creates in ReplicatedStorage.Remotes. The client only
-- sends intentions; every reply is a table { ok = true, ... } or { ok = false, code = "..." }.
return {
	-- Server -> client pushes (RemoteEvents).
	State = "State", -- { balanceCents, inventory = { [item] = quantity }, plot = index }
	Toast = "Toast", -- { text }

	-- Client -> server requests (RemoteFunctions).
	Prices = "Prices",
	Buy = "Buy", -- { item, quantity }
	Sell = "Sell", -- { item, quantity }
	FurnaceGet = "FurnaceGet", -- { id }
	FurnaceLoad = "FurnaceLoad", -- { id, item, quantity }
	FurnaceTake = "FurnaceTake", -- { id, what }
	FurnacePlace = "FurnacePlace", -- { slot }
	FurnacePickup = "FurnacePickup", -- { id }
	WorkshopGet = "WorkshopGet",
	WorkshopOrder = "WorkshopOrder", -- { recipe }
	GridPlace = "GridPlace", -- { item, x, z, rot }
	GridPickup = "GridPickup", -- { id }
	GridRotate = "GridRotate", -- { id, rot }
	ChestGet = "ChestGet", -- { id }
	ChestPut = "ChestPut", -- { id, item, quantity }
	ChestTake = "ChestTake", -- { id, item, quantity }
	MachineGet = "MachineGet", -- { id }
	MachineRecipe = "MachineRecipe", -- { id, recipe }
	MachineLoad = "MachineLoad", -- { id, item, quantity }
	MachineTake = "MachineTake", -- { id, what }
	ResearchGet = "ResearchGet",
	ResearchStart = "ResearchStart", -- { id }
	InventoryMove = "InventoryMove", -- { item, slot }
	MarketGet = "MarketGet",
	MarketBoard = "MarketBoard", -- { item }
	MarketMine = "MarketMine",
	MarketList = "MarketList", -- { item, quantity, priceCents }
	MarketOrder = "MarketOrder", -- { item, quantity, priceCents }
	MarketBuy = "MarketBuy", -- { item, id, quantity, priceCents }
	MarketFill = "MarketFill", -- { item, id, quantity, priceCents }
	MarketCancel = "MarketCancel", -- { item, offerKind, id }
}

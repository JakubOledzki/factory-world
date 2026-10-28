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
}

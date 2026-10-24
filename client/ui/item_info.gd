class_name ItemInfo
## What the game says about its items: the categories the market and the workbench sort them
## into, and for each item its name, a short description and where it comes from (which
## machine makes it and of what), shown when the mouse rests on an item with Ctrl held.

## Categories in the order they are shown: name, items, and id patterns for the rest, so a new
## ore, tool, belt or decoration finds its place on its own. Listed items win over patterns.
const CATEGORIES := [
	["Rośliny i nasiona", ["sapling", "wheat", "carrot", "cabbage", "corn", "potato", "sunflower"], []],
	["Drewno i kamień", ["wood", "stone", "sand"], []],
	["Rudy i węgiel", ["coal"], ["*_ore"]],
	["Sztabki i materiały", ["nails"], ["*_ingot"]],
	["Jedzenie", ["flour", "corn_flour", "sunflower_oil", "sauerkraut", "bread", "corn_bread",
			"carrot_cake", "fries", "vegetable_soup", "bigos"], []],
	["Maszyny", ["furniture_workbench", "furniture_anvil", "furniture_furnace", "furniture_brick_furnace", "furniture_blast_furnace",
			"furniture_sorting_machine", "furniture_mill",
			"furniture_oil_press", "furniture_pickling_barrel", "furniture_bakery", "furniture_kitchen"], []],
	["Logistyka i magazyny", [], ["logistics_*", "storage_*"]],
	["Energia", [], ["power_*"]],
	["Narzędzia", [], ["tool_*"]],
	["Wyposażenie", [], ["furniture_*"]],
	["Odpady i złom", ["trash"], ["waste_*"]],
	["Inne", [], ["*"]],
]

## Every item: [name, what it is for, where it comes from]. Recipes follow the server's
## (Workshop, Smelting and Processing); change them together.
const ITEMS := {
	"trash": ["Śmieci", "Worek mieszanych odpadów. Posegreguj go przy koszu w garażu, a odzyskasz surowce do sprzedania.",
			"Kupisz u handlarza na rynku."],
	"waste_paper": ["Makulatura", "Stary papier i karton z segregacji.", "Segregacja śmieci przy koszu albo w automatycznej sortowni."],
	"waste_aluminium": ["Złom aluminium", "Puszki i blaszki z segregacji; handlarz płaci za nie nieźle.",
			"Segregacja śmieci przy koszu albo w automatycznej sortowni."],
	"waste_copper": ["Złom miedzi", "Najcenniejsze, co da się wyciągnąć ze śmieci.", "Segregacja śmieci przy koszu albo w automatycznej sortowni."],
	"waste_plastic": ["Plastik z odzysku", "Butelki i folie z segregacji.", "Segregacja śmieci przy koszu albo w automatycznej sortowni."],
	"waste_glass": ["Stłuczka szklana", "Szkło z segregacji.", "Segregacja śmieci przy koszu albo w automatycznej sortowni."],
	"furniture_trash_bin": ["Kosz na śmieci", "Stoi w garażu; przy nim ręcznie segregujesz śmieci.", "Jest w garażu od początku."],
	"furniture_workbench": ["Stół warsztatowy", "Wytwarza maszyny, gwoździe, taśmociągi i skrzynie. Postawisz go w garażu albo na działce.",
			"Stół warsztatowy: 20 × drewno + 5 × gwoździe (30 s). Kupisz też u handlarza."],
	"furniture_anvil": ["Kowadło", "Wykuwa narzędzia: siekierę, łopatę, kilof i motykę. Postawisz je w garażu albo na działce.",
			"Stół warsztatowy: 15 × sztabka żelaza + 10 × kamień (60 s). Kupisz też u handlarza za 500 $."],
	"furniture_shelf": ["Regał", "Wyposażenie garażu.", "Jest w garażu od początku."],
	"furniture_barrel_blue": ["Niebieska beczka", "Wyposażenie garażu.", "Jest w garażu od początku."],
	"furniture_barrel_red": ["Czerwona beczka", "Wyposażenie garażu.", "Jest w garażu od początku."],
	"furniture_tyres": ["Opony", "Wyposażenie garażu.", "Są w garażu od początku."],
	"furniture_pallet": ["Paleta", "Wyposażenie garażu.", "Jest w garażu od początku."],
	"furniture_gas_cylinder": ["Butla gazowa", "Wyposażenie garażu.", "Jest w garażu od początku."],
	"furniture_sorting_machine": ["Automatyczna sortownia", "Segreguje śmieci sama, także gdy cię nie ma.",
			"Kupisz u handlarza na rynku."],
	"furniture_furnace": ["Piec kamienny", "Przetapia rudy na sztabki; pali węgiel.",
			"Stół warsztatowy: 20 × kamień (45 s)."],
	"furniture_brick_furnace": ["Piec ceglany",
			"Drugi poziom pieca: przetapia 2 razy szybciej i mieści po 100 rudy i węgla. Stawiasz go tylko na działce.",
			"Stół warsztatowy: 1 × piec kamienny + 40 × kamień + 20 × piasek + 10 × sztabka żelaza (60 s)."],
	"furniture_blast_furnace": ["Piec hutniczy",
			"Trzeci poziom pieca: przetapia 4 razy szybciej, mieści po 200 rudy i węgla, a węgiel starcza mu na 8 przetopień. Tylko na działce.",
			"Stół warsztatowy: 1 × piec ceglany + 60 × kamień + 40 × sztabka żelaza + 20 × sztabka miedzi (90 s)."],
	"tool_axe": ["Siekiera", "Do ścinania drzew na działce.", "Dostajesz ją z działką leśną. Kupisz u handlarza za 100 $ albo wykujesz w kowadle: 3 × sztabka żelaza + 2 × drewno (20 s)."],
	"tool_shovel": ["Łopata", "Do kopania piasku z wydm.", "Dostajesz ją z działką pustynną. Kupisz u handlarza za 100 $ albo wykujesz w kowadle: 2 × sztabka żelaza + 2 × drewno (20 s)."],
	"tool_pickaxe": ["Kilof", "Do rozbijania skał i pracy w kopalni.", "Dostajesz go z działką w górach. Kupisz u handlarza za 100 $ albo wykujesz w kowadle: 3 × sztabka żelaza + 2 × drewno (20 s)."],
	"tool_hoe": ["Motyka", "Do orania pola pod uprawy.", "Dostajesz ją z działką rolną. Kupisz u handlarza za 100 $ albo wykujesz w kowadle: 2 × sztabka żelaza + 2 × drewno (20 s)."],
	"tool_chainsaw": ["Piła spalinowa", "Ścina drzewa o 70% szybciej niż siekiera.", "Kupisz u handlarza za 500 $."],
	"wood": ["Drewno", "Podstawowy materiał budowlany i opał do maszyn i generatora.", "Ścinanie drzew siekierą albo piłą spalinową na działce."],
	"stone": ["Kamień", "Na piece, młyny i hałdy.", "Rozbijanie skał kilofem i kopalnie w górach."],
	"sand": ["Piasek", "Potrzebny do pieca piekarskiego.", "Kopanie wydm łopatą na pustyni."],
	"coal": ["Węgiel", "Opał do pieca kamiennego i maszyn; jedna bryła starcza na kilka wytopów.",
			"Skały i kopalnie w górach."],
	"iron_ore": ["Ruda żelaza", "Przetop ją w piecu na sztabki żelaza.", "Skały i kopalnie w górach."],
	"copper_ore": ["Ruda miedzi", "Przetop ją w piecu na sztabki miedzi.", "Skały i kopalnie w górach."],
	"tin_ore": ["Ruda cyny", "Przetop ją w piecu na sztabki cyny.", "Kopalnie w górach."],
	"silver_ore": ["Ruda srebra", "Rzadka; przetop ją w piecu na sztabki srebra.", "Kopalnie w górach."],
	"gold_ore": ["Ruda złota", "Bardzo rzadka i droga; przetop ją w piecu na sztabki złota.", "Kopalnie w górach."],
	"iron_ingot": ["Sztabka żelaza", "Najczęstszy materiał do maszyn, gwoździ i taśmociągów.",
			"Piec kamienny: 1 × ruda żelaza (10 s)."],
	"copper_ingot": ["Sztabka miedzi", "Do podajników, rozdzielaczy i kuchni polowej.",
			"Piec kamienny: 1 × ruda miedzi (10 s)."],
	"tin_ingot": ["Sztabka cyny", "Cenny metal na sprzedaż.", "Piec kamienny: 1 × ruda cyny (10 s)."],
	"silver_ingot": ["Sztabka srebra", "Cenny metal na sprzedaż.", "Piec kamienny: 1 × ruda srebra (15 s)."],
	"gold_ingot": ["Sztabka złota", "Najcenniejszy metal w grze.", "Piec kamienny: 1 × ruda złota (20 s)."],
	"nails": ["Gwoździe", "Do stołów, skrzyń, beczek i podajników.",
			"Stół warsztatowy: 1 × sztabka żelaza → 5 szt. (10 s). Kupisz też u handlarza."],
	"sapling": ["Sadzonka drzewa", "Posadź ją na działce, a wyrośnie z niej drzewo.",
			"Często wypada przy ścinaniu drzew; kupisz też u handlarza."],
	"wheat": ["Pszenica", "Zboże na mąkę pszenną.", "Uprawa na polu na działce rolnej (5 min)."],
	"carrot": ["Marchew", "Do ciasta marchewkowego i zupy.", "Uprawa na polu na działce rolnej (7 min)."],
	"cabbage": ["Kapusta", "Do kiszenia i zupy.", "Uprawa na polu na działce rolnej (8 min)."],
	"corn": ["Kukurydza", "Zboże na mąkę kukurydzianą.", "Uprawa na polu na działce rolnej (10 min)."],
	"potato": ["Ziemniaki", "Do frytek, zupy i bigosu.", "Uprawa na polu na działce rolnej (15 min)."],
	"sunflower": ["Słonecznik", "Nasiona na olej.", "Uprawa na polu na działce rolnej (20 min)."],
	"logistics_belt": ["Taśmociąg", "Wozi przedmioty po działce; łącz go w linie i zakręty.",
			"Stół warsztatowy: 2 × sztabka żelaza + 1 × drewno → 4 szt. (10 s)."],
	"logistics_fast_belt": ["Szybki taśmociąg", "Taśmociąg drugiego poziomu: wozi przedmioty 2 razy szybciej.",
			"Stół warsztatowy: 2 × taśmociąg + 3 × sztabka żelaza + 1 × sztabka miedzi → 2 szt. (15 s)."],
	"logistics_express_belt": ["Ekspresowy taśmociąg", "Taśmociąg trzeciego poziomu: wozi przedmioty 3 razy szybciej.",
			"Stół warsztatowy: 2 × szybki taśmociąg + 4 × sztabka żelaza + 1 × sztabka cyny → 2 szt. (20 s)."],
	"logistics_inserter": ["Podajnik", "Przekłada przedmioty między taśmą, maszyną i skrzynią. Działa na prąd (5 kW).",
			"Stół warsztatowy: 2 × sztabka żelaza + 1 × sztabka miedzi + 5 × gwoździe (15 s)."],
	"logistics_fast_inserter": ["Szybki podajnik", "Podajnik drugiego poziomu: obraca ramię 2 razy szybciej. Działa na prąd (8 kW).",
			"Stół warsztatowy: 1 × podajnik + 2 × sztabka żelaza + 2 × sztabka miedzi (20 s)."],
	"logistics_express_inserter": ["Ekspresowy podajnik", "Podajnik trzeciego poziomu: obraca ramię 4 razy szybciej. Działa na prąd (12 kW).",
			"Stół warsztatowy: 1 × szybki podajnik + 3 × sztabka miedzi + 1 × sztabka srebra (25 s)."],
	"logistics_splitter": ["Rozdzielacz", "Dzieli taśmę na dwie i może sortować przedmioty.",
			"Stół warsztatowy: 2 × taśmociąg + 4 × sztabka żelaza + 2 × sztabka miedzi (20 s)."],
	"storage_wooden_chest": ["Skrzynia drewniana", "Mieści przedmioty każdego rodzaju.",
			"Stół warsztatowy: 10 × drewno + 5 × gwoździe (10 s)."],
	"storage_iron_chest": ["Skrzynia żelazna", "Większa skrzynia na wszystko.", "Stół warsztatowy: 8 × sztabka żelaza (20 s)."],
	"storage_wood_pile": ["Stos drewna", "Magazyn tylko na drewno.", "Stół warsztatowy: 4 × drewno (5 s)."],
	"storage_heap": ["Hałda", "Magazyn na kamień, piasek, węgiel albo rudę, jeden rodzaj naraz.",
			"Stół warsztatowy: 10 × kamień + 4 × drewno (10 s)."],
	"storage_grain_silo": ["Silos zbożowy", "Magazyn na pszenicę, kukurydzę albo słonecznik, jeden rodzaj naraz.",
			"Stół warsztatowy: 10 × sztabka żelaza + 20 × kamień + 10 × gwoździe (40 s)."],
	"furniture_mill": ["Młyn", "Miele pszenicę i kukurydzę na mąkę. Działa na prąd (30 kW).",
			"Stół warsztatowy: 30 × kamień + 10 × drewno + 2 × sztabka żelaza (60 s)."],
	"furniture_oil_press": ["Tłocznia oleju", "Wytłacza olej ze słonecznika. Działa na prąd (30 kW).",
			"Stół warsztatowy: 15 × drewno + 4 × sztabka żelaza + 10 × gwoździe (60 s)."],
	"furniture_pickling_barrel": ["Beczka do kiszenia", "Kisi kapustę.",
			"Stół warsztatowy: 12 × drewno + 5 × gwoździe (30 s)."],
	"furniture_bakery": ["Piec piekarski", "Piecze chleb i ciasto; pali węgiel albo drewno.",
			"Stół warsztatowy: 40 × kamień + 3 × sztabka żelaza + 10 × piasek (90 s)."],
	"furniture_kitchen": ["Kuchnia polowa", "Gotuje frytki, zupę i bigos; pali węgiel albo drewno.",
			"Stół warsztatowy: 20 × kamień + 5 × sztabka żelaza + 2 × sztabka miedzi (90 s)."],
	"power_generator": ["Generator parowy", "Pali drewno albo węgiel i daje do 100 kW prądu maszynom, do których sięgają słupy.",
			"Stół warsztatowy: 10 × kamień + 8 × sztabka żelaza + 4 × sztabka miedzi (60 s). Kupisz też u handlarza."],
	"power_pole": ["Słup energetyczny", "Zasila maszyny do 2 pól od siebie; słupy do 7 pól od siebie łączą się przewodami.",
			"Stół warsztatowy: 2 × drewno + 1 × sztabka miedzi → 2 szt. (5 s). Kupisz też u handlarza."],
	"flour": ["Mąka pszenna", "Do chleba i ciasta marchewkowego.", "Młyn: 2 × pszenica (6 s)."],
	"corn_flour": ["Mąka kukurydziana", "Do chleba kukurydzianego.", "Młyn: 2 × kukurydza (6 s)."],
	"sunflower_oil": ["Olej słonecznikowy", "Do ciasta i frytek.", "Tłocznia oleju: 2 × słonecznik (10 s)."],
	"sauerkraut": ["Kapusta kiszona", "Do bigosu.", "Beczka do kiszenia: 2 × kapusta → 2 szt. (60 s)."],
	"bread": ["Chleb", "Jedzenie na sprzedaż.", "Piec piekarski: 2 × mąka pszenna (20 s)."],
	"corn_bread": ["Chleb kukurydziany", "Jedzenie na sprzedaż.", "Piec piekarski: 2 × mąka kukurydziana (20 s)."],
	"carrot_cake": ["Ciasto marchewkowe", "Droższe jedzenie na sprzedaż.",
			"Piec piekarski: 2 × mąka pszenna + 3 × marchew + 1 × olej słonecznikowy (30 s)."],
	"fries": ["Frytki", "Jedzenie na sprzedaż.", "Kuchnia polowa: 3 × ziemniaki + 1 × olej słonecznikowy → 2 szt. (15 s)."],
	"vegetable_soup": ["Zupa jarzynowa", "Jedzenie na sprzedaż.",
			"Kuchnia polowa: 2 × marchew + 2 × ziemniaki + 1 × kapusta (20 s)."],
	"bigos": ["Bigos", "Jedzenie na sprzedaż.", "Kuchnia polowa: 2 × kapusta kiszona + 2 × ziemniaki → 2 szt. (25 s)."],
}


## The index in CATEGORIES of the category an item belongs to.
static func category_of(item: String) -> int:
	for i in CATEGORIES.size():
		if item in CATEGORIES[i][1]:
			return i
	for i in CATEGORIES.size():
		for pattern: String in CATEGORIES[i][2]:
			if item.match(pattern):
				return i
	return CATEGORIES.size() - 1


static func name_of(item: String) -> String:
	return ITEMS[item][0] if ITEMS.has(item) else item


static func description(item: String) -> String:
	return ITEMS[item][1] if ITEMS.has(item) else ""


static func source(item: String) -> String:
	return ITEMS[item][2] if ITEMS.has(item) else ""

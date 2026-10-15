class_name CampaignShop
extends RefCounted
## Needles' pop-up stall (CAMPAIGN.md §7.5): 3 supplements (rarity roll OTC 50 / Rx 35 / BM 13 /
## Banned 2; a 4th slot in Act 3), 1 technique of the player's fighter they do not own, 1 service
## (Rub-down, Antidote, Reroll stock once, or Sell at 50%). Price modifiers: Dose 9+ x1.3,
## Sponsor Patch (+1 item, -10%), Bargain Bin (+1 Black Market item), Juice Bar Tab (-8%/level),
## Needles' Connection (always one Black Market item), Glandco coupon (-20% next visit).
## Stock is generated per player from the node's stream (rerolls use the next key).


static func stock(ctrl: RunController, pid: String, reroll := 0) -> Dictionary:
	var cat: CampaignCatalog = ctrl.catalog
	var state: Dictionary = ctrl.state
	var p: Dictionary = RunState.player(state, pid)
	var rr: Dictionary = ctrl.rules_for(pid)
	var shop: Dictionary = cat.rules.get("shop", {})
	var node_id := str(state.get("position", ""))
	var key := "node/%s/shop/%s/%d" % [node_id, pid, reroll]
	var n := int(shop.get("supplement_slots", 3)) + int(rr.get("shop_extra_items", 0.0))
	if int(state.get("act", 1)) >= 3:
		n += int(shop.get("act3_extra_slot", 1))
	var sups := RewardRoller.supplement_offer(cat, state, p, key, {"source": "shop", "n": n})
	var extra_bm := int(rr.get("shop_extra_black_market", 0.0))
	var has_bm := false
	for s in sups:
		if str(cat.supplements[s].get("rarity", "")) == "black_market":
			has_bm = true
	if float(rr.get("shop_always_black_market", 0.0)) > 0.0 and not has_bm:
		extra_bm += 1
	if extra_bm > 0:
		var bm := RewardRoller.supplement_offer(cat, state, p, key + "/bm", {"source": "shop", "n": extra_bm, "rarity": "black_market", "exclude": sups})
		sups.append_array(bm)
	var items := []
	var mult := price_mult(ctrl, pid)
	for i in sups.size():
		var sid := str(sups[i])
		items.append({"slot": "s%d" % i, "id": sid, "kind": "supplement", "price": int(round(cat.price_of(sid) * mult)), "sold": false})
	var tech := RewardRoller.technique_offer(cat, state, p, key + "/tech", int(shop.get("technique_slots", 1)))
	for j in tech.size():
		var tid := str(tech[j])
		items.append({"slot": "t%d" % j, "id": tid, "kind": "technique", "price": int(round(cat.price_of(tid) * mult)), "sold": false})
	var pool: Array = shop.get("service_pool", ["rub_down", "antidote", "reroll", "sell"])
	var srng := RunRng.stream(int(state["seed"]), "node/%s/shop/%s/service" % [node_id, pid])
	var service := str(pool[srng.range_i(0, pool.size() - 1)]) if not pool.is_empty() else "sell"
	var prices: Dictionary = shop.get("services", {})
	return {"items": items, "service": service, "service_price": int(round(float(prices.get(service, 0)) * mult)),
		"rerolls": reroll, "reroll_used": reroll > 0, "done": false, "coupon": float(p.get("coupon", 0.0))}


static func price_mult(ctrl: RunController, pid: String) -> float:
	var rr: Dictionary = ctrl.rules_for(pid)
	var p: Dictionary = RunState.player(ctrl.state, pid)
	return maxf(0.1, float(rr.get("shop_price_mult", 1.0)) * (1.0 - float(p.get("coupon", 0.0))))


## Base price of an owned supplement (for selling).
static func sell_value(ctrl: RunController, id: String) -> int:
	var frac := float(ctrl.catalog.rules.get("shop", {}).get("sell_fraction", 0.5))
	return int(round(ctrl.catalog.price_of(id) * frac))

extends RefCounted

## THE KITCHEN'S NOUNS, AND WHAT BECOMES WHAT.
##
## Adapted from `KaganAyten/RestaurantGame3DUnity` (MIT) -- see
## `docs/THIRD_PARTY_NOTICES.md`. The idea worth taking from it is that **an item
## is a type, and preparing something is a type-to-type mapping**. That one
## decision is what lets a station, a hand and a recipe all talk about the same
## thing without any of them knowing what a mesh is.
##
## The reference does it as a C# `enum`, which means adding an ingredient is a
## code change. Here it is DATA, for the same reason every lesson in this project
## is data: `assets_models` requires that every object is "the shape of a word",
## so an item carries its English word, its Thai, and the colour it is drawn in.
## A new ingredient is a row.
##
## PURE. No `Node3D`, no mesh, no scene -- `test_architecture_guard.gd` draws that
## line and this file stays on the right side of it. What an item LOOKS like is
## `kitchen_prop.gd`'s problem; what an item IS, is this file's.

const Palette := preload("res://scripts/ui/palette.gd")

## Nothing in the hand, nothing on the station. Named rather than `""` so a
## caller reads as "the hand is empty" instead of "the hand is falsy".
const NONE: String = ""

## Every item the kitchen knows, keyed by id.
##
##   `word`      the English being taught -- this is a language game first
##   `thai`      the hint, per the Thai-hints setting
##   `color`     what the prop is drawn in, from the locked palette
##   `shape`     how `kitchen_prop.gd` builds it: box | ball | cup | bowl | flat
##   `size`      metres, so a child can tell a banana from a bowl at a glance
##   `held`      true if Aliz can carry it (a station is not carryable)
##   `model`     optional: a prop id in `assets/models/meshy-props/manifest.json`
##               (`prop_registry.gd`). When it is named AND its GLB imports,
##               `kitchen_view.gd` stands that mesh in for the drawn form;
##               otherwise the drawn form stays. A string, not a mesh -- this
##               file stays pure. `modelSize` is the longest axis in metres the
##               prop is drawn at, so the swap keeps the drawn item's scale.
const ITEMS: Dictionary = {
	"bottle": {
		"word": "bottle", "thai": "ขวดนม", "color": Palette.CREAM,
		"shape": "cup", "size": 0.11, "held": true,
	},
	"bottleOfMilk": {
		"word": "milk", "thai": "นม", "color": Color(1.0, 0.988, 0.949),
		"shape": "cup", "size": 0.11, "held": true,
	},
	"banana": {
		"word": "banana", "thai": "กล้วย", "color": Color(0.98, 0.85, 0.42),
		"shape": "flat", "size": 0.14, "held": true,
		"model": "banana", "modelSize": 0.26,
	},
	"apple": {
		"word": "apple", "thai": "แอปเปิ้ล", "color": Palette.SOFT_PINK,
		"shape": "ball", "size": 0.09, "held": true,
		"model": "apple", "modelSize": 0.20,
	},
	"bowl": {
		"word": "bowl", "thai": "ชาม", "color": Palette.MINT,
		"shape": "bowl", "size": 0.15, "held": true,
	},
	"spoon": {
		"word": "spoon", "thai": "ช้อน", "color": Palette.DUSTY_BLUE,
		"shape": "flat", "size": 0.13, "held": true,
	},
	## The two prepared foods. Their ids say what they ARE, not how they were
	## made, so a second route to the same dish needs no new id.
	"mashedBanana": {
		"word": "mashed banana", "thai": "กล้วยบด", "color": Color(0.99, 0.90, 0.60),
		"shape": "bowl", "size": 0.15, "held": true,
	},
	"fruitBowl": {
		"word": "fruit bowl", "thai": "ชามผลไม้", "color": Color(0.99, 0.78, 0.62),
		"shape": "bowl", "size": 0.16, "held": true,
	},
}


static func exists(item_id: String) -> bool:
	return ITEMS.has(item_id)


static func data(item_id: String) -> Dictionary:
	return (ITEMS.get(item_id, {}) as Dictionary).duplicate(true)


## The English word an item teaches. Empty for `NONE`, so a caller can say
## "carrying the %s" without a special case for empty hands.
static func word_for(item_id: String) -> String:
	return String(data(item_id).get("word", ""))


static func thai_for(item_id: String) -> String:
	return String(data(item_id).get("thai", ""))


static func color_for(item_id: String) -> Color:
	var value: Variant = data(item_id).get("color", Palette.CREAM)
	return value if value is Color else Palette.CREAM


static func shape_for(item_id: String) -> String:
	return String(data(item_id).get("shape", "box"))


static func size_for(item_id: String) -> float:
	return float(data(item_id).get("size", 0.10))


## The Meshy prop that stands in for this item's drawn form, or "" for none.
static func model_for(item_id: String) -> String:
	return String(data(item_id).get("model", "")).strip_edges()


## Longest axis, in metres, the prop is drawn at. 0 lets the prop keep the
## manifest's own size.
static func model_size_for(item_id: String) -> float:
	return float(data(item_id).get("modelSize", 0.0))


## Can Aliz pick this up and walk with it?
static func is_carryable(item_id: String) -> bool:
	return bool(data(item_id).get("held", false))


static func ids() -> Array:
	var out: Array = ITEMS.keys()
	out.sort()
	return out

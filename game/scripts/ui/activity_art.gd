extends RefCounted

## Original vector activity pictures + approved 3D bottle render. No concept
## art and no new generation. Readable at the same 96px optical size.
const PATHS: Dictionary = {
	"bottle": "res://assets/ui/icons/pictures/care_bottle.png",
	"bowl": "res://assets/ui/icons/pictures/care_bowl.svg",
	"bath": "res://assets/ui/icons/pictures/care_bath.svg",
	"moon": "res://assets/ui/icons/pictures/care_bedtime.svg",
	"tidy": "res://assets/ui/icons/pictures/care_tidy.svg",
	"brush": "res://assets/ui/icons/pictures/care_brush.svg",
	"sun": "res://assets/ui/icons/pictures/care_sun.svg",
	"shirt": "res://assets/ui/icons/pictures/dress.png",
	"ball": "res://assets/ui/icons/pictures/toys.png",
}

static func texture_for(kind: String) -> Texture2D:
	var path: String = String(PATHS.get(kind, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null

extends SceneTree
## Procedural app-icon generator for Little Buddy.
##
## The icon is authored here, in this file, as an SVG document built from plain
## geometry (rects, circles, cubic paths, gradients). Nothing is downloaded,
## traced or derived from third-party artwork, and the script makes no network
## calls of any kind -- so the shipped app icon carries zero licence surface.
##
## Usage (writes into the project's res://):
##   godot --headless --path game --script res://../tools/generate_icon.gd
##
## Usage (explicit absolute output directory):
##   godot --headless --path game --script res://../tools/generate_icon.gd -- \
##       --out /abs/path/to/game
##
## Outputs:
##   <out>/icon.svg                      -- editor/project icon (vector source)
##   <out>/icon_1024.png                 -- 1024x1024 opaque RGB8 iOS master
##   <out>/assets/icon/preview/icon_<n>.png  -- downsampled readability checks
##
## Design rules (these are "does it survive the home screen" rules):
##   * One hero object (a baby bottle), dead-centre, no text, no tiny details.
##   * Hero stays inside a safe circle of ~80% width, because iOS masks the
##     icon to a superellipse and eats the corners.
##   * Value contrast carries the silhouette: a light bottle on a mid-tone
##     dusty-blue field. No outlines and no thin strokes -- both vanish at 60px.
##   * Depth comes from soft gradients and one glass highlight, not from
##     skeuomorphic bevels or hard drop shadows.
##   * Fully opaque. iOS rejects app icons with an alpha channel.
##   * Palette is the in-game nursery palette: warm cream, dusty blue, soft
##     pink, peach.

const MASTER_SIZE: int = 1024

## Small sizes rendered for eyeballing readability. 60/120/180 are the iPhone
## home-screen sizes, 76 is the iPad one.
const PREVIEW_SIZES: Array[int] = [180, 120, 76, 60]

const DEFAULT_OUT_DIR: String = "res://"
const PREVIEW_SUBDIR: String = "assets/icon/preview"

## Largest acceptable master PNG. App Store marketing assets have to stay
## sane, and anything above this means the gradients got noisy.
const MAX_MASTER_BYTES: int = 500 * 1024

# -- Palette ------------------------------------------------------------------
# Dusty-blue field, warm cream milk, soft pink collar, peach teat.
const BG_LIGHT: String = "#8FC6EA"
const BG_MID: String = "#5A9BD1"
const BG_DEEP: String = "#2F6EA6"
const GROUND: String = "#2E5C82"
const GLASS_TOP: String = "#FFFFFF"
const GLASS_BOTTOM: String = "#DCEBF4"
const MILK_TOP: String = "#FFF7E8"
const MILK_BOTTOM: String = "#FFE1B6"
const COLLAR_TOP: String = "#FAB7CE"
const COLLAR_BOTTOM: String = "#E4739C"
const TEAT_TOP: String = "#FCD6BC"
const TEAT_BOTTOM: String = "#EFA57D"

# -- Geometry (in the 1024 viewBox) -------------------------------------------
# Everything below is mirrored about x = 512, and the hero's vertical midpoint
# sits at y = 505, i.e. optically centred.
const CENTRE_X: float = 512.0

## Bottle silhouette: a genuinely narrow neck that stays narrow for a stretch
## below the collar, then sloping shoulders, straight sides and a round base.
## That visible neck notch is the single thing that separates "baby bottle"
## from "jar" in a 60px silhouette, so it is exaggerated on purpose.
const BODY_PATH: String = (
	"M414 352 L414 425 C414 458 352 474 352 545 L352 744 "
	+ "C352 784 382 816 420 816 L604 816 "
	+ "C642 816 672 784 672 744 L672 545 "
	+ "C672 474 610 458 610 425 L610 352 Z"
)

## The milk: same outline as the lower body, capped by a lazy wave.
const MILK_PATH: String = (
	"M352 570 C404 536 460 536 512 562 C564 588 620 586 672 554 "
	+ "L672 744 C672 784 642 816 604 816 L420 816 "
	+ "C382 816 352 784 352 744 Z"
)

## Silicone teat: a wide, short dome -- wide enough to survive downsampling.
const TEAT_PATH: String = (
	"M434 300 C434 250 442 216 462 200 C480 184 544 184 562 200 "
	+ "C582 216 590 250 590 300 Z"
)

## Safe circle the hero must not leave (fraction of icon width).
const SAFE_RADIUS_RATIO: float = 0.40

## Extreme points of the hero, used by the self-check below.
const HERO_EXTREMES: Array = [
	[352.0, 816.0],  # bottom-left of the base
	[672.0, 816.0],  # bottom-right of the base
	[512.0, 190.0],  # tip of the teat
	[352.0, 545.0],  # widest point, left
	[672.0, 545.0],  # widest point, right
	[400.0, 264.0],  # collar, upper left
	[624.0, 264.0],  # collar, upper right
]


func _init() -> void:
	var out_dir: String = _resolve_out_dir()
	if not out_dir.ends_with("/"):
		out_dir += "/"

	print("Little Buddy icon generator")
	print("  output: ", out_dir)

	var failures: int = 0

	if not _check_safe_area():
		failures += 1

	var svg: String = build_svg()

	# 1. Vector source, doubling as the Godot editor/project icon.
	var svg_path: String = out_dir + "icon.svg"
	if not _write_text(svg_path, svg):
		printerr("  FAIL  could not write ", svg_path)
		failures += 1
	else:
		print("  wrote ", svg_path, "  (", svg.length(), " chars)")

	# 2. Rasterise the master. load_svg_from_string() returns straight RGBA8;
	#    we flatten it onto an opaque backdrop and drop the alpha channel so
	#    the file iOS consumes has no transparency at all.
	var master: Image = _rasterise(svg, MASTER_SIZE)
	if master == null:
		printerr("  FAIL  SVG rasterisation failed")
		quit(1)
		return

	var master_path: String = out_dir + "icon_1024.png"
	if master.save_png(master_path) != OK:
		printerr("  FAIL  could not write ", master_path)
		failures += 1
	else:
		var report: Dictionary = _inspect_png(master_path)
		if report.has("error"):
			printerr("  FAIL  ", master_path, ": ", report["error"])
			failures += 1
		else:
			print(
				"  wrote %s  %dx%d  %s  %.1f KiB"
				% [
					master_path,
					report["width"],
					report["height"],
					"opaque" if report["opaque"] else "HAS ALPHA",
					report["bytes"] / 1024.0,
				]
			)
			if not report["opaque"]:
				printerr("  FAIL  master PNG is not opaque")
				failures += 1
			if int(report["bytes"]) > MAX_MASTER_BYTES:
				printerr("  FAIL  master PNG is too large")
				failures += 1

	# 3. Downsampled previews. These deliberately resize the *master* rather
	#    than re-rasterising the vector, because that is exactly what Godot's
	#    iOS exporter does when it derives the per-size app icons.
	var preview_dir: String = out_dir + PREVIEW_SUBDIR
	if not _ensure_dir(preview_dir):
		printerr("  FAIL  could not create ", preview_dir)
		failures += 1
	else:
		# Keep the previews out of the resource system: they are a dev-time
		# readability aid, not shipped content.
		_write_text(preview_dir + "/.gdignore", "")
		for size in PREVIEW_SIZES:
			var small: Image = master.duplicate()
			small.resize(size, size, Image.INTERPOLATE_LANCZOS)
			small.convert(Image.FORMAT_RGB8)
			var path: String = "%s/icon_%d.png" % [preview_dir, size]
			if small.save_png(path) != OK:
				printerr("  FAIL  could not write ", path)
				failures += 1
			else:
				print("  wrote ", path)

	if failures > 0:
		printerr("%d check(s) failed" % failures)
		quit(1)
		return

	print("All checks passed.")
	quit(0)


# -----------------------------------------------------------------------------
# Artwork
# -----------------------------------------------------------------------------


## Builds the complete icon as an SVG document.
##
## Draw order matters: field, halo, contact shadow, glass body, milk, highlight,
## teat, collar. The collar is last so it sits over the teat base and the
## bottle neck, which is what makes the silhouette read as a bottle rather than
## as a generic capsule.
func build_svg() -> String:
	var parts: PackedStringArray = PackedStringArray()

	parts.append(
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 1024 1024">'
			% [MASTER_SIZE, MASTER_SIZE]
		)
	)

	parts.append("<defs>")
	parts.append(
		_radial_gradient(
			"field",
			0.5,
			0.32,
			0.82,
			[[0.0, BG_LIGHT, 1.0], [0.5, BG_MID, 1.0], [1.0, BG_DEEP, 1.0]]
		)
	)
	parts.append(
		_radial_gradient(
			"halo",
			0.5,
			0.5,
			0.5,
			# Warm cream rather than white: it pulls the cold blue field towards
			# the nursery palette and makes the milk feel lit rather than pasted.
			# Kept low on purpose: a strong halo lightens the field right next to
			# the bottle and eats the local contrast the 60px render depends on.
			[[0.0, "#FFF4E0", 0.30], [0.55, "#FFF4E0", 0.12], [1.0, "#FFF4E0", 0.0]]
		)
	)
	parts.append(
		_radial_gradient(
			"ground",
			0.5,
			0.5,
			0.5,
			[[0.0, GROUND, 0.26], [0.6, GROUND, 0.10], [1.0, GROUND, 0.0]]
		)
	)
	parts.append(
		_linear_gradient("glass", [[0.0, GLASS_TOP, 1.0], [1.0, GLASS_BOTTOM, 1.0]])
	)
	parts.append(_linear_gradient("milk", [[0.0, MILK_TOP, 1.0], [1.0, MILK_BOTTOM, 1.0]]))
	parts.append(
		_linear_gradient("collar", [[0.0, COLLAR_TOP, 1.0], [1.0, COLLAR_BOTTOM, 1.0]])
	)
	parts.append(_linear_gradient("teat", [[0.0, TEAT_TOP, 1.0], [1.0, TEAT_BOTTOM, 1.0]]))
	parts.append(
		_linear_gradient("shine", [[0.0, "#FFFFFF", 0.62], [1.0, "#FFFFFF", 0.04]])
	)
	parts.append("</defs>")

	# Field: fills every pixel, so the finished image is opaque by construction
	# and the superellipse mask has colour to bite into in the corners.
	parts.append('<rect width="1024" height="1024" fill="url(#field)"/>')
	# Halo: lifts the hero off the field without a hard shape.
	parts.append('<circle cx="512" cy="506" r="420" fill="url(#halo)"/>')
	# Contact shadow: a whisper of grounding under the base.
	parts.append('<ellipse cx="512" cy="846" rx="232" ry="52" fill="url(#ground)"/>')

	parts.append('<path d="%s" fill="url(#glass)"/>' % BODY_PATH)
	parts.append('<path d="%s" fill="url(#milk)"/>' % MILK_PATH)
	# Single soft highlight down the left of the glass. Kept narrow and fading
	# to almost nothing so it reads as a curved surface, not as a white pill.
	parts.append('<rect x="392" y="500" width="44" height="250" rx="22" fill="url(#shine)"/>')
	parts.append('<path d="%s" fill="url(#teat)"/>' % TEAT_PATH)
	# Collar: deliberately chunky. Together with the neck it is what tells a
	# 60px viewer "bottle", so it must not thin out when downsampled.
	parts.append('<rect x="400" y="264" width="224" height="92" rx="44" fill="url(#collar)"/>')

	parts.append("</svg>")
	return "\n".join(parts) + "\n"


func _linear_gradient(id: String, stops: Array) -> String:
	# Top-to-bottom in object space: simple, and it keeps every fill lit from
	# the same direction.
	var out: String = '<linearGradient id="%s" x1="0" y1="0" x2="0" y2="1">' % id
	out += _stops(stops)
	return out + "</linearGradient>"


func _radial_gradient(id: String, cx: float, cy: float, r: float, stops: Array) -> String:
	var out: String = '<radialGradient id="%s" cx="%s" cy="%s" r="%s">' % [id, cx, cy, r]
	out += _stops(stops)
	return out + "</radialGradient>"


func _stops(stops: Array) -> String:
	var out: String = ""
	for stop in stops:
		out += (
			'<stop offset="%s" stop-color="%s" stop-opacity="%s"/>'
			% [stop[0], stop[1], stop[2]]
		)
	return out


# -----------------------------------------------------------------------------
# Rasterisation
# -----------------------------------------------------------------------------


## Renders the SVG at `size` and returns an opaque RGB8 image.
func _rasterise(svg: String, size: int) -> Image:
	var img: Image = Image.new()
	var err: int = img.load_svg_from_string(svg, float(size) / 1024.0)
	if err != OK:
		printerr("  load_svg_from_string failed: ", err)
		return null
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)

	# Belt and braces: composite over an opaque backdrop before dropping alpha,
	# so any stray edge pixel resolves to a real colour rather than to black.
	var flat: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	flat.fill(Color(BG_MID))
	flat.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	return flat


# -----------------------------------------------------------------------------
# Self-checks
# -----------------------------------------------------------------------------


## Verifies the hero stays inside the safe circle iOS's mask leaves visible.
func _check_safe_area() -> bool:
	var safe: float = 1024.0 * SAFE_RADIUS_RATIO
	var centre: Vector2 = Vector2(CENTRE_X, 512.0)
	var worst: float = 0.0
	for point in HERO_EXTREMES:
		worst = maxf(worst, centre.distance_to(Vector2(point[0], point[1])))
	if worst > safe:
		printerr(
			"  FAIL  hero leaves the safe circle (%.0f > %.0f px)" % [worst, safe]
		)
		return false
	print("  safe area ok: hero reaches %.0f px of a %.0f px radius" % [worst, safe])
	return true


## Reads the written PNG back off disk and reports on it.
func _inspect_png(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"error": "file is empty or unreadable"}

	var img: Image = Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return {"error": "PNG does not decode"}

	# PNG colour type lives at byte 25 of the IHDR chunk. 2 == truecolour RGB,
	# i.e. no alpha channel at all -- which is what iOS requires.
	var colour_type: int = bytes[25] if bytes.size() > 25 else -1

	return {
		"bytes": bytes.size(),
		"width": img.get_width(),
		"height": img.get_height(),
		"opaque": colour_type == 2 and not img.detect_alpha(),
		"colour_type": colour_type,
	}


# -----------------------------------------------------------------------------
# Plumbing
# -----------------------------------------------------------------------------


func _resolve_out_dir() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--out="):
			return args[i].substr(6)
	return DEFAULT_OUT_DIR


func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _ensure_dir(dir_path: String) -> bool:
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK

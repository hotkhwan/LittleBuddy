extends RefCounted

## The shipped branding files are what the store, the launcher and the engine
## expect, byte for byte where it matters.
##
##   * every iOS icon slot the export preset names exists at exactly its size,
##     is SQUARE and has NO alpha (iOS masks the corners itself; an icon with
##     transparency is rejected by App Store Connect and shows black corners on
##     older devices);
##   * the Android legacy icon and the adaptive pair are the sizes the exporter
##     wants, the foreground keeps alpha and the background does not;
##   * the boot splash is the 4:3 iPad frame, opaque, under 1.0 MB;
##   * the runtime logo textures keep alpha, stay under their byte budgets,
##     and are imported WITH mipmaps, because the menu scales them;
##   * none of it lives under `assets/uiGenerated`, which every export excludes.

const IOS_DIR: String = "res://assets/icon/ios"
const IOS_SIZES: Array[int] = [40, 58, 76, 80, 120, 152, 167, 180, 1024]
const ANDROID_DIR: String = "res://assets/icons/android"
const PROJECT_ICON: String = "res://assets/icon/app_icon_512.png"
const BOOT_SPLASH: String = "res://assets/branding/bootSplash.png"
const LOGO_1024: String = "res://assets/branding/littleDaysLogo_1024.png"
const LOGO_512: String = "res://assets/branding/littleDaysLogo_512.png"

const BOOT_SPLASH_MAX_BYTES: int = 1024 * 1024
const LOGO_1024_MAX_BYTES: int = 400 * 1024
const LOGO_512_MAX_BYTES: int = 200 * 1024


func test_name() -> String:
	return "branding_assets"


func run():
	var failures: Array = []
	failures.append_array(_test_ios_icons())
	failures.append_array(_test_android_icons())
	failures.append_array(_test_boot_splash())
	failures.append_array(_test_logo_textures())
	failures.append_array(_test_nothing_shipped_from_uiGenerated())
	return failures


func _test_ios_icons():
	var failures: Array = []
	for size: int in IOS_SIZES:
		var path: String = "%s/icon_%d.png" % [IOS_DIR, size]
		var image: Image = _read(path, failures)
		if image == null:
			continue
		if image.get_width() != size or image.get_height() != size:
			failures.append("%s is %dx%d, not %dx%d" % [path, image.get_width(), image.get_height(), size, size])
		if image.detect_alpha() != Image.ALPHA_NONE:
			failures.append("%s has an alpha channel; iOS icons must be opaque" % path)
		if _is_dark_corner(image):
			failures.append("%s has a dark corner; the rounded render was not composited over a fill" % path)
	var project_icon: Image = _read(PROJECT_ICON, failures)
	if project_icon != null and (project_icon.get_width() != 512 or project_icon.get_height() != 512):
		failures.append("%s is not 512x512" % PROJECT_ICON)
	return failures


func _test_android_icons():
	var failures: Array = []
	var legacy: Image = _read("%s/icon_192.png" % ANDROID_DIR, failures)
	if legacy != null:
		if legacy.get_width() != 192 or legacy.get_height() != 192:
			failures.append("icon_192.png is %dx%d" % [legacy.get_width(), legacy.get_height()])
		if legacy.detect_alpha() != Image.ALPHA_NONE:
			failures.append("icon_192.png has alpha; the legacy launcher icon is opaque")
	var fg: Image = _read("%s/icon_adaptive_foreground_432.png" % ANDROID_DIR, failures)
	if fg != null:
		if fg.get_width() != 432 or fg.get_height() != 432:
			failures.append("the adaptive foreground is %dx%d, not 432" % [fg.get_width(), fg.get_height()])
		if fg.detect_alpha() == Image.ALPHA_NONE:
			failures.append("the adaptive foreground has no transparency; the launcher mask needs it")
		# The art must fully cover the 72/108 mask circle: sample its extremes.
		var centre: float = 216.0
		var mask_radius: float = 432.0 * 72.0 / 108.0 * 0.5
		for angle: float in [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, PI * 1.25, PI * 1.5, PI * 1.75]:
			var p := Vector2(centre + cos(angle) * (mask_radius - 2.0), centre + sin(angle) * (mask_radius - 2.0))
			if fg.get_pixelv(Vector2i(p)).a < 0.99:
				failures.append("the adaptive foreground is transparent inside the launcher mask at %s" % p)
				break
		if fg.get_pixel(2, 2).a > 0.01:
			failures.append("the adaptive foreground's corner is opaque; the art should sit inside the safe zone")
	var bg: Image = _read("%s/icon_adaptive_background_432.png" % ANDROID_DIR, failures)
	if bg != null:
		if bg.get_width() != 432 or bg.get_height() != 432:
			failures.append("the adaptive background is %dx%d, not 432" % [bg.get_width(), bg.get_height()])
		if bg.detect_alpha() != Image.ALPHA_NONE:
			failures.append("the adaptive background has alpha")
		if bg.get_pixel(10, 10).v < 0.9:
			failures.append("the adaptive background is dark; it should be a flat pastel")
	return failures


func _test_boot_splash():
	var failures: Array = []
	var image: Image = _read(BOOT_SPLASH, failures)
	if image == null:
		return failures
	if image.get_width() != 2048 or image.get_height() != 1536:
		failures.append("bootSplash.png is %dx%d, not 2048x1536" % [image.get_width(), image.get_height()])
	if image.detect_alpha() != Image.ALPHA_NONE:
		failures.append("bootSplash.png has alpha; the engine composes it over bg_color and a seam would show")
	var bytes: int = _bytes(BOOT_SPLASH)
	if bytes > BOOT_SPLASH_MAX_BYTES:
		failures.append("bootSplash.png is %d KB; the budget is 1024 KB" % (bytes / 1024))
	var corner: Color = image.get_pixel(8, 8)
	if corner.v < 0.9 or corner.s > 0.15:
		failures.append("the boot splash corner is #%s; it should be the cream bg_color" % corner.to_html(false))
	return failures


func _test_logo_textures():
	var failures: Array = []
	for entry: Array in [[LOGO_1024, 1024, LOGO_1024_MAX_BYTES], [LOGO_512, 512, LOGO_512_MAX_BYTES]]:
		var path: String = entry[0]
		var image: Image = _read(path, failures)
		if image == null:
			continue
		if image.get_width() != int(entry[1]):
			failures.append("%s is %d wide, not %d" % [path, image.get_width(), int(entry[1])])
		if image.detect_alpha() == Image.ALPHA_NONE:
			failures.append("%s lost its transparency; the logo sits on scenes, not on a plaque" % path)
		if image.get_pixel(1, 1).a > 0.02:
			failures.append("%s is not trimmed to content (its corner is opaque)" % path)
		var bytes: int = _bytes(path)
		if bytes > int(entry[2]):
			failures.append("%s is %d KB; the budget is %d KB" % [path, bytes / 1024, int(entry[2]) / 1024])
		var import_text: String = FileAccess.get_file_as_string(path + ".import")
		if not import_text.contains("mipmaps/generate=true"):
			failures.append("%s.import does not generate mipmaps; the menu scales this texture" % path)
		var texture: Resource = load(path)
		if not (texture is Texture2D):
			failures.append("%s does not load as a Texture2D" % path)
	return failures


func _test_nothing_shipped_from_uiGenerated():
	var failures: Array = []
	for path: String in [BOOT_SPLASH, LOGO_1024, LOGO_512, PROJECT_ICON]:
		if path.contains("uiGenerated"):
			failures.append("%s lives under uiGenerated, which every export excludes" % path)
		if path.contains("generated_v1"):
			failures.append("%s lives under the owner's source pack, which is .gdignore'd and never in the pck" % path)
	# The pack's app-icon concept shows a white rabbit, not Bunny; its README
	# says it MUST NOT ship, and the folder it sits in is ignored by the engine.
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://assets/ui/generated_v1/.gdignore")):
		failures.append("assets/ui/generated_v1 has lost its .gdignore; the app-icon concept there must never ship")
	for script_path: String in [
		"res://scripts/branding/splash.gd",
		"res://scripts/branding/logo_title.gd",
		"res://scripts/branding/scene_transition.gd",
		"res://scenes/splash/splash.tscn",
	]:
		var text: String = FileAccess.get_file_as_string(script_path)
		if text.contains("uiGenerated"):
			failures.append("%s references uiGenerated, which is not in the shipped pck" % script_path)
	return failures


func _read(path: String, failures: Array) -> Image:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		failures.append("%s is missing" % path)
		return null
	var image: Image = Image.load_from_file(absolute)
	if image == null or image.is_empty():
		failures.append("%s is not a readable PNG" % path)
		return null
	return image


func _bytes(path: String) -> int:
	return FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).size()


static func _is_dark_corner(image: Image) -> bool:
	var w: int = image.get_width()
	var h: int = image.get_height()
	for p: Vector2i in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if image.get_pixelv(p).v < 0.5:
			return true
	return false

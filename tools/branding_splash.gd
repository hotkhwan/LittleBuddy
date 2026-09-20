extends SceneTree

## Renders the engine boot splash `res://assets/branding/bootSplash.png`.
##
##   Godot --path game --script res://../tools/branding_splash.gd   (NOT --headless: it draws)
##
## The boot splash is the very first frame a child sees, drawn by the engine
## before any script runs, so it is a plain PNG: 2048x1536 (the 4:3 iPad shape;
## `boot_splash/fullsize` letterboxes it on wider phones against the same cream,
## so the letterbox is invisible), the Little Days logo centred, and the
## "Made with Godot Engine" line the MIT licence asks for along the bottom.
##
## Rendered through a `SubViewport` rather than composed in Python because the
## attribution needs a real font, and this way the text is the project's own
## default font at a size that reads on a 7.9" screen. The logo comes straight
## from the owner's 2172 px render so nothing is upscaled.

const OUT_PATH: String = "res://assets/branding/bootSplash.png"
const PREVIEW_PATH: String = "res://../docs/shots/brand_boot_splash.png"
const LOGO_SOURCE: String = "res://assets/uiGenerated/branding/littleDaysLogo.png"
const SIZE := Vector2i(2048, 1536)
## Palette.CREAM -- must equal `boot_splash/bg_color` in project.godot.
const CREAM := Color(1.0, 0.965, 0.898)
## Palette.INK_SOFT: body copy that is not the headline.
const INK_SOFT := Color(0.541, 0.451, 0.345)
const LOGO_WIDTH_FRACTION: float = 0.62
const MAX_BYTES: int = 1024 * 1024


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var bg := ColorRect.new()
	bg.color = CREAM
	bg.size = Vector2(SIZE)
	viewport.add_child(bg)

	var image := Image.load_from_file(ProjectSettings.globalize_path(LOGO_SOURCE))
	if image == null:
		push_error("branding_splash: cannot read %s" % LOGO_SOURCE)
		quit(1)
		return
	# Trim to content so the logo, not its transparent air, is what gets centred.
	var used: Rect2i = image.get_used_rect()
	image = image.get_region(used)
	var texture := ImageTexture.create_from_image(image)

	var logo := TextureRect.new()
	logo.texture = texture
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var logo_w: float = SIZE.x * LOGO_WIDTH_FRACTION
	var logo_h: float = logo_w * float(image.get_height()) / float(image.get_width())
	logo.size = Vector2(logo_w, logo_h)
	# A touch above true centre: optically centred, and it leaves the bottom
	# band to the attribution without the two ever competing.
	logo.position = Vector2((SIZE.x - logo_w) * 0.5, (SIZE.y - logo_h) * 0.46)
	viewport.add_child(logo)

	var credit := Label.new()
	credit.text = "Made with Godot Engine"
	credit.add_theme_color_override("font_color", INK_SOFT)
	credit.add_theme_font_size_override("font_size", 40)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	credit.size = Vector2(SIZE.x, 80)
	credit.position = Vector2(0, SIZE.y - 80 - 56)
	viewport.add_child(credit)

	for _i in range(3):
		await process_frame
	RenderingServer.force_draw(true, 0.0)
	await RenderingServer.frame_post_draw

	var shot: Image = viewport.get_texture().get_image()
	if shot.get_width() != SIZE.x or shot.get_height() != SIZE.y:
		push_error("branding_splash: rendered %dx%d, asked %s" % [shot.get_width(), shot.get_height(), SIZE])
		quit(1)
		return
	shot.convert(Image.FORMAT_RGB8)
	var out_path: String = ProjectSettings.globalize_path(OUT_PATH)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	if shot.save_png(out_path) != OK:
		push_error("branding_splash: could not write %s" % OUT_PATH)
		quit(1)
		return
	var bytes: int = FileAccess.get_file_as_bytes(out_path).size()
	print("  wrote %s  %dx%d  %.1f KB" % [OUT_PATH, shot.get_width(), shot.get_height(), bytes / 1024.0])

	var preview: Image = shot.duplicate()
	preview.resize(1024, 768, Image.INTERPOLATE_LANCZOS)
	preview.save_png(ProjectSettings.globalize_path(PREVIEW_PATH))
	print("  wrote %s  1024x768" % PREVIEW_PATH)

	if bytes > MAX_BYTES:
		push_error("branding_splash: %d bytes is over the 1.0 MB budget" % bytes)
		quit(1)
		return
	print("BOOT SPLASH OK")
	quit(0)

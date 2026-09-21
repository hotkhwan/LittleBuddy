# Little Days generated UI pack v1

Each icon is an independently cropped PNG with alpha, 512 x 512. These are OWNER REVIEW design assets, not a claim they have been integrated into Godot.

- `ui/play.png`: Start / Play with Bunny or Continue icon (adjust label in Godot)
- `ui/free_play.png`: Free Play icon
- `ui/settings.png`: Settings icon
- `ui/dress_up.png`: Dress Up icon
- `ui/music.png`: Music control
- `ui/star.png`: Rewards
- `ui/back.png`: Back/navigation (rotate or mirror only after verifying semantic direction; currently curved-left)
- `ui/home.png`: Home
- `branding/logo_concept.png`: lettering/logo proposal. Check legibility on phone and resize in layout, do not raster-stretch.
- `branding/app_icon_CONCEPT_NOT_CANONICAL_BUNNY.png`: concept only. It contains a white rabbit rather than human baby Bunny and a different Aliz hairstyle, and MUST NOT be shipped as Little Days canonical character icon. Use the repo's canonical character render for final app icon instead.

Implementation: copy into `game/assets/ui/generated_v1/`; use icon inside consistent Godot TextureButton/button component. Keep accessible hit area ~44–48pt or larger and icon itself smaller; evaluate at iPhone and iPad viewports. Do not hard-replace working runtime assets before comparing. PNG assets have a generative origin; do not confuse with licensed third-party art. Keep the existing game's progress, navigation and subscriptions unchanged.

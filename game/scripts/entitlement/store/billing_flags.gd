extends RefCounted

## THE HARD SWITCH. Purchases are off in every build until the owner turns them on.
##
## One project setting decides whether ANY store gateway may start a purchase:
##
##     little_days/billing/purchases_enabled  (bool, committed FALSE)
##
## It is read here and nowhere else, and it is checked in `store_gateway.gd`'s
## base `purchase()` BEFORE the subclass hook runs -- so with the setting false no
## gateway, mock or real, ever reaches a store SDK. `test_billing_flags.gd` reads
## the committed `project.godot` and `export_presets.cfg` (not the running
## settings, so a local override cannot make it green) and fails the suite if the
## line is missing or true.
##
## Flipping it true is an owner decision recorded in `docs/FAMILY_CLUB_BILLING.md`
## (activation checklist: store products, secrets, backend env, approval, device
## QA). Nothing in the game reads this flag to show or hide a price.
##
## `mock_purchases_enabled_by_args()` is a developer convenience for running the
## purchase -> backend -> entitlement flow end to end on a desktop with the
## deterministic mock gateway (`-- --billing-mock-purchases`). It never applies to
## a real store adapter, and no exported build's launcher passes it.

const SETTING_PURCHASES_ENABLED: String = "little_days/billing/purchases_enabled"
const USER_ARG_MOCK_PURCHASES: String = "--billing-mock-purchases"

## The one status line the app may show for billing. Prices are NOT here (they
## belong to Parent Corner and the quota config, see the no-purchase guard).
const STATUS_TEXT_UNAVAILABLE: String = "Billing is not available in this build."

## Seconds a backend entitlement answer may be believed offline after the
## server last confirmed it, even if `periodEnd` is further out: 72 hours.
## A device that cannot reach the backend keeps Family Club for three days and
## then drops to Free Starter until the next successful verify. Bounded, never
## "until the file says otherwise".
const OFFLINE_CACHE_SECONDS: int = 72 * 3600


## May a REAL store purchase start? Only the project setting says yes.
static func purchases_enabled() -> bool:
	if not ProjectSettings.has_setting(SETTING_PURCHASES_ENABLED):
		return false
	return bool(ProjectSettings.get_setting(SETTING_PURCHASES_ENABLED))


## May the MOCK gateway pretend to purchase, for a developer run? The project
## setting or the developer user arg. Real adapters never consult this.
static func mock_purchases_enabled() -> bool:
	return purchases_enabled() or mock_purchases_enabled_by_args()


static func mock_purchases_enabled_by_args() -> bool:
	return OS.get_cmdline_user_args().has(USER_ARG_MOCK_PURCHASES)

extends RefCounted

## The seam between "where can Little Buddy walk" and the engine.
##
## `CharacterMovementController` only ever talks to one of these, never to
## `NavigationAgent3D`, `NavigationServer3D` or a `NavigationRegion3D`. That is
## what makes every movement decision -- path replacement, arrival debounce,
## reachability, cancel, state transitions -- coverable by real assertions in the
## headless `--script` runner, which has no physics frames and therefore no
## reliably synchronised navigation map.
##
## This base class is also a working implementation: **the straight-line
## fallback**. If navigation has not been baked (or the map has not synchronised
## yet, or a room ships without a `NavigationRegion3D`), the child still gets a
## character that walks where they tap. Degrading to "walks straight there" is
## always better for a four-year-old than a character that refuses to move.
##
## Subclasses override `query_path()` and `snap_to_navigable()`.
## `scripts/navigation/nav_map_provider.gd` is the real one.


## Is a real navigation mesh behind this provider? False for the straight-line
## fallback. Purely informational -- callers must work either way.
func is_navigation_ready() -> bool:
	return false


## The path from `from` to `to`, starting at `from` and ending at the closest
## point to `to` that is actually reachable.
##
## IMPORTANT CONTRACT, inherited from `NavigationServer3D.map_get_path()`: an
## unreachable `to` does NOT produce an empty path or an error. It produces a
## path that stops short. Reachability is therefore decided by the caller with
## `NavMath.path_reaches()`, never by a boolean from here.
func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([from, to])


## The closest point to `point` that the character could stand on. The
## straight-line fallback considers everywhere standable.
func snap_to_navigable(point: Vector3) -> Vector3:
	return point

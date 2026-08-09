## Delete opaque islands floating in the background of an installed cutout.
##
## The generator stamps a four-point sparkle into a corner of every image it draws (D219),
## and `install_cutouts` drops it for free: `cutout_lib.despeckle` removes components far
## below the largest, and a run of the enemy set reports 1 to 31 "stray island(s)" a file.
##
## **That only helps the files installed after the despeckle existed.** Anything installed
## before it kept its stamp, and the stamp is opaque, so it does not read as a hole and
## `find_gouges`, `find_bites` and `plate_check` all pass it: on magenta it is a small grey
## diamond sitting in the field beside the subject, which looks like part of the art until
## you notice it is the same diamond on another plate. `marrow_priest` carried one for its
## whole life, reported by a player as a hole in the sprite.
##
## The fix is not a repaint and not an inpaint. The island is BACKGROUND that was never
## cleared, so clearing it is exact and the subject is untouched.
##
## **A shortlist, like `refill_pockets.gd`, and for the same reason.** A floating opaque
## component can be legitimate — a thrown spark, a chip of stone, a swinging chain link
## drawn clear of the body. So this reports and `--fix <family>/<id>` writes, and there is
## no `--all`.
##
##   godot --headless --script tools/drop_strays.gd
##   godot --headless --script tools/drop_strays.gd -- --fix enemies/marrow_priest
##   godot --headless --import
extends SceneTree

const Cut := preload("res://tools/cutout_lib.gd")

const DIRS := ["enemies", "relics", "powers", "cards"]
## An island bigger than this share of the subject is not a speck, it is a design decision.
## The sparkle measures 0.3-1.5% of the plate it sits on; a limb or a weapon drawn clear of
## the body runs well past 8%, which is the figure `cutout_lib.despeckle` already uses.
const STRAY_FRAC := 0.08
## ...and below this many pixels it is not worth reporting at all: single-pixel motes are
## everywhere and dropping them changes nothing anyone can see.
const STRAY_MIN := 40

## The stamp when it TOUCHES the subject, which connectivity cannot reach (D220).
##
## `marrow_priest` was bridged to his sleeve by two pixels of pale paint; `brute` and
## `warden` carry one straddling the gap between a thigh and a hand, cut down the middle by
## the matte so half is welded to each side. One component with the figure, every time.
##
## So: a BOX, the way `strip_sparkle.gd --box` handles the one backdrop the intersection
## cannot do. Inside it, only pixels carrying the stamp's own signature are cleared — pale
## and desaturated — so a brown thigh or an orange pauldron inside the same box is left
## alone. The box goes in the command and never in the code, which is the point: a
## coordinate compiled into a tool is a number nobody can check later.
##
##   godot --headless --script tools/drop_strays.gd -- --erase enemies/brute 172,160,40,42
## Measured off the stamps on `brute` and `warden`: their pixels run 0.30-0.55 luminance at
## 0.01-0.16 saturation, while the brown thigh and orange pauldron they sit against are 0.4+
## saturated. So the saturation gate is what protects the art and the luminance gate only has
## to clear the stamp's dark RIM — at 0.38 the bright core went and the rim stayed as a ghost.
const ERASE_LUM := 0.30      ## the stamp is brighter than the art it is stamped over
const ERASE_SAT := 0.25      ## ...and far less saturated

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fix := args.has("--fix")
	var erase := args.has("--erase")
	var targets: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			targets.append(String(a))
	if erase:
		if targets.size() != 2:
			print("--erase needs <family>/<id> and x,y,w,h")
			quit(2)
			return
		_erase(String(targets[0]), String(targets[1]))
		quit(0)
		return
	if fix and targets.is_empty():
		print("--fix needs a named target, e.g. enemies/marrow_priest")
		quit(2)
		return
	var found := 0
	var written := 0
	print("%-26s %7s %7s  %s" % ["island", "px", "% subj", ""])
	for sub in DIRS:
		var dir_path := "res://assets/art/%s/" % sub
		for name in _pngs(dir_path):
			var rel := "%s/%s" % [sub, name.get_basename()]
			var mine := targets.has(rel) or targets.has(name.get_basename())
			if not targets.is_empty() and not mine:
				continue
			var n := _handle(dir_path + name, rel, fix and mine)
			found += int(n[0])
			written += int(n[1])
	print("\n%d floating island(s) worth looking at" % found)
	if written > 0:
		print("%d file(s) rewritten — run `godot --headless --import`" % written)
	elif found > 0:
		print("nothing written. Look at the plate on magenta (tools/plate_check.gd), then: "
			+ "--fix <family>/<id>")
	quit(0)

## Clear the stamp inside one box, by its own colour, and report what it took.
func _erase(rel: String, box: String) -> void:
	var parts := box.split(",")
	if parts.size() != 4:
		print("box must be x,y,w,h")
		return
	var path := "res://assets/art/%s.png" % rel
	var im := Cut.load_image(path)
	if im == null:
		print("no such plate: %s" % rel)
		return
	var w := im.get_width()
	var h := im.get_height()
	var x0 := maxi(0, int(parts[0]))
	var y0 := maxi(0, int(parts[1]))
	var x1 := mini(w, x0 + int(parts[2]))
	var y1 := mini(h, y0 + int(parts[3]))
	var cleared := 0
	var kept := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := im.get_pixel(x, y)
			if c.a * 255.0 <= float(Cut.ALPHA_CUT):
				continue
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			var sat: float = 0.0 if mx <= 0.001 else (mx - mn) / mx
			var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			if lum >= ERASE_LUM and sat <= ERASE_SAT:
				c.a = 0.0
				im.set_pixel(x, y, c)
				cleared += 1
			else:
				kept += 1
	if im.save_png(Cut.abs_path(path)) != OK:
		print("FAILED writing %s" % rel)
		return
	print(("%s: cleared %d px in the box, kept %d that were not the stamp"
		+ " — run `godot --headless --import`") % [rel, cleared, kept])

func _pngs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ProjectSettings.globalize_path(dir_path))
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.to_lower().ends_with(".png"):
			out.append(f)
		f = d.get_next()
	out.sort()
	return out

## Returns [islands_found, 1 if rewritten else 0].
func _handle(path: String, label: String, fix: bool) -> Array:
	var im := Cut.load_image(path)
	if im == null:
		return [0, 0]
	var w := im.get_width()
	var h := im.get_height()
	# Opaque components, 8-connected so a diagonal hairline does not split one in two.
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if im.get_pixel(x, y).a * 255.0 > float(Cut.ALPHA_CUT) else 0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var comps: Array = []
	for start in w * h:
		if seen[start] == 1 or solid[start] == 0:
			continue
		var members: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			members.append(i)
			var x: int = i % w
			var y: int = i / w
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				if seen[j] == 0 and solid[j] == 1:
					seen[j] = 1
					stack.append(j)
		comps.append(members)
	if comps.size() < 2:
		return [0, 0]
	comps.sort_custom(func(a, b): return a.size() > b.size())
	var biggest: int = comps[0].size()
	var strays: Array = []
	for k in range(1, comps.size()):
		var c: Array = comps[k]
		if c.size() < STRAY_MIN or float(c.size()) / float(biggest) > STRAY_FRAC:
			continue
		strays.append(c)
	if strays.is_empty():
		return [0, 0]
	for c in strays:
		print("%-26s %7d %6.1f%%  %s" % [label, c.size(),
			100.0 * float(c.size()) / float(biggest),
			"dropped" if fix else "candidate — LOOK at it before dropping it"])
	if not fix:
		return [strays.size(), 0]
	for c in strays:
		for i in c:
			var px := im.get_pixel(int(i) % w, int(i) / w)
			px.a = 0.0
			im.set_pixel(int(i) % w, int(i) / w, px)
	if im.save_png(Cut.abs_path(path)) != OK:
		print("  FAILED writing %s" % path)
		return [strays.size(), 0]
	return [strays.size(), 1]

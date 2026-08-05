## Headless test: the content pipeline itself, so the game can be expanded safely.
##
## Adding a card, an enemy or a dungeon touches a `.tres` file AND a hand-written
## catalogue in GDScript. Nothing used to check the two agreed, so a forgotten
## catalogue line meant a finished piece of content silently did not exist, and a
## typo'd id meant a dungeon quietly referenced nothing. Neither shows up as an
## error — the game just has less in it than you think.
##
## This suite exists so that expansion fails loudly. Everything it checks is a
## thing that has ALREADY gone wrong once in this project.
## Run: godot --headless --script tests/test_content.gd
extends SceneTree

## UI scripts reference autoloads, which are not registered in a headless
## `--script` run, so some things can only be checked as source text.
func _source_has(path: String, needle: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	return text.find(needle) != -1

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()

	# --- catalogues must match what is on disk, in BOTH directions ---
	#
	# An orphan is finished content nobody can reach; a ghost is a catalogue entry
	# whose file was renamed or deleted, which fails at load with no clue why.
	for spec in [
			["cards", "res://resources/cards/", m.CATALOG.keys()],
			["relics", "res://resources/relics/", m.RELIC_CATALOG.keys()],
			["powers", "res://resources/powers/", Balance.POWERS],
			["dungeons", "res://resources/dungeons/", Balance.DUNGEONS],
			["zones", "res://resources/zones/", Balance.ZONES],
			["builds", "res://resources/builds/", Balance.BUILDS]]:
		var label: String = spec[0]
		var on_disk := _ids_in(spec[1])
		var catalogued := {}
		for id in spec[2]:
			catalogued[id] = true
		for id in on_disk:
			if not catalogued.has(id):
				fails += 1
				print("FAIL %s/%s.tres exists but is in no catalogue — unreachable content" % [
					label, id])
		for id in catalogued:
			if not (id in on_disk):
				fails += 1
				print("FAIL %s catalogue names '%s', which has no file" % [label, id])

	# --- every id inside a resource matches its filename ---
	# A mismatch makes lookups miss in one direction only, which is the worst kind.
	for id in _ids_in("res://resources/cards/"):
		var c := load("res://resources/cards/%s.tres" % id) as CardData
		if c != null and c.id != id:
			fails += 1; print("FAIL card file '%s' declares id '%s'" % [id, c.id])
	for id in _ids_in("res://resources/enemies/"):
		var e := load("res://resources/enemies/%s.tres" % id) as EnemyData
		if e != null and e.id != id:
			fails += 1; print("FAIL enemy file '%s' declares id '%s'" % [id, e.id])

	# --- cross-references are plain strings and fail silently when wrong ---
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		for cid in Array(d.card_pool) + Array(d.exclusive_cards):
			if not m.CATALOG.has(cid):
				fails += 1; print("FAIL dungeon %s references missing card '%s'" % [did, cid])
		var foes: Array = Array(d.enemy_roster)
		if d.boss != "":
			foes.append(d.boss)
		for eid in foes:
			if not ResourceLoader.exists(Balance.ENEMY_DIR + eid + ".tres"):
				fails += 1; print("FAIL dungeon %s references missing enemy '%s'" % [did, eid])
	for zid in Balance.ZONES:
		var z := Balance.zone(zid)
		if z == null:
			continue
		for did2 in Array(z.dungeons):
			if not (did2 in Balance.DUNGEONS):
				fails += 1; print("FAIL zone %s references missing dungeon '%s'" % [zid, did2])
	for bid in Balance.BUILDS:
		var b := Balance.build(bid)
		if b == null:
			continue
		for cid2 in Array(b.cards):
			if not m.CATALOG.has(cid2):
				fails += 1; print("FAIL build %s references missing card '%s'" % [bid, cid2])
	# every dungeon must belong to exactly one zone, or it is unreachable in the UI
	var placed := {}
	for zid2 in Balance.ZONES:
		var z2 := Balance.zone(zid2)
		if z2 == null:
			continue
		for did3 in Array(z2.dungeons):
			if placed.has(did3):
				fails += 1; print("FAIL dungeon %s is in two zones" % did3)
			placed[did3] = zid2
	for did4 in Balance.DUNGEONS:
		if not placed.has(did4):
			fails += 1; print("FAIL dungeon %s belongs to no zone — unreachable" % did4)

	# --- every archetype has a plate, and adding one cannot steal another's ---
	#
	# This used to measure "sprite headroom": how many CC0 tiles were left in a shared
	# pool before the next archetype started sharing a face with an existing one. The
	# pool is gone (D89) and so is the whole failure mode — plates are keyed by
	# archetype id and generated from each archetype's own fight data, so a new `.tres`
	# gets its own and steals nobody's. What is left to check is that somebody ran the
	# generator.
	var enemies: int = PixelArt.archetype_ids().size()
	var plated := 0
	for aid in PixelArt.archetype_ids():
		if PixelArt.enemy_art(String(aid)) != null:
			plated += 1
	print("  enemy plates: %d of %d archetypes" % [plated, enemies])
	if plated < enemies:
		fails += 1
		print("FAIL %d archetype(s) have no plate — run tools/gen_enemy_art.gd, then --import" % [
			enemies - plated])
	var card_headroom: int = PixelArt.CARD_TILES.size() - m.CATALOG.size()
	print("  card art headroom: %d" % card_headroom)
	if card_headroom < 0:
		fails += 1; print("FAIL more cards than card illustrations")

	# --- enum ordinals are PERSISTED, so they may only ever be appended to ---
	#
	# Enemy patterns store these as raw ints in .tres, and spent relic triggers go
	# into save files. Inserting a value silently rewrites every existing enemy and
	# every save. Pinned here so a reorder fails a test instead of shipping.
	for pin in [["EnemyData.Action.ATTACK", EnemyData.Action.ATTACK, 0],
			["EnemyData.Action.SUNDER", EnemyData.Action.SUNDER, 5],
			["EnemyData.Action.DRAIN", EnemyData.Action.DRAIN, 7],
			["EnemyData.Trigger.SELF_HP_BELOW_PCT", EnemyData.Trigger.SELF_HP_BELOW_PCT, 0],
			["EnemyData.Trigger.EVERY_N_TURNS", EnemyData.Trigger.EVERY_N_TURNS, 4],
			["RelicData.Trigger.ON_KILL", RelicData.Trigger.ON_KILL, 0],
			["RelicData.Trigger.ON_BLOCK_EXPIRED", RelicData.Trigger.ON_BLOCK_EXPIRED, 4],
			["RelicData.Effect.DAMAGE_ALL", RelicData.Effect.DAMAGE_ALL, 0],
			["RelicData.Effect.GAIN_ENERGY", RelicData.Effect.GAIN_ENERGY, 5],
			["CardData.Rarity.LEGENDARY", CardData.Rarity.LEGENDARY, 4]]:
		if int(pin[1]) != int(pin[2]):
			fails += 1
			print("FAIL %s is now %d, was %d — existing .tres and saves refer to the old number" % [
				pin[0], int(pin[1]), int(pin[2])])

	# --- a hand-computed constant that silently rots ---
	#
	# BASELINE_CARD_POWER is the reference deck's power per energy, written out by
	# hand. Every scaling number in the game is relative to it, so if card pricing
	# changes and this is not recomputed, the whole curve drifts with no error.
	var ref: Array = []
	for i in 4:
		ref.append(load("res://resources/cards/hack.tres"))
		ref.append(load("res://resources/cards/cover.tres"))
	var recomputed: float = Balance.deck_power(ref) / Balance.deck_cost(ref)
	if absf(recomputed - Balance.BASELINE_CARD_POWER) > 0.01:
		fails += 1
		print("FAIL BASELINE_CARD_POWER is %.3f but the reference deck now measures %.3f" % [
			Balance.BASELINE_CARD_POWER, recomputed])

	# --- the project must stay exportable to every platform we target ---
	#
	# Android and iOS can never be BUILT in CI: one needs a JDK and the Android
	# SDK, the other needs macOS, Xcode and a per-developer team ID. What can be
	# guaranteed is that nothing in the repository is what stops them. This is the
	# half that needs no export templates; tests/export_ready.sh does the rest by
	# actually attempting each export.
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		fails += 1; print("FAIL export_presets.cfg is missing or unreadable")
	else:
		var want := {"Linux": false, "Windows": false, "macOS": false,
			"Android": false, "iOS": false}
		for section in cfg.get_sections():
			if not section.ends_with(".options"):
				var nm: String = cfg.get_value(section, "name", "")
				if want.has(nm):
					want[nm] = true
		for nm2 in want:
			if not want[nm2]:
				fails += 1
				print("FAIL no export preset for %s — the platform would have to be set up from scratch" % nm2)

		# An Android APK carries only the ABIs its preset asks for, and Godot's
		# default asks for arm64-v8a alone — which a 32-bit-only phone cannot
		# install AT ALL. It reports that as "app not compatible" at install time,
		# saying nothing about ABIs, so the APK shipped arm64-only for 22 builds
		# without anyone being told (D170). Guarded HERE rather than only in CI
		# because the editor REWRITES this file whenever the export dialog is
		# touched, and a rewrite that drops these keys is silent.
		for section2 in cfg.get_sections():
			if section2.ends_with(".options") \
					and cfg.get_value(section2.trim_suffix(".options"), "name", "") == "Android":
				for abi in ["armeabi-v7a", "arm64-v8a"]:
					if not bool(cfg.get_value(section2, "architectures/" + abi, false)):
						fails += 1
						print("FAIL the Android preset does not build %s — every %s device would refuse to install the APK" % [
							abi, "32-bit" if abi.begins_with("armeabi") else "64-bit"])

				# --- the launcher icon (D180) ---
				#
				# Guarded here for the same reason as the ABIs, and it is the same failure
				# shape: an unset icon key is not an error, it is Godot quietly shipping its
				# OWN logo onto a phone's home screen, and no build log mentions it. That is
				# what 22 builds did. The editor also rewrites this file whenever the export
				# dialog is touched, so a rewrite that drops these keys has to be caught by
				# something other than looking at a launcher.
				#
				# Sizes are asserted because Android's names are not hints: a 432px layer is
				# masked to its central 66%, and a foreground at the wrong size is cropped
				# rather than scaled.
				var icons := {
					"launcher_icons/main_192x192": 192,
					"launcher_icons/adaptive_foreground_432x432": 432,
					"launcher_icons/adaptive_background_432x432": 432,
					"launcher_icons/adaptive_monochrome_432x432": 432,
				}
				for key in icons:
					var ipath: String = String(cfg.get_value(section2, key, ""))
					if ipath.is_empty():
						fails += 1
						print("FAIL the Android preset sets no %s — the APK ships Godot's logo" % key)
						continue
					if not ResourceLoader.exists(ipath):
						fails += 1
						print("FAIL %s points at %s, which is not in the project" % [key, ipath])
						continue
					var itex := load(ipath) as Texture2D
					var want_px: int = int(icons[key])
					if itex == null or itex.get_width() != want_px or itex.get_height() != want_px:
						fails += 1
						print("FAIL %s is %s, not %dx%d" % [
							key, "unloadable" if itex == null else "%dx%d" % [
								itex.get_width(), itex.get_height()], want_px, want_px])

	# The window icon and every exporter's fallback (D180). Godot's default for an unset
	# `config/icon` is its own logo, which is why this is asserted rather than assumed, and
	# the size is asserted as a whole-number multiple of the 48-cell grid the art is drawn
	# on: a pixel-art icon scaled by 5.33 draws some pixels five wide and others six.
	var app_icon: String = String(ProjectSettings.get_setting("application/config/icon", ""))
	if app_icon.is_empty() or not ResourceLoader.exists(app_icon):
		fails += 1
		print("FAIL application/config/icon is '%s' — the game wears the engine's logo" % app_icon)
	else:
		var it := load(app_icon) as Texture2D
		if it == null:
			fails += 1; print("FAIL the app icon at %s does not load" % app_icon)
		elif it.get_width() != it.get_height() or it.get_width() % 48 != 0:
			fails += 1
			print("FAIL the app icon is %dx%d — not a square whole-number scale of the 48px grid" % [
				it.get_width(), it.get_height()])

	# arm64 targets (macOS universal, Android, iOS) refuse to export without this
	if not bool(ProjectSettings.get_setting(
			"rendering/textures/vram_compression/import_etc2_astc", false)):
		fails += 1
		print("FAIL import_etc2_astc is off — every arm64 target refuses to export")

	# a hand of cards along the bottom of a 1280x720 layout is unusable in portrait
	var orientation := int(ProjectSettings.get_setting(
		"display/window/handheld/orientation", 0))
	if orientation == 0:
		fails += 1; print("FAIL no handheld orientation set — phones default to portrait")

	# the whole UI is Buttons; without this, touch presses nothing
	if not bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", true)):
		fails += 1; print("FAIL touch does not emulate mouse — no button in the game responds")

	# a finger sends no hover events, so cards must be readable without one
	if not _source_has("res://scripts/ui.gd", "touch_ui"):
		fails += 1
		print("FAIL no touch path in card_button — cards would be unreadable until played")

	# --- the README's numbers are claims, and a claim nobody re-checks goes stale ---
	#
	# The front page carries a `tests-N suites` badge and a "39 suites" row, and the
	# badge is a hand-written string on shields.io — there is no service counting them
	# for us. So the count is asserted HERE, against the same globs `tests/run.sh`
	# actually runs. Add a suite and this fails until the badge is corrected, which is
	# the only mechanism that has ever kept a number in this repo honest (D141).
	var suites := 0
	var td := DirAccess.open("res://tests")
	if td == null:
		fails += 1; print("FAIL cannot open res://tests to count suites")
	else:
		td.list_dir_begin()
		var f := td.get_next()
		while f != "":
			if (f.begins_with("test_") and f.ends_with(".gd")) or f.ends_with("Test.tscn"):
				suites += 1
			f = td.get_next()
		td.list_dir_end()
		var readme := FileAccess.open("res://README.md", FileAccess.READ)
		if readme == null:
			fails += 1; print("FAIL README.md is missing")
		else:
			var text := readme.get_as_text()
			readme.close()
			# both the badge (URL-encoded) and the prose row
			for claim in ["tests-%d%%20suites" % suites, "%d suites" % suites]:
				if text.find(claim) == -1:
					fails += 1
					print("FAIL README does not say '%s' — there are %d suites now" % [
						claim, suites])
			# A per-release download counter cannot survive a rolling release: the release
			# object is deleted and recreated on every green push, and the counts go with
			# it, so the badge reads "downloads since the last commit" — usually 0, and
			# never what a reader takes it for (D158). Deleted, and kept deleted here.
			if text.find("img.shields.io/github/downloads") != -1:
				fails += 1
				print("FAIL README has a downloads badge — the release is recreated per push, so it counts nothing (D158)")

			# The licence badge is a STATIC string too, and for a better reason than the
			# suite count: the dynamic one read the licence off the GitHub API, and when
			# that answered "repo not found" for one minute during a rename, GitHub's
			# image proxy cached the red picture and would not give it up — camo no
			# longer honours PURGE, so a transient upstream failure reds a badge until
			# its URL changes. A fact that never changes should not be fetched (D148).
			# It is pinned to the actual LICENSE file instead.
			var lic := FileAccess.open("res://LICENSE", FileAccess.READ)
			if lic == null:
				fails += 1; print("FAIL LICENSE is missing")
			else:
				var ltext := lic.get_as_text()
				lic.close()
				var is_apache2 := ltext.find("Apache License") != -1 \
					and ltext.find("Version 2.0") != -1
				if not is_apache2:
					fails += 1
					print("FAIL LICENSE is no longer Apache 2.0 — the README badge says it is")
				elif text.find("licence-Apache_2.0-brightgreen") == -1:
					fails += 1
					print("FAIL README licence badge does not match LICENSE (Apache 2.0)")

	# --- the build says which build it is, and the committed value is never a stamped one ---
	#
	# The release channel is a rolling tag: `latest` is deleted and recreated on every green
	# push, so the README's download links always serve the newest build AND every published
	# APK has the identical filename. That is a good property for the link and a bad one for
	# a bug report — hence the stamp (D156), and hence this check, which guards the two ways
	# it can quietly stop working.
	var stamp := String(ProjectSettings.get_setting(BuildInfo.KEY, ""))
	if stamp == "":
		fails += 1; print("FAIL %s is not set — a build cannot say which build it is" % BuildInfo.KEY)
	# A stamped `project.godot` must never be committed: `tools/stamp_build.sh` runs per
	# export in CI, and if its output were committed then every hand build afterwards would
	# claim to be whichever CI build was exported last.
	elif not stamp.ends_with(BuildInfo.DEV_SUFFIX):
		fails += 1
		print("FAIL config/version is committed as '%s' — a stamped build got committed; it must end in '%s'" % [
			stamp, BuildInfo.DEV_SUFFIX])
	if not BuildInfo.is_dev():
		fails += 1; print("FAIL BuildInfo.is_dev() is false in the repository")
	if not BuildInfo.label().begins_with("v"):
		fails += 1; print("FAIL BuildInfo.label() does not read as a version: %s" % BuildInfo.label())
	if not FileAccess.file_exists("res://tools/stamp_build.sh"):
		fails += 1; print("FAIL tools/stamp_build.sh is gone — nothing stamps a release")
	# The stamp is worth nothing if no screen shows it. Source-level, because both screens
	# reference autoloads and cannot be built in a `--script` run.
	for screen in ["res://scripts/main_menu.gd", "res://scripts/settings_menu.gd"]:
		var src := FileAccess.open(screen, FileAccess.READ)
		if src == null:
			fails += 1; print("FAIL %s is missing" % screen); continue
		var body := src.get_as_text()
		src.close()
		if body.find("BuildInfo") == -1:
			fails += 1
			print("FAIL %s no longer shows the build stamp" % screen)
	# And CI has to actually stamp, in every job that exports something.
	var wf := FileAccess.open("res://.github/workflows/ci.yml", FileAccess.READ)
	if wf != null:
		var yml := wf.get_as_text()
		wf.close()
		var stamps := yml.count("tools/stamp_build.sh")
		var exports := yml.count("--export-release")
		if stamps < 2:
			fails += 1
			print("FAIL ci.yml calls the stamper %d time(s) for %d export step(s)" % [stamps, exports])
	print("  (info: build stamp is '%s', dev=%s)" % [stamp, BuildInfo.is_dev()])

	# --- the signing key can never be committed, and the ignore has to cover what the
	# --- script actually writes ---
	#
	# A committed keystore is not just a leaked private key: it IS the app's identity to
	# Android (D157), so anyone holding it could sign a package that installs over a player's
	# copy. And it would have to be replaced, which costs every install the one forced
	# uninstall a stable key exists to avoid. Two halves, because the pattern being present
	# proves nothing if the script writes something it does not match.
	var ignore := FileAccess.open("res://.gitignore", FileAccess.READ)
	if ignore == null:
		fails += 1; print("FAIL .gitignore is missing")
	else:
		var rules := ignore.get_as_text()
		ignore.close()
		for pattern in ["*.keystore", "*.jks"]:
			if rules.find(pattern) == -1:
				fails += 1
				print("FAIL .gitignore does not ignore %s — a signing key could be committed (D157)" % pattern)
		var keygen := FileAccess.open("res://tools/make_release_key.sh", FileAccess.READ)
		if keygen == null:
			fails += 1; print("FAIL tools/make_release_key.sh is gone")
		else:
			var script := keygen.get_as_text()
			keygen.close()
			# The default output path, as the script spells it: `out="${1:-$PWD/<name>}"`.
			var at := script.find("out=\"${1:-")
			if at < 0:
				fails += 1; print("FAIL cannot find make_release_key.sh's default output path")
			else:
				var line := script.substr(at, script.find("\n", at) - at)
				var suffix_ok := false
				for pattern in ["*.keystore", "*.jks"]:
					if line.ends_with(pattern.substr(1) + "\"}\"") or line.contains(pattern.substr(1)):
						suffix_ok = true
				if not suffix_ok:
					fails += 1
					print("FAIL make_release_key.sh writes %s, which no .gitignore rule covers" % line)

	# --- and the signing step has to say WHY it could not open the key ---
	#
	# It failed once with a message that named the wrong cause, because the password had a
	# default (`theowing`, so a missing secret read as a wrong password) and because keytool
	# prints its reason on stdout, which the step sent to /dev/null (D162). Both are one
	# character of shell away from coming back, so both are pinned here.
	var wf2 := FileAccess.open("res://.github/workflows/ci.yml", FileAccess.READ)
	if wf2 == null:
		fails += 1; print("FAIL .github/workflows/ci.yml is missing")
	else:
		var yml2 := wf2.get_as_text()
		wf2.close()
		# The assignment, not `${KEYSTORE_PASSWORD:-}` — the empty-guard idiom is how the step
		# tests for the secret at all, so matching the bare prefix flags the fix as the bug.
		if yml2.contains("pass=\"${KEYSTORE_PASSWORD:-"):
			fails += 1
			print("FAIL ci.yml defaults the keystore password again — a missing secret will report as a wrong one (D162)")
		if yml2.contains("-storepass \"$pass\" -alias \"$alias\" >/dev/null"):
			fails += 1
			print("FAIL ci.yml drops keytool's stdout, which is where it prints why the key would not open (D162)")

	# --- the rules screen states rules, and nothing about this save ---
	#
	# How the Owing Works had the Builds tracker embedded in it, so half the screen was
	# the game and half was one player's progress, with nothing marking the join (D166).
	# The line the screen is held to is mechanical: it may read the BALANCE (numbers that
	# are the same for everyone — deck size, escalation, the death penalty) and it may not
	# read `MetaState`, which is the save. Checked as text because the alternative is
	# rendering it against two saves and diffing, and this is the property that was
	# actually broken.
	var gl := FileAccess.open("res://scripts/glossary.gd", FileAccess.READ)
	if gl == null:
		fails += 1; print("FAIL scripts/glossary.gd is missing")
	else:
		var src2 := gl.get_as_text()
		gl.close()
		for banned in ["MetaState.", "GameState.", "builds_screen.gd"]:
			# Comments explain WHY the screen may not do this, so only real code counts.
			for line2 in src2.split("\n"):
				var code := line2.strip_edges()
				if code.begins_with("#") or not code.contains(banned):
					continue
				fails += 1
				print("FAIL glossary.gd reads %s — the rules screen must say nothing about one save (D166): %s" % [
					banned, code])
				break

	if fails == 0:
		print("CONTENT TEST: PASS (catalogues, ids, references, art capacity, enum pins, baseline, export readiness, README counts, build stamp)")
	else:
		print("CONTENT TEST: FAIL (%d)" % fails)
	quit()

func _ids_in(dir: String) -> Array:
	var out: Array = []
	for p in PixelArt.list_resources(dir, ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	return out

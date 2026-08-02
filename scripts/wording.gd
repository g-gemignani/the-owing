## Shared rules of the written voice — the parts of a sentence that are the same
## wherever the sentence is built.
##
## It is its own file for a reason that is not tidiness. The obvious home was `UI`,
## where the screens already are, and `UI` is unreachable from half the code that
## writes player-facing text: `ui.gd` names the `UITheme` autoload, and an autoload
## referenced at compile time makes every script that depends on it fail to compile
## in a headless `--script` run — which does not go red, it HANGS, because the error
## skips the `quit()` (D19, fourth time). `Icons.card_lines()` and
## `CardFilter.summary()` are pure text and are called by four `--script` suites, so
## a text helper that drags the theme in is a helper they cannot use. Nothing in here
## may touch an autoload, a Node or a Texture.
##
## Deliberately not `Balance`: that file is the single source of truth for TUNING,
## and a number that changes the game does not belong in the same drawer as a rule
## about the letter s.
class_name Wording
extends RefCounted

## "1 clear", "4 clears" — a counted noun, agreeing with the number in front of it.
##
## The Powers screen shipped "needs 1 clears", because two of the ten powers unlock
## at exactly one clear and the line was written as a bare `%d clears`. That shape is
## all over the screens, and the three answers already in the tree were the actual
## problem: the correct one spelled out at the call site (`"%d card%s" % [n, "" if n
## == 1 else "s"]`), the `card(s)` evasion, and a plural that is simply wrong at one.
## One wrong line is a typo; three idioms for one rule is a thing to name and share
## (D125).
##
## `many` is for a noun English does not pluralise with an s — "copy"/"copies" is the
## one call site that needs it today, and it is the reason the parameter exists
## rather than a `+ "s"` buried in a format string.
##
## This is for a LEDGER line, where the number is the point and only the noun has to
## agree with it. Where the count is dramatic the voice still writes both sentences
## by hand and should: `CombatEngine.take_draw_notice()` says "the draw stays in the
## pile" and the iso hint says "Something is moving nearby", neither of which any
## formatter would have produced.
static func count(n: int, one: String, many: String = "") -> String:
	return "%d %s" % [n, one if n == 1 else (many if many != "" else one + "s")]

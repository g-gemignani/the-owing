#!/usr/bin/env python3
"""Generate the missing art through Pollinations, obeying ART_PROMPTS.md.

ART_PROMPTS.md is generated from the content catalogues, so it — not this file —
is the source of truth for wording. This tool parses it rather than restating it:
a prompt sheet copied into a script goes stale the moment a card or enemy is
renamed, which is the exact failure the generated sheet exists to prevent (D73).

Its three rules are enforced here, not left to the caller:

  1. ONE generator for everything. The model is fixed per run and recorded in the
     staging receipt, so a later run cannot silently mix dialects.
  2. `assets/art/bg_crypt.png` is attached to EVERY request as a style
     reference. This is why the model must accept reference images — `flux` does
     NOT, and choosing it silently discards the style bible (D100).
  3. The style block is pasted verbatim, once per request, unimproved.

Output goes to a staging directory; nothing is written into assets/art/. The
Godot installers named per tier in ART_PROMPTS.md do the matte/trim/anchor work
and own the final filenames (D73).

  python3 tools/gen_pollinations.py --list
  python3 tools/gen_pollinations.py --tier 3 --dry-run
  python3 tools/gen_pollinations.py --tier 3 --out /tmp/staging/cards
  python3 tools/gen_pollinations.py --tier 2 --only abyss_horror --out /tmp/s

There is also a keyless route for hand-driving a chat UI (Gemini, ChatGPT) in a
browser, which composes the same prompts from the same sheet and prints them for
copy-paste. It needs no key and makes no network call:

  python3 tools/gen_pollinations.py --browser > /tmp/browser_prompts.md
  python3 tools/gen_pollinations.py --browser --tier 6a

Key: $POLLINATIONS_API_KEY, or ~/.config/pollinations/api-key (chmod 600).
Get one at https://enter.pollinations.ai/keys
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request
import uuid

REPO = pathlib.Path(__file__).resolve().parent.parent
PROMPTS = REPO / "ART_PROMPTS.md"
STYLE_REFERENCE = REPO / "assets" / "art" / "bg_crypt.png"
ENDPOINT = "https://gen.pollinations.ai/v1/images/edits"
USER_AGENT = "deckcrawl-art-tool/1.0 (+tools/gen_pollinations.py)"
KEY_FILE = pathlib.Path.home() / ".config" / "pollinations" / "api-key"

# Reference-image capable models only (`in=text,image` in /image/models).
DEFAULT_MODEL = "nanobanana-2"
TEXT_ONLY_MODELS = {"flux", "zimage", "dreamshaper", "p-image", "ideogram-v4-turbo"}

# Generation sizes, from the per-tier prose in ART_PROMPTS.md ("Generate at
# 1024x1024 and let the installer scale down"). Generation size is NOT the final
# asset size — the installers scale and anchor.
TIER_RULES = {
    "0": {"size": "1024x1024"},
    "1b": {"size": "1024x1024"},
    "1c": {"size": "768x768"},
    "1d": {"size": "1280x1280"},
    "2": {"size": "1024x1024"},
    "3": {"size": "1024x768"},  # 4:3, cropped to the 320x240 card band
    # Tier 4 is THREE sheets, not one: the node icons, the tile icons and the
    # dice faces install separately (`install_sheet.gd -- nodes|tiles|dice`).
    "4": {
        "size": "1024x1024",
        "groups": [("nodes", "node_"), ("tiles", "tile_"), ("dice", "die_")],
    },
    "5": {"size": "1280x720"},
    "5b": {"size": "1280x720"},
    "5c": {"size": "1280x720"},
    "6a": {"size": "1024x1024"},
    "6b": {"size": "1024x768"},
    "7": {"size": "1600x480"},
}


# A chat UI has no `size` parameter, so the browser route has to say the shape in
# words instead. Keyed by the generation sizes above.
ASPECT = {
    "1024x1024": "a square 1:1 image",
    "768x768": "a square 1:1 image",
    "1280x1280": "a square 1:1 image",
    "1024x768": "a 4:3 landscape image",
    "1280x720": "a 16:9 landscape image",
    "1600x480": "a 10:3 wide banner image",
    "960x1344": "a portrait 5:7 image",
}

# The shape of a request is per FILE, not per tier, and tier 0 is where that bit:
# five square-ish cutouts and one card BACK, which is 320x448 because the card is
# 150x214. A tier-wide "generate a square 1:1 image" was asking for a portrait asset
# at 1:1, so whatever came back had to be squashed into the card or cropped (D109).
# ART_PROMPTS.md now carries each row's target size and these two derive from it.
ASPECT_NAMES = [
    (1 / 1, "a square 1:1 image"),
    (4 / 3, "a 4:3 landscape image"),
    (16 / 9, "a 16:9 landscape image"),
    (10 / 3, "a 10:3 wide banner image"),
    (3 / 4, "a 3:4 portrait image"),
    (5 / 7, "a portrait 5:7 image"),
    (2 / 3, "a 2:3 portrait image"),
]


def parse_size(size: str) -> tuple[int, int] | None:
    m = re.fullmatch(r"(\d+)x(\d+)", size.strip())
    return (int(m.group(1)), int(m.group(2))) if m else None


def aspect_words(size: str) -> str:
    """The nearest named shape for a WxH, by ratio."""
    wh = parse_size(size)
    if wh is None:
        return size
    ratio = wh[0] / wh[1]
    return min(ASPECT_NAMES, key=lambda p: abs(p[0] / ratio - 1.0))[1]


def gen_size(size: str) -> str:
    """A generation size for an asset size: the smallest whole multiple whose long
    edge clears 1024. A whole multiple keeps the aspect EXACT, which a snapped-to-16
    scale factor does not — and the aspect is the entire point of computing this."""
    wh = parse_size(size)
    if wh is None:
        return size
    k = 1
    while max(wh) * k < 1024:
        k += 1
    return f"{wh[0] * k}x{wh[1] * k}"


# A tier's prose is written for someone READING ART_PROMPTS.md, and only some of
# it is art direction. The rest addresses the operator — which files are computed
# instead of painted, which installer takes the sheet, why a decision was made —
# and pasting that into a prompt is worse than dropping it: tier 0 was sending
# "DO NOT GENERATE the nine-slices ... They come out of tools/gen_ui_kit.gd" to a
# generator whose entire job was to generate, and tier 4 was demanding three
# sheets inside a request for one. Filtered per SENTENCE, because the two kinds
# sit in the same paragraph. These markers never appear in real art direction.
OPERATOR_PROSE = re.compile(
    r"`|\(D\d+\)|\.gd\b|DO NOT GENERATE|\bTier \S|\bbelow\b|\bcomputed\b"
    r"|\binstaller\b|\bgenerator\b|\blicensed\b|\brequest\b",
    re.I,
)


def art_direction(prose: str) -> str:
    """Keep only the sentences of a tier's prose that direct the painting."""
    keep = [s for s in re.split(r"(?<=[.!?])\s+", prose) if not OPERATOR_PROSE.search(s)]
    return " ".join(keep).strip()


class Tier:
    def __init__(self, key: str, title: str) -> None:
        self.key = key
        self.title = title
        self.preamble: list[str] = []
        self.rows: list[tuple[str, str]] = []
        self.sizes: dict[str, str] = {}   # save-as path -> that file's target size
        self.install = ""
        self.grid = ""    # a sheet tier's rows x cols and its spare-cell rule
        self.sheet = False

    @property
    def direction(self) -> str:
        """The tier's prose with the operator-facing sentences taken out."""
        return art_direction(" ".join(self.preamble))

    @property
    def size(self) -> str:
        return TIER_RULES.get(self.key, {}).get("size", "1024x1024")

    def _row_size(self, name: str) -> str | None:
        """The target size of the row whose save-as basename is `name`."""
        for path, size in self.sizes.items():
            if pathlib.PurePosixPath(path).name == name:
                return size
        return None

    def shape_of(self, name: str) -> str:
        """The shape to ASK for, per file. Falls back to the tier default when the
        row carries no size, or when its aspect matches the tier's anyway — so the
        tiers that were already right keep the exact wording they had."""
        size = self._row_size(name)
        if size is None or aspect_words(size) == ASPECT.get(self.size, self.size):
            return ASPECT.get(self.size, self.size)
        return aspect_words(size)

    def size_of(self, name: str) -> str:
        """Same rule, for the API route's `size` parameter."""
        size = self._row_size(name)
        if size is None or aspect_words(size) == ASPECT.get(self.size, self.size):
            return self.size
        return gen_size(size)

    @property
    def groups(self) -> list[tuple[str, str]]:
        """Sub-sheets for tiers the doc splits (tier 4); empty otherwise."""
        return TIER_RULES.get(self.key, {}).get("groups", [])

    def __repr__(self) -> str:
        return f"<Tier {self.key} {len(self.rows)} files>"


def parse_prompts(text: str) -> tuple[str, list[Tier]]:
    """Pull the shared style block and every tier's subjects out of the sheet."""
    fences = re.findall(r"```\n(.*?)```", text, re.S)
    if not fences:
        raise SystemExit("no fenced style block found in ART_PROMPTS.md")
    style = fences[0].strip()

    tiers: list[Tier] = []
    current: Tier | None = None
    for line in text.splitlines():
        heading = re.match(r"^## Tier (\S+)\s+[—-]\s+(.*)$", line)
        if heading:
            current = Tier(heading.group(1), heading.group(2).strip())
            tiers.append(current)
            continue
        if current is None:
            continue

        # Two columns (save as | subject) or three (save as | size | subject). The
        # size column is what makes the shape per-file; a row without one falls back
        # to the tier default, so an older sheet still parses.
        row = re.match(r"^\|\s*`([^`]+)`\s*\|\s*(.*?)\s*\|\s*$", line)
        if row:
            path, rest = row.group(1), row.group(2)
            parts = [c.strip() for c in rest.split("|")]
            if len(parts) >= 2 and parse_size(parts[0]):
                current.sizes[path] = parts[0]
                subject = parts[-1]
            else:
                subject = rest
            # A re-roll row lists the same file twice: once in the "what is wrong"
            # table and once in the subject table. Keep the LAST, which is the subject.
            current.rows = [r for r in current.rows if r[0] != path]
            current.rows.append((path, subject))
            continue
        # Checked BEFORE the install line: in the sheet tiers both live on one
        # line ("...as ONE image, not 7. ... Install: `godot ...`").
        if "as ONE image" in line:
            current.sheet = True
        if "install_" in line and "godot" in line:
            match = re.search(r"godot --headless[^`]*", line)
            current.install = (match.group(0) if match else line).strip().strip("`")
            # The same line carries the GRID — how many rows and columns, and what to
            # do with the spare cells — and that half is art direction, not operator
            # prose. Dropping the whole line dropped it: tier 1c came back as nine
            # stone tiles with its seven symbols scattered over cells 0-3, 5, 6 and 8,
            # and tier 1d came back with 25 glyphs where 21 were asked for, because
            # neither prompt ever said the grid. Both then install one cell out, which
            # is 21 correct drawings on 21 wrong meanings (D112). The bold count that
            # opens the line IS operator prose ("as ONE image, not 7") and goes.
            head = re.sub(r"\*\*[^*]*\*\*", "", line.split("Install:")[0]).strip()
            if head:
                current.grid = head
            continue
        stripped = line.strip()
        # Skip table chrome, the not-for-a-generator notes, and the count line.
        if (
            stripped
            and not stripped.startswith("|")
            and not stripped.startswith("*")
            and not stripped.startswith("#")
        ):
            current.preamble.append(stripped)
    return style, tiers


def compose(style: str, tier: Tier, subject: str) -> str:
    """Style block verbatim, then tier-specific direction, then one subject."""
    parts = [style]
    if tier.direction:
        parts.append(tier.direction)
    parts.append(subject)
    return "\n\n".join(parts)


def compose_sheet(style: str, tier: Tier, rows: list[tuple[str, str]]) -> str:
    cells = "\n".join(f"{i + 1}. {subject}" for i, (_, subject) in enumerate(rows))
    parts = [style]
    if tier.direction:
        parts.append(tier.direction)
    # The grid FIRST, because "a grid containing 21 cells" is not a geometry and a
    # model handed no rows and columns picks its own — then fills the ones the
    # subject list did not reach.
    if tier.grid:
        parts.append(tier.grid)
    parts.append(
        f"A single grid image containing {len(rows)} filled cells, in this exact "
        f"order left to right then top to bottom. Nothing touching a cell edge.\n"
        f"{cells}"
    )
    return "\n\n".join(parts)


# Mirrors FAMILIES in tools/install_cutouts.gd. A tier whose targets live in one
# of these directories installs with that tool; the sheet sets say so themselves
# via the Install: line ART_PROMPTS.md carries.
CUTOUT_FAMILIES = {"enemies", "relics", "powers", "cards"}

# Mirrors KIT in tools/install_chrome.gd, for the same reason and with the same
# hazard: this is a second copy of a list, and a name added there and not here goes
# quiet rather than loud. It is by NAME and not by the `ui/` directory because the
# directory is not the question — tier 7's logo, splash and cursors are also `ui/`
# and genuinely have no installer, so a directory rule would send someone to a tool
# that would refuse all four. Until D112 the sheet told the operator that nothing
# covered ANY of these, which is how the six HUD files got matted by hand.
CHROME_NAMES = {
    "dropdown_arrow", "slider_grabber", "scrollbar_grabber",
    "checkbox_on", "checkbox_off",
    "energy_orb_full", "energy_orb_empty", "target_ring",
    "orb_glow", "card_glow", "card_back",
}


def install_hints(tier: Tier, jobs: list[tuple[str, str]]) -> list[str]:
    """The command(s) that take this tier's downloads into assets/art/."""
    if tier.groups:
        # Tier 4 names its installer mid-paragraph without the word `godot`, so
        # the Install: parse misses it — but each group label IS the set name.
        return [
            f"godot --headless --script tools/install_sheet.gd -- {label} {name}"
            for (label, _), (name, _) in zip(tier.groups, jobs)
        ]
    if tier.install:
        return [tier.install]
    families = {pathlib.PurePosixPath(p).parent.name for p, _ in tier.rows}
    hints = [
        f"godot --headless --script tools/install_cutouts.gd -- {f} <staging dir>"
        for f in sorted(families & CUTOUT_FAMILIES)
    ]
    # Backdrops sit at the ROOT of assets/art/, so they have no family directory for
    # the rule above to match on and the sheet told you no installer covered them —
    # which is wrong, and would have had someone hand-copying a 1280x720 file into
    # place. They are recognised by the one thing that does identify them: the
    # `bg_` prefix the loader resolves them by (D109).
    if any(pathlib.PurePosixPath(p).name.startswith("bg_") for p, _ in tier.rows):
        hints.append(
            "godot --headless --script tools/install_backdrops.gd -- <staging dir>"
        )
    if any(pathlib.PurePosixPath(p).stem in CHROME_NAMES for p, _ in tier.rows):
        hints.append(
            "godot --headless --script tools/install_chrome.gd -- <staging dir>"
        )
    return hints


def build_jobs(style: str, tier: Tier, only: str | None) -> list[tuple[str, str]]:
    """(filename, prompt) pairs for a tier — ONE per sheet where the tier is a sheet.

    Shared by the API route and the browser route so the two cannot drift: a
    browser prompt that differs from the posted one is a second dialect, which
    is the failure rule 1 exists to prevent.
    """
    if tier.groups:
        jobs = []
        for label, prefix in tier.groups:
            rows = [
                r for r in tier.rows
                if pathlib.PurePosixPath(r[0]).name.startswith(prefix)
            ]
            if rows:
                jobs.append((f"sheet_{label}.png", compose_sheet(style, tier, rows)))
        return jobs
    if tier.sheet:
        return [(f"sheet_tier{tier.key}.png", compose_sheet(style, tier, tier.rows))]
    return [
        (pathlib.PurePosixPath(path).name, compose(style, tier, subject))
        for path, subject in tier.rows
        if not only or only in path
    ]


def render_browser(style: str, tiers: list[Tier], only: str | None) -> str:
    """A copy-paste sheet for hand-driving a chat UI, with no API key involved.

    The prompts are byte-identical to the posted ones; what this adds is the
    three things the HTTP body carries that a chat box cannot — the reference
    image, the output size, and the filename the installers expect.
    """
    live = [t for t in tiers if t.rows]
    jobs_by_tier = [(t, build_jobs(style, t, only)) for t in live]
    jobs_by_tier = [(t, j) for t, j in jobs_by_tier if j]
    pastes = sum(len(j) for _, j in jobs_by_tier)
    files = sum(len(t.rows) for t, _ in jobs_by_tier)

    out: list[str] = []
    w = out.append
    w("<!-- GENERATED by tools/gen_pollinations.py --browser — do not edit by hand. -->")
    w("")
    w("# Browser prompt sheet")
    w("")
    w(f"**{pastes} pastes, covering {files} files.** Sheet tiers are one paste each.")
    w("")
    w("## Before the first paste")
    w("")
    w(
        f"1. Start ONE chat and **attach `{STYLE_REFERENCE.relative_to(REPO)}`** to it. "
        "Every prompt below says *the attached reference image*, so a chat without "
        "it silently drops the style bible (rule 2, D100)."
    )
    w(
        "2. Keep using that same chat. Re-attach the reference if the palette starts "
        "drifting — chat context decays across a long session in a way an HTTP "
        "request does not."
    )
    w(
        "3. Paste each block **unchanged**. Do not improve it between images; its "
        "job is to be identical every time (rule 3)."
    )
    w(
        "4. Download each result and rename it to the `save as` filename, all into "
        "one staging directory per tier. Nothing goes into `assets/art/` by hand — "
        "the installers matte, trim, anchor and resize, and the filename is the "
        "wiring (D73)."
    )
    w(
        "5. Take the chat UI's corner watermark off the whole staging directory "
        "**before** the installer touches it: `godot --headless --script "
        "tools/strip_sparkle.gd -- <staging dir>`. It finds the stamp by "
        "intersecting the images against each other, so it needs the batch intact "
        "and unresized, and it needs at least four of them. A matted cutout would "
        "survive without this — the corner is field and the matte takes it — but "
        "anything installed opaque or as a bloom ships the stamp (D112)."
    )
    w("")
    w("| tier | pastes | shape | title |")
    w("|---|---|---|---|")
    for tier, jobs in jobs_by_tier:
        shapes = sorted({tier.shape_of(n) for n, _ in jobs})
        w(f"| {tier.key} | {len(jobs)} | {', '.join(shapes)} | {tier.title} |")
    w("")

    for tier, jobs in jobs_by_tier:
        w(f"## Tier {tier.key} — {tier.title}")
        w("")
        shapes = sorted({tier.shape_of(n) for n, _ in jobs})
        # "each a square image" is a lie the moment one file in the tier is not, and
        # tier 0 and tier 7 both mix shapes — so the shape is stated per paste below
        # and only summarised here.
        w(f"{len(jobs)} paste{'s' if len(jobs) != 1 else ''}, "
          + (f"each {shapes[0]}." if len(shapes) == 1 else "shape stated per paste."))
        hints = install_hints(tier, jobs)
        w("")
        if hints:
            w("Install once the whole tier is downloaded:")
            w("")
            w("```bash\n" + "\n".join(hints) + "\ngodot --headless --import\n```")
        else:
            w(
                "No installer covers these — they are loose `ui/` cutouts. Matte and "
                "place them with the same care the installers take, then re-import."
            )
        w("")
        for name, prompt in jobs:
            w(f"### `{name}`")
            w("")
            w("```")
            w(f"Generate {tier.shape_of(name)}.")
            w("")
            w(prompt)
            w("```")
            w("")
    return "\n".join(out)


def find_key() -> str:
    key = (os.environ.get("POLLINATIONS_API_KEY") or "").strip()
    if not key and KEY_FILE.is_file():
        key = KEY_FILE.read_text().strip()
    if not key:
        raise SystemExit(
            "No Pollinations API key. Create one at https://enter.pollinations.ai/keys,\n"
            f"then: install -m 600 /dev/stdin {KEY_FILE} <<< 'pk_...'\n"
            "(or export POLLINATIONS_API_KEY)"
        )
    return key


def post_multipart(prompt: str, model: str, size: str, key: str) -> bytes:
    """POST /v1/images/edits as multipart so the LOCAL style reference can be sent.

    The JSON form of this endpoint takes reference images as URLs only, which
    cannot reach a file inside the repo — hence multipart.
    """
    ref = STYLE_REFERENCE.read_bytes()
    ref_mime = mimetypes.guess_type(STYLE_REFERENCE.name)[0] or "image/png"
    boundary = f"----pollinations{uuid.uuid4().hex}"
    body = bytearray()

    def field(name: str, value: str) -> None:
        body.extend(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n".encode()
        )

    field("prompt", prompt)
    field("model", model)
    field("size", size)
    field("n", "1")
    field("response_format", "b64_json")
    body.extend(
        f'--{boundary}\r\nContent-Disposition: form-data; name="image"; '
        f'filename="{STYLE_REFERENCE.name}"\r\n'
        f"Content-Type: {ref_mime}\r\n\r\n".encode()
    )
    body.extend(ref)
    body.extend(f"\r\n--{boundary}--\r\n".encode())

    req = urllib.request.Request(
        ENDPOINT,
        data=bytes(body),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            # Cloudflare answers urllib's default UA with 403 "error code: 1010"
            # before the request reaches the API, which reads like a bad key.
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:400]
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc

    entries = payload.get("data") or []
    if not entries:
        raise RuntimeError(f"no image in response: {json.dumps(payload)[:300]}")
    entry = entries[0]
    if entry.get("b64_json"):
        return base64.b64decode(entry["b64_json"])
    if entry.get("url"):
        with urllib.request.urlopen(entry["url"], timeout=600) as resp:
            return resp.read()
    raise RuntimeError(f"response had neither b64_json nor url: {list(entry)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tier", help="tier key, e.g. 2, 3, 6a")
    ap.add_argument("--out", help="staging directory to write into")
    ap.add_argument("--only", help="substring filter on the target filename")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--limit", type=int, help="stop after N images")
    ap.add_argument("--list", action="store_true", help="show tiers and exit")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="compose and print prompts without calling the API (needs no key)",
    )
    ap.add_argument(
        "--browser",
        action="store_true",
        help="emit a copy-paste sheet for a chat UI; all tiers unless --tier "
        "(needs no key, makes no request)",
    )
    args = ap.parse_args()

    style, tiers = parse_prompts(PROMPTS.read_text())
    by_key = {t.key: t for t in tiers}

    if args.list:
        print(f"style block: {len(style)} chars")
        print(f"reference:   {STYLE_REFERENCE.relative_to(REPO)}")
        print(f"{'tier':6} {'files':>5}  {'gen size':10} {'mode':8} title")
        for t in tiers:
            if not t.rows:
                continue
            mode = f"{len(t.groups)} sheets" if t.groups else ("1 sheet" if t.sheet else "-")
            print(f"{t.key:6} {len(t.rows):5}  {t.size:10} {mode:8} {t.title}")
        total = sum(len(t.rows) for t in tiers)
        live = len([t for t in tiers if t.rows])
        print(f"\n{total} generatable files across {live} tiers")
        return 0

    if args.browser:
        chosen = tiers
        if args.tier:
            if args.tier not in by_key or not by_key[args.tier].rows:
                ap.error(f"unknown or empty tier {args.tier!r}; try --list")
            chosen = [by_key[args.tier]]
        if not STYLE_REFERENCE.is_file():
            raise SystemExit(f"style reference missing: {STYLE_REFERENCE}")
        sheet = render_browser(style, chosen, args.only)
        if args.out:
            path = pathlib.Path(args.out).expanduser()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(sheet + "\n")
            print(f"wrote {path}", file=sys.stderr)
        else:
            print(sheet)
        return 0

    if not args.tier:
        ap.error("--tier is required (or use --list)")
    tier = by_key.get(args.tier)
    if tier is None or not tier.rows:
        ap.error(f"unknown or empty tier {args.tier!r}; try --list")

    if not STYLE_REFERENCE.is_file():
        raise SystemExit(f"style reference missing: {STYLE_REFERENCE}")
    if args.model in TEXT_ONLY_MODELS:
        raise SystemExit(
            f"{args.model} is text-only and cannot accept the style reference, which "
            "ART_PROMPTS.md rule 2 requires on every request. Use a reference-capable "
            "model such as nanobanana-2 or seedream5 (D100)."
        )

    jobs = build_jobs(style, tier, args.only)
    if tier.groups:
        print(
            f"tier {tier.key} installs as {len(jobs)} separate SHEETS: "
            + ", ".join(n for n, _ in jobs)
        )
    elif tier.sheet:
        print(f"tier {tier.key} is a SHEET tier: {len(tier.rows)} cells in one image")
    if args.limit:
        jobs = jobs[: args.limit]
    if not jobs:
        raise SystemExit("nothing matched --only")

    if args.dry_run:
        for name, prompt in jobs:
            print("=" * 72)
            print(f"{name}   [{tier.size_of(name)}, model={args.model}, ref={STYLE_REFERENCE.name}]")
            print("-" * 72)
            print(prompt)
        print("=" * 72)
        print(f"{len(jobs)} prompts composed. No API calls made.")
        if tier.install:
            print(f"install with: {tier.install}")
        return 0

    if not args.out:
        raise SystemExit("--out is required unless --dry-run")
    out = pathlib.Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    key = find_key()

    wrote, failed = 0, 0
    for i, (name, prompt) in enumerate(jobs, 1):
        print(f"[{i}/{len(jobs)}] {name} ... ", end="", flush=True)
        try:
            data = post_multipart(prompt, args.model, tier.size_of(name), key)
        except Exception as exc:  # noqa: BLE001 - report and keep going
            print(f"FAIL {exc}")
            failed += 1
            continue
        (out / name).write_bytes(data)
        print(f"{len(data):,} bytes")
        wrote += 1

    # The receipt is what stops a later run mixing generators (rule 1).
    (out / "GENERATED_BY.json").write_text(
        json.dumps(
            {
                "model": args.model,
                "tier": tier.key,
                "title": tier.title,
                "size": tier.size_of(name),
                "style_reference": str(STYLE_REFERENCE.relative_to(REPO)),
                "endpoint": ENDPOINT,
                "wrote": wrote,
                "failed": failed,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"\nwrote {wrote}, failed {failed} -> {out}")
    if tier.install:
        print(f"install with: {tier.install}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

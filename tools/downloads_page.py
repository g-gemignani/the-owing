#!/usr/bin/env python3
"""Build the downloads page: every version of the game that can still be downloaded.

    tools/downloads_page.py [outdir]        # default: site/

Writes `<outdir>/index.html`, self-contained — no fonts, no scripts, no CDN. It is
published to GitHub Pages by the `pages` job in `.github/workflows/ci.yml`, and it is
NOT committed: it is a rendering of the releases API, so a copy in the tree would be a
second statement of a fact the API already owns, wrong from the next release onward.

Why a page at all, when GitHub already lists releases. Three things /releases cannot do,
and each of them is the reason a player closes the tab:

  * it does not separate a version somebody chose to publish from the rolling build of
    `main`. Both are "a release", and the newest thing on the page is the one that is
    not meant to be the default;
  * every asset row is a filename and a byte count. Which one a Windows machine wants
    is a guess unless you already know what `x86_64` means;
  * the notes are release notes — written for somebody following the project, not for
    somebody who wants the game.

The sizes and the dates come from the API rather than from anything typed, for D207's
reason: a number that is only true on the day it is written is the D34 shape in a
document, and the copy nobody re-runs is the one the reader believes.
"""

import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

REPO = os.environ.get("DOWNLOADS_REPO", "g-gemignani/the-owing")

# The rolling build of `main`, under a tag of its own. NOT called `main`: a git tag with
# the same name as a branch makes every `git checkout main` and `git show main` in the
# repository ambiguous, and git resolves that ambiguity in the branch's favour silently.
MAIN_TAG = "main-latest"

# Commonest platform first, not alphabetical — a reader is looking for their own machine.
# Keyed by the asset filename, which is what CI uploads, so a platform that stops being
# built leaves the page by being absent rather than by somebody remembering.
PLATFORMS = [
    ("TheOwing-windows-x86_64.zip", "Windows", "Unzip and run TheOwing.exe"),
    ("TheOwing-macos-universal.zip", "macOS", "Unzip, then right-click the app and choose Open"),
    ("TheOwing-linux-x86_64.zip", "Linux", "Unzip, then chmod +x TheOwing.x86_64"),
    ("TheOwing-android.apk", "Android", "Copy it to the phone and tap it. Android 7+"),
]
ORDER = {name: i for i, (name, _, _) in enumerate(PLATFORMS)}
LABEL = {name: label for name, label, _ in PLATFORMS}
OPENING = {name: how for name, _, how in PLATFORMS}


def fetch():
    """Every release, newest first. `gh` when it is here, plain HTTPS otherwise.

    Unauthenticated works because the repository is public; a token is used when the
    environment has one purely for the rate limit, which a CI runner shares with every
    other job on its IP.
    """
    url = "https://api.github.com/repos/%s/releases?per_page=100" % REPO
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if token:
        req.add_header("Authorization", "Bearer %s" % token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except Exception as exc:  # noqa: BLE001 - the fallback is the point
        print("releases API failed (%s), trying gh" % exc, file=sys.stderr)
        out = subprocess.run(
            ["gh", "api", "repos/%s/releases?per_page=100" % REPO],
            capture_output=True, text=True, check=True).stdout
        return json.loads(out)


def mib(n):
    """Whole megabytes. Coarse on purpose: an exact byte count moves on every push and
    would make the page look like it changed when nothing did."""
    return (n + 524288) // 1048576


def when(iso):
    if not iso:
        return ""
    return datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").strftime("%-d %b %Y")


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def assets_of(rel):
    """The platform assets, in reading order, with anything unrecognised dropped.

    Dropped rather than listed: the release also carries whatever CI happened to stage,
    and a page whose job is "pick your machine" is made worse by a row nobody can use.
    """
    got = [a for a in rel.get("assets", []) if a["name"] in ORDER]
    got.sort(key=lambda a: ORDER[a["name"]])
    return got


def render_assets(rel):
    got = assets_of(rel)
    if not got:
        return '<p class="none">No downloads on this one — the builders did not finish.</p>'
    rows = []
    for a in got:
        rows.append(
            '<a class="dl" href="%s" title="%s">'
            '<span class="plat">%s</span>'
            '<span class="meta">%s&thinsp;MB</span></a>'
            % (esc(a["browser_download_url"]), esc(OPENING[a["name"]]),
               esc(LABEL[a["name"]]), mib(a["size"])))
    return '<div class="dls">%s</div>' % "".join(rows)


def render_release(rel, kind):
    tag = rel["tag_name"]
    head = esc(rel.get("name") or tag)
    date = when(rel.get("published_at") or rel.get("created_at"))
    return (
        '<article class="rel %s">'
        '<h3>%s <a class="notes" href="%s">notes</a></h3>'
        '<p class="date">%s</p>%s</article>'
        % (kind, head, esc(rel["html_url"]), esc(date), render_assets(rel)))


PAGE = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The Owing &mdash; downloads</title>
<meta name="description" content="Every downloadable version of The Owing, a card game about debt.">
<style>
:root {{
  --bg: #f7f5f2; --fg: #1b1917; --dim: #5d564f; --line: #ddd6cd;
  --card: #fffdfa; --accent: #7a2e1e; --warn: #6b4b12; --warnbg: #fdf4dd;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #14120f; --fg: #ece7e0; --dim: #a29a90; --line: #322c25;
    --card: #1c1916; --accent: #e0a08a; --warn: #e5c98a; --warnbg: #241d0f;
  }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.6 ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
main {{ max-width: 46rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem; }}
h1 {{ font-size: 1.9rem; margin: 0 0 .25rem; letter-spacing: -.02em; }}
h2 {{ font-size: 1.1rem; margin: 2.5rem 0 .25rem; text-transform: uppercase;
  letter-spacing: .09em; color: var(--dim); }}
h3 {{ font-size: 1.15rem; margin: 0 0 .1rem; }}
p {{ margin: .4rem 0; }}
a {{ color: var(--accent); }}
.lede {{ color: var(--dim); margin-bottom: 1.5rem; }}
.sub {{ color: var(--dim); font-size: .92rem; margin: .1rem 0 1rem; }}
.rel {{ border: 1px solid var(--line); background: var(--card);
  border-radius: .6rem; padding: 1rem 1.1rem; margin: .9rem 0; }}
.rel.main {{ border-style: dashed; }}
.date {{ color: var(--dim); font-size: .88rem; margin: 0 0 .7rem; }}
.notes {{ font-size: .8rem; font-weight: 400; text-decoration: none;
  border-bottom: 1px solid currentColor; margin-left: .4rem; }}
.dls {{ display: flex; flex-wrap: wrap; gap: .5rem; }}
.dl {{ display: flex; flex-direction: column; text-decoration: none; color: inherit;
  border: 1px solid var(--line); border-radius: .45rem; padding: .45rem .8rem;
  min-width: 6.5rem; }}
.dl:hover {{ border-color: var(--accent); color: var(--accent); }}
.plat {{ font-weight: 600; font-size: .95rem; }}
.meta {{ color: var(--dim); font-size: .8rem; }}
.dl:hover .meta {{ color: inherit; }}
.warn {{ background: var(--warnbg); border-left: 3px solid var(--warn);
  padding: .8rem 1rem; border-radius: 0 .4rem .4rem 0; margin: 1rem 0; }}
.none {{ color: var(--dim); font-size: .9rem; margin: 0; }}
footer {{ margin-top: 3rem; padding-top: 1.2rem; border-top: 1px solid var(--line);
  color: var(--dim); font-size: .85rem; }}
</style></head>
<body><main>

<h1>The Owing &mdash; downloads</h1>
<p class="lede">A card game about debt. Free, nothing to buy inside it, no internet needed.
Pick a version, pick your machine. <a href="https://github.com/{repo}">The project</a>.</p>

<div class="warn"><strong>Your computer will warn you the first time.</strong> Nothing here is
code-signed, which needs a paid developer identity per platform. Windows shows
<em>More info &rarr; Run anyway</em>; on macOS right-click the app and choose <em>Open</em>;
on Android allow an app from outside the Play Store.</div>

<h2>Stable</h2>
<p class="sub">Cut from a tag &mdash; a state somebody decided to name. The top one is what the
README links to. Older ones stay here and stay downloadable; a save carries its own version
and is migrated forward, so going back a version is not always possible.</p>
{stable}

<h2>Build of main</h2>
<p class="sub">The newest commit that passed the suite. It is <strong>replaced on every push</strong>,
so this is the only build of <code>main</code> that exists &mdash; the tagged versions above are
the ones that are kept. Expect half-finished work: this is what is being built today, not what
was decided to be worth publishing.</p>
{rolling}

<footer>
Every build stamps its own commit &mdash; the title screen shows it and Settings spells it out
as <code>v&lt;version&gt;+&lt;date&gt;.&lt;commit&gt;</code>. Quote that in a bug report; the
filenames are identical in every release.<br>
On NixOS the Linux binary needs <code>steam-run</code>. See
<a href="https://github.com/{repo}/blob/main/BUILD.md">BUILD.md</a>.<br>
Generated from the releases of <a href="https://github.com/{repo}/releases">{repo}</a> on {built}.
</footer>

</main></body></html>
"""


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "site"
    releases = [r for r in fetch() if not r.get("draft")]

    rolling = [r for r in releases if r["tag_name"] == MAIN_TAG]
    # A version is a `v*` TAG (D227), and the page states that rule rather than inverting it.
    # "Everything that is not the rolling tag" was the first cut and it is wrong in both
    # directions: the repository still carries a `latest` release from the channel D227
    # removed, which would have been listed as a stable version four versions out of date,
    # and any future channel would join it. Filtered on the tag and not on `prerelease`,
    # because that flag is a mechanism — a stable version demoted when a newer one landed is
    # still a version somebody published.
    stable = [r for r in releases
              if r["tag_name"].startswith("v") and r["tag_name"] != MAIN_TAG]

    stable_html = "".join(render_release(r, "stable") for r in stable) \
        or '<p class="none">No tagged version yet.</p>'
    rolling_html = "".join(render_release(r, "main") for r in rolling) \
        or '<p class="none">No build of <code>main</code> yet — the next push to it makes one.</p>'

    html = PAGE.format(
        repo=REPO, stable=stable_html, rolling=rolling_html,
        built=datetime.now(timezone.utc).strftime("%-d %b %Y"))

    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "index.html")
    with open(path, "w") as f:
        f.write(html)
    print("downloads page: %s (%d stable, %d rolling)" % (path, len(stable), len(rolling)))


if __name__ == "__main__":
    main()

"""Writes WhatsNewData.lua, the notes the in-game changelog shows (SmoothExperienceBar/WhatsNew.lua), from
CHANGELOG.md: the newest versions' sections, as players read them. scripts/package.ps1 runs it for every build;
run it by hand to try the window in a dev install (the file is not committed).

    python tools/whatsnew_data.py [CHANGELOG.md] [WhatsNewData.lua] [version]

Defaults: the repo's CHANGELOG.md and SmoothExperienceBar/WhatsNewData.lua. With a release version (X.Y.Z, a leading
v allowed), sections for later versions are left out, and that version must have one of its own: it exits 1 if not.
Any other version (a dev build's git describe) keeps them all.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COUNT = 12  # versions kept: the window shows at most 8, the rest is slack


def plain(text):
    """Text as players read it: Markdown's code and bold marks dropped, the lines of one bullet joined."""
    text = text.replace("`", "").replace("**", "")
    return re.sub(r"\s+", " ", text).strip()


def note(text):
    """A note: a bold title at its start, ended by a colon or full stop ("**Reputation Bar**: ..." or
    "**Reputation Bar.** ...") becomes (title, text), for the window to show the title on a line of its own; any
    other note, a bold word in a sentence included, stays a plain string."""
    titled = re.match(r"^\*\*(.+?)([:.]?)\*\*\s*([:.]?)\s*(.*)$", text.strip(), re.S)
    if titled and (titled.group(2) or titled.group(3)) and titled.group(4).strip():
        body = plain(titled.group(4))
        # Under its title, on a line of its own, the text starts a sentence.
        return (plain(titled.group(1)), body[:1].upper() + body[1:])
    return plain(text)


def parse(text):
    """The changelog's versions, newest first: [{"version", "sections": [(title, [note, ...]), ...]}]. Only
    "## X.Y.Z" headings start a version; text before the first one is the file's own introduction, and any other
    "## " heading ends the version."""
    versions, version, section, note_text = [], None, None, None

    def close():
        nonlocal note_text
        if note_text is not None and section is not None:
            section[1].append(note(note_text))
        note_text = None

    for line in text.splitlines():
        number = re.match(r"^##\s+(\d+\.\d+\.\d+)\s*$", line)
        title = re.match(r"^###\s+(.+?)\s*$", line)
        if number:
            close()
            version, section = {"version": number.group(1), "sections": []}, None
            versions.append(version)
        elif line.startswith("## ") or line.startswith("# "):
            close()
            version, section = None, None
        elif version is not None and title:
            close()
            section = (title.group(1), [])
            version["sections"].append(section)
        elif section is not None and re.match(r"^-\s", line):
            close()
            note_text = re.sub(r"^-\s+", "", line)
        elif note_text is not None and re.match(r"^\s+\S", line):
            note_text += " " + line
        else:
            close()
    close()
    return versions


def key(version):
    return tuple(int(n) for n in version.split("."))


def for_release(versions, version):
    """The versions up to a release version, which must have a section; None if it has none."""
    kept = [v for v in versions if key(v["version"]) <= key(version)]
    return kept if kept and kept[0]["version"] == version else None


def lua_string(s):
    out = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + out + '"'


def lua(versions, count=COUNT):
    out = ["local _, ns = ...", "",
           "-- Generated from CHANGELOG.md by tools/whatsnew_data.py for the in-game changelog (WhatsNew.lua).",
           "-- Not committed, not edited by hand.",
           "ns.WhatsNewData = {"]
    for v in versions[:count]:
        out.append("    { version = %s, sections = {" % lua_string(v["version"]))
        for title, notes in v["sections"]:
            out.append("        { %s, {" % lua_string(title))
            for n in notes:
                if isinstance(n, tuple):
                    out.append("            { %s, %s }," % (lua_string(n[0]), lua_string(n[1])))
                else:
                    out.append("            %s," % lua_string(n))
            out.append("        } },")
        out.append("    } },")
    out.append("}")
    return "\n".join(out) + "\n"


def main(argv):
    changelog = argv[1] if len(argv) > 1 else os.path.join(ROOT, "CHANGELOG.md")
    target = argv[2] if len(argv) > 2 else os.path.join(ROOT, "SmoothExperienceBar", "WhatsNewData.lua")
    with open(changelog, encoding="utf-8") as f:
        versions = parse(f.read())
    release = re.match(r"^v?(\d+\.\d+\.\d+)$", argv[3]) if len(argv) > 3 else None
    if release:
        versions = for_release(versions, release.group(1))
        if versions is None:
            sys.stderr.write(f"CHANGELOG.md has no section for {release.group(1)}\n")
            return 1
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(lua(versions))
    newest = versions[0]["version"] if versions else "none"
    print(f"WhatsNewData.lua: {min(COUNT, len(versions))} versions, newest {newest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

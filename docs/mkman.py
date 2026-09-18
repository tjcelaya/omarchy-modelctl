#!/usr/bin/env python3
"""Generate docs/modelctl.1 from docs/MANUAL.md.

MANUAL.md is written in a small Markdown subset so one file serves both GitHub and
man(1): a `# name(section)` title, `##` / `###` headings, paragraphs, `- ` bullets,
fenced code blocks, and inline `code`, **bold** and [links](url). The subset maps
onto scdoc(5); scdoc(1) then emits the roff.

    docs/mkman.py            # writes docs/modelctl.1
    docs/mkman.py --scd      # prints the intermediate scdoc instead
"""
import re, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "MANUAL.md")
OUT = os.path.join(HERE, "modelctl.1")


def inline(text):
    """Markdown inline -> scdoc inline. Escape scdoc's markup characters first."""
    parts = re.split(r"(`[^`]*`)", text)
    out = []
    for p in parts:
        if p.startswith("`") and p.endswith("`") and len(p) >= 2:
            out.append("_" + p[1:-1].replace("_", "\\_").replace("*", "\\*") + "_")
            continue
        p = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: m.group(1) if m.group(2) in m.group(1) else f"{m.group(1)} ({m.group(2)})", p)
        p = p.replace("\\", "\\\\").replace("_", "\\_")
        p = re.sub(r"\*\*(.+?)\*\*", lambda m: "\0" + m.group(1) + "\0", p)   # keep bold markers
        p = p.replace("*", "\\*").replace("\0", "*")
        p = p.replace("...", "…")
        out.append(p)
    return "".join(out)


def convert(md):
    lines = md.splitlines()
    scd = []
    i = 0
    title = re.match(r"#\s+(\S+)\((\d)\)", lines[0])
    if not title:
        sys.exit("MANUAL.md must start with '# name(section)'")
    scd += [f"{title.group(1)}({title.group(2)})", ""]
    i = 1
    para = []

    def flush():
        if para:
            scd.append(inline(" ".join(para)))
            scd.append("")
            para.clear()

    while i < len(lines):
        ln = lines[i]
        if ln.startswith("```"):
            flush()
            scd.append("```")
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                scd.append(lines[i])
                i += 1
            scd += ["```", ""]
        elif ln.startswith("### "):
            flush(); scd += ["## " + inline(ln[4:]).upper() if False else "## " + inline(ln[4:]), ""]
        elif ln.startswith("## "):
            flush(); scd += ["# " + inline(ln[3:]), ""]
        elif ln.startswith("- "):
            flush()
            item = [ln[2:]]
            i += 1
            while i < len(lines) and lines[i].startswith("  ") and not lines[i].startswith("- "):
                item.append(lines[i].strip()); i += 1
            scd.append("- " + inline(" ".join(item)))
            if i >= len(lines) or not lines[i].startswith("- "):
                scd.append("")
            continue
        elif ln.strip() == "":
            flush()
        elif ln.startswith("!["):
            pass  # images have no place in a manpage
        else:
            para.append(ln.strip())
        i += 1
    flush()
    # collapse runs of blank lines
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(scd)).strip() + "\n"
    return text


def main():
    scd = convert(open(SRC, encoding="utf-8").read())
    if "--scd" in sys.argv:
        sys.stdout.write(scd); return
    try:
        roff = subprocess.run(["scdoc"], input=scd, capture_output=True, text=True, check=True).stdout
    except FileNotFoundError:
        sys.exit("mkman: scdoc is not installed (pacman -S scdoc)")
    except subprocess.CalledProcessError as e:
        sys.exit("mkman: scdoc failed:\n" + e.stderr)
    open(OUT, "w", encoding="utf-8").write(roff)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()

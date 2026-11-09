"""Lines in which an R output file of the built R departs from the reference
where the reference agrees with itself:
    python compare-rout.py REFHOME OURHOME REF1 REF2 OUR
REF1 and REF2 are two runs of the reference R, whose R.home() is REFHOME,
OUR the run of the built R, whose R.home() is OURHOME.  A difference
between REF1 and OUR counts only where REF1 and REF2 agree, so temporary
paths and file times, which differ between any two runs, drop out by
themselves.  What differs between the two Rs by design is taken out first:
the R version line and R.home().  So are, as tools::Rdiff does, the timing
lines that begin with "Time" and the output of system.time() and
proc.time() (the header and the line after it), since timings of fast code
come out alike in two runs often enough, and the addresses R prints for
bytecode, environments and external pointers.  Prints the differences that
count and their number last."""
import difflib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
ADDRESS = re.compile(r"<(bytecode|environment|pointer): 0x[0-9a-f]+>")


def lines(path, home):
    homes = [home + "/", home.replace("/", "\\") + "\\", home.replace("/", "\\\\") + "\\\\"]
    out, skip = [], False
    with open(path, encoding="utf-8", errors="replace") as f:
        for l in f:
            l = l.rstrip("\r\n")
            if skip:
                skip = False
                continue
            if re.match(r" *user +system +elapsed *$", l):
                skip = True
                continue
            if l.startswith(("R Under development", "R version", "Time")):
                continue
            for h in homes:
                l = l.replace(h, "R_HOME/")
            out.append(ADDRESS.sub(r"<\1: address>", l))
    return out


refhome, ourhome = sys.argv[1:3]
ref1, ref2 = (lines(p, refhome) for p in sys.argv[3:5])
our = lines(sys.argv[5], ourhome)
# indices of REF1 that REF2 does not reproduce, and the number of lines REF2
# inserts at a point of REF1
unstable, inserted = set(), {}
for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ref1, ref2, autojunk=False).get_opcodes():
    if op in ("replace", "delete"):
        unstable.update(range(i1, i2))
    if op == "insert":
        inserted[i1] = j2 - j1
n = 0
for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ref1, our, autojunk=False).get_opcodes():
    if op == "equal":
        continue
    # excused only where the reference varies as much: an insertion of as
    # many lines at the same point, or unstable lines replaced by no more
    if op == "insert" and inserted.get(i1) == j2 - j1:
        continue
    if op != "insert" and j2 - j1 <= i2 - i1 and all(i in unstable for i in range(i1, i2)):
        continue
    n += 1
    print(f"@@ reference line {i1 + 1}, {op}")
    for l in ref1[i1:i2]:
        print(f"< {l}")
    for l in our[j1:j2]:
        print(f"> {l}")
print(n)

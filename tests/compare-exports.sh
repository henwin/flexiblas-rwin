#!/bin/bash
# The exports of Rblas.dll and Rlapack.dll in the built R against those of
# CRAN's build of the same R:
#   compare-exports.sh OBJDUMP REFBIN BIN
# REFBIN and BIN are the directories with the DLLs.  Rblas.dll must export
# exactly what CRAN's does.  Rlapack.dll exports what CRAN's does less the
# names FlexiBLAS lacks (patches/r/0001): dlarscl2_, dlascl2_ and the module
# procedures of la_xisnan (__la_xisnan_MOD_* from gfortran, _QMla_xisnanP*
# from flang on aarch64, not yet seen); it must leave out no other name and
# add none.
# Prints the differences and exits 1 unless both hold.
objdump=$1 refbin=$2 bin=$3
[ -x "$objdump" ] || { echo "no objdump at $objdump"; exit 1; }
[ -n "$refbin" ] && [ -d "$refbin" ] || { echo "no directory of CRAN's R: '$refbin'"; exit 1; }
exports() {   # exports DLL: one name per line, sorted; GNU and LLVM objdump
    "$objdump" -p "$1" | awk '/\[Ordinal\/Name Pointer\] Table|^Export Table/ {e = 1; next} e && /^$/ {e = 0}
        e && (/^ +[0-9]+ +0x/ || /^[ \t]*\[ *[0-9]+\]/) {print $NF}' | sort
}
status=0
for dll in Rblas Rlapack; do
    exports "$refbin/$dll.dll" > ref-$dll.txt
    exports "$bin/$dll.dll" > $dll.txt
    for f in ref-$dll.txt $dll.txt; do
        [ -s $f ] || { echo "$dll.dll: no exports read into $f"; status=1; }
    done
    missing=$(comm -23 ref-$dll.txt $dll.txt)
    extra=$(comm -13 ref-$dll.txt $dll.txt)
    allowed=
    [ $dll = Rlapack ] && allowed=$(echo "$missing" | grep -E '^(dlarscl2_|dlascl2_|__la_xisnan_MOD_.*|_QMla_xisnanP.*)$')
    other=$(comm -23 <(echo "$missing" | grep .) <(echo "$allowed" | grep .))
    echo "$dll.dll: $(wc -l < $dll.txt) exports, CRAN's $(wc -l < ref-$dll.txt);" \
        "left out as FlexiBLAS lacks them: $(echo $allowed); other left out: $(echo ${other:-none}); added: $(echo ${extra:-none})"
    [ -z "$other" ] && [ -z "$extra" ] || status=1
done
exit $status

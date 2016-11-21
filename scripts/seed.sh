#!/bin/sh
#
# Check AUR and download missing sources and remove
# sources that are obsolete
#
[ -z "$debug" ] && debug=:

fatal() {
	echo "$@" 1>&2
	exit 1
}

[ $# -ne 2 ] && fatal "Usage: $0 <manifest> <srcdir>"

manifest="$1"
srcdir="$2"

[ ! -f "$manifest" ] && fatal "Missing manifest; $manifest"
[ ! -d "$srcdir" ] && mkdir -p "$srcdir"

for d in "$srcdir"/*
do
  [ -d "$d" ] || continue
  if [ -f "$d/PKGBUILD" ] ; then
    grep -q NO_COWER "$d/PKGBUILD" && continue
  fi

  $debug "Marking $d/.t"
  > "$d/.t"
done

exec <"$manifest" || exit 1
while read ln
do
  ln=$(echo "$ln" | sed 's/#.*$//')
  ln=$(echo $ln)
  [ -z "$ln" ] && continue

  $debug ": $ln"

  if [ -f "$srcdir/$ln/.t" ] ; then
    rm -f "$srcdir/$ln/.t"
    continue
  fi
  ( cd "$srcdir" && cower -d "$ln")
done

for d in "$srcdir"/*
do
  [ -f "$d/.t" ] || continue
  echo "Removing $d"
  rm -rf $d
done


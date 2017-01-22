#!/bin/bash
#
# = SEEDER(8)
# :Revision: 1.1
# :Author: A Liu Ly
#
# == NAME
#
# seeder - Sync sources from a manifest.
#
# == SYNOPSIS
#
# *seeder* manifest srcdir
#
# == DESCRIPTION
#
# Check AUR and download missing sources and remove
# sources that are obsolete
#
#--

#### start common stuff ####
version=$( grep '^# :Revision:' "$0" | cut -d: -f3 | tr -d ' ')
set -euf -o pipefail
die() {
  ## Show a message and exit
  ## # USAGE
  ##   die exit_code [msg]
  ## # ARGS
  ## * exit_code -- Exit code
  ## * msg -- Text to show on stderr
  local exit_code="$1"
  shift
  echo "$@" 2>&1
  exit $exit_code
}
debug() {
  ## Will show a message if debug is non-empty
  [ -z "${debug:=y}" ] && return
  echo "$@"
}
manual() {
  ## Show embedded (manify) documentation
  sed -n -e '/^#++$/,$p' "$0" -e '/^#--$/q' "$1" | grep '^#' | sed -e 's/^# //' -e 's/^#//'
  exit 0
}
usage() {
  ## Show usage
  echo 'Usage:'
  sed -n -e '/^#++$/,$p' "$0" -e '/^#--$/q' "$1" | grep '^#' | \
    sed -n -e '/^# == SYNOPSIS/,$p'  | ( read x ; cat ) | \
    sed -e '/^# == /q' | sed 's/^# == .*//' | sed -e 's/^# *//' | \
    (while read l ; do [ -n "$l" ] && echo '    '"$l" ; done) && :
  [ -n "$version" ] && echo "$(basename "$0") v$version"
  exit
}
#### stop common stuff ####

x_opts=()
while [ $# -gt 0 ] ; do
  case "$1" in
    --ignorerepo=*)
      x_opts+=( "$1" )
      ;;
    *)
      break
      ;;
  esac
  shift
done

[ $# -ne 2 ] && usage "$0"
manifest="$1"
srcdir="$2"

[ ! -f "$manifest" ] && die 63 "Missing manifest; $manifest"
[ ! -d "$srcdir" ] && mkdir -p "$srcdir"

#
# Marks all directores for potential deletions
#
for d in $(find "$srcdir" -maxdepth 1 -mindepth 1 -type d)
do
  [ -d "$d" ] || continue
  if [ -f "$d/PKGBUILD" ] ; then
    grep -q NO_COWER "$d/PKGBUILD" && continue
  fi

  debug "Marking $d/.t"
  > "$d/.t"
done

#
# Reads manifest (for potentially new files)
#
sed 's/#.*$//' "$manifest" | (
  while read ln
  do
    [ -z "$ln" ] && continue
    debug ": $ln"

    if [ -f "$srcdir/$ln/.t" ] ; then
      rm -f "$srcdir/$ln/.t"
      continue
    fi
    ( cd "$srcdir" && cower "${x_opts[@]}" -d "$ln")
  done
)

#
# Remove any marked (obsolete) files
#
for d in $(find "$srcdir" -maxdepth 1 -mindepth 1 -type d)
do
  [ -f "$d/.t" ] || continue
  echo "Removing $d"
  rm -rf $d
done


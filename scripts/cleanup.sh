#!/bin/bash
#
# = CLEANUP(8)
# :Revision: 1.1
# :Author: A Liu Ly
#
# == NAME
#
# cleanup - Checks .buildstats and deletes any files not in list
#
# == SYNOPSIS
#
# *cleanup* [--ext=xyz] [dir]
#
# == DESCRIPTION
#
# Check .buildstats and dletes any files not in list.
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

match_file() {
  echo "$files" | (
    while read i
    do
      [ x"$i" = x"$1" ] && return 0
    done
    return 1
  )
  return $?
}

#
# 1. read build stats and make sure all files exists
# 2. read build stats and make sure only files in .buildstats exist
#



exts=()
while [ $# -eq 0 ]
do
  case "$1" in
    --ext=*)
      exts+=( "${1#--ext=}" )
      ;;
    *)
      break
      ;;
  esac
  shift
done

[ $# -eq 0 ] && set - .
[ $# -ne 1 ] && usage "$0"

[ -z "${exts[*]}" ] && exts=( '.pkg.tar' '.pkg.tar.gz' '.pkg.tar.bz2' '.pkg.tar.xz' )

cd "$1" || die 77 "chdir error"
[ ! -f ".buildstats" ] && die 78 "Missing buildstats"

files="$(cut -d: -f3- ".buildstats" | tr ' ' '\n')"
findcmd=( find . -type f)
if [ ${#exts[*]} -eq 1 ] ; then
  findcmd+=( -name '*'"${exts[1]}" )
else
  findcmd+=( '(' )
  o=""
  for i in "${exts[@]}"
  do
    findcmd+=( $o '-name' '*'"$i" )
    o="-o"
  done
  findcmd+=( ')' )
fi
findcmd+=( -printf "%f\n" )

"${findcmd[@]}" | (
  rv=0
  while read l
  do
    echo "$l"
    match_file "$l" && continue
    rm -f$(debug v) "$l"
    rv=1
  done
  exit $rv
) || (
  echo "MUST RE-INDEX"
)



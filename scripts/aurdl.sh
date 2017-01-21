#++
# = AURDL(8)
# :Revision: 1.1
# :Author: A Liu Ly
#
# == NAME
#
# aurdl - Check AUR and download sources that need to be updated...
#
# == SYNOPSIS
#
# *aurdl* [--ignore-repo=name] srcdir [srcdir ...]
#
# == DESCRIPTION
#
# Examine the source directories and updates any that need updating.
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
cnt=0

cleanup() {
  [ -z "${work:-}" ] && return
  [ -d "$work" ] && rm -rf "$work"
}

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

[ $# -eq 0 ] && usage "$0"

for pkg in "$@"
do
  [ -f "$pkg"/PKGBUILD ] || continue
  grep -q NO_COWER "$pkg"/PKGBUILD && continue
  
  pkgname="$(set +euf ; . "$pkg"/PKGBUILD ; echo $pkgname)"
  if [ -z "$pkgname" ] ; then
    echo "$pkg: PKGBUILD missing pkgname"
    continue
  fi
  pkgver="$(. "$pkg"/PKGBUILD ; echo $pkgver-$pkgrel)"  
  aurver="$(echo $(cower -i $pkgname | grep '^Version ' | cut -d: -f2-))"
  if [ -z "$aurver" ] ; then
    echo "$pkgname not found by cower"
    continue
  fi
  debug $pkgname $pkgver - $aurver
  [ "$aurver" = "$pkgver" ] && continue
  
  work="$(mktemp -d -p "$(dirname "$pkg")")"
  ( cd "$work" && cower "${x_opts[@]}" -d "$pkgname" )
  if [ -f "$work/$pkgname/PKGBUILD" ] ; then
    rm -rf "$pkg"
    mv "$work/$pkgname" "$pkg"
    cnt=$(expr $cnt + 1)
  else
    echo "$pkg: Download error"
  fi
  rm -rf "$work"
done

if [ $cnt -eq 0 ] ; then
  echo "No sources updated!"
  exit 1
fi
echo "Updates: $cnt"
exit 0

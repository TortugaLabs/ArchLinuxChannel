#!/bin/sh
#
# Usage:
#
# - mk world (default) : does everything
# - mk init : reads manifest.txt and pre-loads AUR sources
# - mk update : Checks AUR and updates any packages
# - mk build : build packages
#
#
# options:
# - -d : debug on
#
# OBSOLETE
# - mk push : push packages to repo

# hardcoded because we are only using 64 bits...
export CCW_ARCH=x86_64

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


world=$(cd "$(dirname "$0")" && pwd)
[ -z "$world" ] && exit 1
[ -z "${IN_ROOTER:-}" ] && exec "$world/scripts/rooter.sh" "$0" "$@"
scripts="$world/scripts"
cd "$world" || exit 1

[ -z "${name:-}" ] && name="tlabs"
repo=$(readlink -f ..)/$name/x86_64
mkdir -p "$repo"

while [ "$#" -gt 0 ] ; do
  case "$1" in
    -d|--debug)
      export debug=true
      ;;
    *)
      break
      ;;
  esac
  shift
done


if [ "$#" -eq 0 ] ; then
  set - world
fi

init() {
  debug "! initializing sources"
  $scripts/seed.sh --ignorerepo="$name" manifest.txt source
}

update() {
  debug "! update from AUR"
  srcs=$(find source -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
  ( cd source && $scripts/aurdl.sh --ignorerepo="$name" $srcs )
}

build() {
  debug "! Building sources"
  (
    cd source || exit
    sources=$(find . -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
    $scripts/ccw.sh depsort $sources | $scripts/builder.sh "$repo" "$name"
    updscore
  )
}

push() {
  debug "! Push to repo"
  if [ -z "$repo" ] ; then
    echo "Specify repo with --repo= option"
    exit 1
  fi
  if [ -z "$name" ] ; then
    echo "Specify name with --name= option"
    exit 1
  fi
  debug "REPO PATH: $repo"
  debug "REPO NAME: $name"
  $scripts/repoupd.sh $repo $name source/*
}

updscore() {
  local \
    wget="wget -O- -nv" \
    url="http://ow1.localnet/cgi-bin/updstat.cgi?" \
    n="&" \
    app="host=ArchLinuxChannel" \
    ver="version=$(date +%Y.%m)"

  $wget "$url$app$n$ver"
}

world() {
  init
  update || :
  build
  #push
}

for op in "$@"
do
  "$op"
done




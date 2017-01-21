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

[ -z "$debug" ] && debug=:

world=$(cd "$(dirname "$0")" && pwd)
[ -z "$world" ] && exit 1
[ -z "$IN_ROOTER" ] && exec "$world/scripts/rooter.sh" "$0" "$@"
scripts="$world/scripts"
cd "$world" || exit 1

[ -z "$name" ] && name="tlabs"
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
  $debug "! initializing sources"
  $scripts/seed.sh manifest.txt source
}

update() {
  $debug "! update from AUR"
  ( cd source && $scripts/aurdl.sh --ignorerepo="$name" * )
}

build() {
  $debug "! Building sources"
  (
    cd source || exit
    $scripts/ccw.sh depsort * | $scripts/builder.sh "$repo" "$name"
  )
}

push() {
  $debug "! Push to repo"
  if [ -z "$repo" ] ; then
    echo "Specify repo with --repo= option"
    exit 1
  fi
  if [ -z "$name" ] ; then
    echo "Specify name with --name= option"
    exit 1
  fi
  $debug "REPO PATH: $repo"
  $debug "REPO NAME: $name"
  $scripts/repoupd.sh $repo $name source/*
}

world() {
  init
  update
  build
  #push
}

for op in "$@"
do
  "$op"
done




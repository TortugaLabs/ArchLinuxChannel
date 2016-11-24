#!/bin/sh
#
# Usage:
#
# - mk world (default) : does everything
# - mk init : reads manifest.txt and pre-loads AUR sources
# - mk update : Checks AUR and updates any packages
# - mk build : build packages
# - mk push : push packages to repo
#
# options:
# - -d : debug on
#

[ -z "$debug" ] && debug=:

world=$(cd "$(dirname "$0")" && pwd)
[ -z "$world" ] && exit 1
[ -z "$IN_ROOTER" ] && exec "$world/scripts/rooter.sh" "$0" "$@"
scripts="$world/scripts"

while [ "$#" -gt 0 ] ; do
  case "$1" in
    -d|--debug)
      export debug=echo
      ;;
    --repo=*)
      repo=${1#--repo=}
      ;;
    -r)
      repo=${2}
      shift
      ;;
    --repo-name=*)
      name=${1#--repo-name=}
      ;;
    -n)
      name=${2}
      shift
      ;;
    *)
      break
      ;;
  esac
  shift
done

if [ -n "$repo" ] ; then
  repo=$(cd "$repo" && pwd) || exit 1
fi

cd "$world" || exit 1

if [ "$#" -eq 0 ] ; then
  set - world
fi

init() {
  $scripts/seed.sh manifest.txt source
}

update() {
  ( cd source && $scripts/aurdl.sh * )
}

build() {
   ( cd source && $scripts/builder.sh * )
}

push() {
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
  push
}

for op in "$@"
do
  "$op"
done




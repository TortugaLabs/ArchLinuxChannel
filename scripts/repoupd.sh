#!/bin/sh
#
# Check source directories and make sure that any
# built packages are in the target repo
#
# Usage:
#   $0 repo-path [pkgs]
#
[ -z $debug ] && debug=:

if [ $# -lt 2 ] ; then
  echo Usage:
  echo $0 repo-path repo-name srcdirs...
  exit 1
fi

repo="$1" ; shift
if [ ! -d "$repo" ] ; then
  mkdir -p "$repo" || exit 1
fi
repo_name="$1" ; shift

# Clean-up repo
find "$repo" -name '*.pkg.tar.*' -links 1 | (while read pkg
do
  pkgname=$(pacman -Q --file "$pkg" | awk '{print $1}')
  ( cd "$repo" && repo-remove ${repo_name}.db.tar.gz $pkgname )
  rm -f "$pkg"
done)

for pkg in $(for pkg in "$@" ; do [ -f "$pkg"/PKGBUILD ] && echo "$pkg" ; done)
do
  pkgs=$(
    cd "$pkg"
    for f in $(echo *.pkg.tar.*)
    do
      [ -f $f ] && echo $f
    done
  )
  $debug $pkg : $pkgs
  for f in $pkgs
  do
    [ -f "$repo/$f" ] && continue
    ln "$pkg/$f" "$repo/$f"
    (cd $repo && repo-add ${repo_name}.db.tar.gz "$f")
  done
done


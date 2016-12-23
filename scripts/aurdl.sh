#!/bin/sh
#
# Check AUR and download sources that need to be updated...
#
cnt=0
[ -z "$debug" ] && debug=:

cleanup() {
  [ -z "$work" ] && return
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


for pkg in "$@"
do
  [ -f "$pkg"/PKGBUILD ] || continue
  grep -q NO_COWER "$pkg"/PKGBUILD && continue
  
  pkgname="$(. "$pkg"/PKGBUILD ; echo $pkgname)"
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
  $debug $pkgname $pkgver - $aurver
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

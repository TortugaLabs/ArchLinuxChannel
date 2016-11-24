#!/bin/bash
#
# Look into a set of source directories and build anything that is
# pending
#
# Usage: $0 [--32|--64] [pkgs]
#
[ -z "$debug" ] && debug=:
ccmsz=64

while [ $# -gt 0 ] ; do
  case "$1" in
  --64)
    ccmsz=64
    ;;
  --32)
    ccmsz=32
    ;;
  *)
    break
    ;;
  esac
  shift
done

set -o pipefail
tmp=$(mktemp -d) || exit
cleanup() {
  [ -n "$tmp" ] && rm -rf "$tmp"
  if [ -n "$ccm_nuke" ] ; then
    [ -n "$ccm" ] && [ "$ccm_nuke" = yes ] && $ccm n
  fi
}
trap "cleanup" EXIT

$debug ccmsz=$ccmsz

source /usr/share/makepkg/util.sh || exit
if [ $# -eq 0 ] ; then
  echo "Usage: $0 [--32|--64] pkgs"
  exit 1
fi

if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root=sudo
fi

# Use find to avoid ARG_MAX issues.
findsrc() {
    find -- "$@" -maxdepth 1 -type f -name .SRCINFO -print0
}
# XXX: The three functions below could be done in a single awk pass (#177)
gendeps() {
    xargs -0i awk -v FS='[<=>]' '
          /pkgbase/ {
	      B = $2
	      printf("%s\t%s\n", B, B)
	  }
          /^\t(make|check)?depends/ {
	      printf("%s\t%s\n", B, $2)
	  }
          /^$/ {nextfile} # Split package
    ' {}
}

genbase() {
    xargs -0i awk -v FS='[<=>]' '
          /pkgbase/ {B = $2}
          /pkgname/ {printf("%s\t%s\n", $2, B)}
    ' {}
}

# make/depends arrays contain pkgname instead of pkgbase.
# Replace entries accordingly in the output.
basesub() {
    declare -A pkg
    declare name base

    while read -r -u 3 name base; do
        pkg[$name]=$base
    done 3< "$1"

    while read -r name _; do
        if [[ ${pkg[$name]} ]]; then
            printf '%s\n' "${pkg[$name]}"
        fi
    done | tac | awk '!x[$0]++' | tac
}

dmsort() {
    if hash datamash 2>/dev/null; then
        datamash -W check < "$1" >/dev/null || return
    fi

    tsort "$1"
}

aurqueue() {
  findsrc "$@" > "$tmp"/i || return
  gendeps < "$tmp"/i > "$tmp"/deps &
  genbase < "$tmp"/i > "$tmp"/base &
  wait     # XXX: exit code 0
  dmsort "$tmp"/deps | basesub "$tmp"/base | grep -Fxf <(printf '%s\n' "$@") | tac
}

CCMCFG=${CFGFILE:-$HOME/.config/clean-chroot-manager.conf}
$debug CCMCFG=$CCMCFG
chroot_repo="chroot_local"

ccm="$root ccm$ccmsz"
ccm_ready=no
ccm_nuke=no
ccm_preheat=()
cnt=0

for p in "$@"
do
  [ ! -f "$p"/PKGBUILD ] && continue
  [ -f "$p"/.SRCINFO ] && continue
  ( cd "$p" && makepkg --printsrcinfo > .SRCINFO )
done

queue=$(aurqueue "$@")
$debug "IN:     " $*
$debug "ORDERED:" $queue

# Check if we need to build packages
for pkg in $queue
do
  pkgs=$(cd "$pkg" ; n=0 ; for x in *.pkg.tar.* ; do [ -f $x ] && n=$(expr $n + 1) ; done ; echo $n)
  $debug "$pkg : $pkgs"
  
  if [ $pkgs -eq 0 ] ; then
    if [ $ccm_ready = no ] ;then
      if $ccm c ; then
        ccm_nuke=yes
	# Pre-load repo with ...
	local_repo="$(. $CCMCFG && eval echo '$'CHROOTPATH$ccmsz)/root/repo"
	$debug "local_repo=$local_repo"
	[ ! -d "$local_repo" ] && $root mkdir -p "$local_repo"
	for inpkg in "${ccm_preheat[@]}"
	do
		$root cp -a "$inpkg" "$local_repo"
	done
	( cd "$local_repo" && $root repo-add "$chroot_repo.db.tar.gz" *.pkg.tar.* )
	# add a local repo to chroot
	[ -f $(dirname "$local_repo")/etc/pacman.conf ] && $debug "Editing pacman.conf"
	$root sed -i '/\[testing\]/i \
		# Added by clean-chroot-manager\n[chroot_local]\nSigLevel = Never\nServer = file:///repo\n' \
		$(dirname "$local_repo")/etc/pacman.conf
      fi
      ccm_ready=yes
    fi
    ( cd "$pkg" && $ccm s ) && cnt=$(expr $cnt + 1)
  else
    if [ $ccm_ready = no ] ; then
      ccm_preheat+=( $(echo "$pkg"/*.pkg.tar.*) )
    elif [ -n "$local_repo" ] ; then
      pkgs=$(cd "$pkg" ; echo *.pkg.tar.* )
      ( cd "$pkg" && $root cp -a $pkgs "$local_repo" )
      ( cd "$local_repo" && $root repo-add "$chroot_repo.db.tar.gz" $pkgs )
    fi
  fi
done

echo "Builds: $cnt"

[ $cnt -eq 0 ] && exit 1
exit 0


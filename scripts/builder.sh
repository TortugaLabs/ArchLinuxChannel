#!/bin/bash
#++
# = BUILDER(8)
# :Revision: 2.0-arch
# :Author: A Liu Ly
#
# == NAME
#
# builder - Builds a sorted list of packages
#
# == SYNOPSIS
#
# *builder* repodir reponame
#
# == DESCRIPTION
#
# Read from standard input a list of packages to build.
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

##################################################################
# Functions
##################################################################

update_buildstats() {
  local \
    statsfile="$1" \
    pkg="$2" \
    pvr="$3"
  shift 3

  local inp="$(awk -F: '$1 != "'"$pkg"'" { print }' "$statsfile" | grep ':')"
  (
    [ -n "$inp" ] && echo "$inp"
    echo "$pkg:$pvr:$*"
  ) >"$statsfile"
}
getpkg_buildstats() {
  local \
    statsfile="$1" \
    pkg="$2" \
    pvr="$3"
  awk -F: '$1 == "'"$pkg"'" && $2 == "'"$pvr"'" { print $3 }' "$statsfile"
}


##################################################################
# MAIN
##################################################################
main() {
  local \
    chroot_ready=false \
    statsfile="$repo_dir"/.buildstats \
    chroot_pkgs="" \
    local build_dir="$repo_dir/._build"

  [ ! -d "$repo_dir" ] && die 72 "REPO DIR NON EXISTENT"
  
  if [ -f "$repo_dir"/"$repo_name".db.tar.gz ] ; then
    local need_index=false
  else
    local need_index=true
  fi
  [ ! -f "$statsfile" ] && >"$statsfile"
  local new_pkgs=""

  local pkg pvr i
  while read pkg
  do
    [ ! -f "$pkg/PKGBUILD" ] && continue

    pvr=$(
      epoch=0
      set +euf
      . $pkg/PKGBUILD
      [ -z "$pkgver" ] && exit
      [ -z "$pkgrel" ] && exit
       echo "$epoch;$pkgver-$pkgrel"
    )
    if [ -z "$pvr" ] ; then
      echo "$pkg: Missing pkgver|pkgrel" 1>&2
      continue
    fi
    
    local pkgs="$(getpkg_buildstats "$statsfile" "$pkg" "$pvr")"
    if [ -n "$pkgs" ] ;then
      # Already built...
      debug "$pkg $pvr - $pkgs"
      if $chroot_ready ; then
	for i in $pkgs
	do
	  [ -f "$repo_dir/$i" ] && $ccw i "$repo_dir/$i"
	done
      else
	if [ -z "$chroot_pkgs" ] ; then
	  chroot_pkgs="$pkgs"
	else
	  chroot_pkgs="$chroot_pkgs $pkgs"
	fi
      fi
      continue
    fi

    if ! $chroot_ready ; then
      $ccw create || :
      if [ -n "$chroot_pkgs" ] ; then
	for i in $chroot_pkgs
	do
	  $ccw i "$repo_dir/$i"
	done
      fi
      chroot_ready=true
    fi

    [ -d "$build_dir" ] && rm -rf "$build_dir"
    mkdir -p "$build_dir"
    $ccw b --output="$build_dir" "$pkg"
    local output="$(find "$build_dir" -name '*.pkg.tar*' -maxdepth 1 -mindepth 1 -type f -printf '%f\n')"
    if [ -n "$output" ] ; then
      for i in $output
      do
	rm -f "$repo_dir/$i"
        cp -l$(debug v) "$build_dir/$i" "$repo_dir"
      done
      update_buildstats "$statsfile" "$pkg" "$pvr" $output
      need_index=true
      new_pkgs="$new_pkgs $output"
    fi
  done

  if $need_index ; then
    if ! $chroot_ready ; then
      $ccw create || :
      chroot_ready=true
    fi
    (
      cd $repo_dir
      repo-add $repo_name.db.tar.gz $new_pkgs
    )
  fi

  $chroot_ready && $ccw nuke
    
  rm -rf "$build_dir"
}

##################################################################
# Command-line
##################################################################
ccw="$(cd "$(dirname $0)" && pwd)/ccw.sh"
type $ccw >/dev/null || die 68 "$ccw missing"

[ $# -ne 2 ] && usage "$0"

repo_dir="$(readlink -f "$1")"
repo_name="$2"
shift 2

main "$@"

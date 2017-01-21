#!/bin/sh
#++
# = CCW(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# ccw - Cleal Chroot wraper
#
# == SYNOPSIS
#
# *ccw* _global-options_ *op* _args_
#
# == DESCRIPTION
#
# *ccw* provides a wrapper for building packages in a clean chroot.
# The main advantage over the standard `arch-build-scripts` is:
#
# - ccw manages a local repo within the chroot so dependencies that
#   you build are pulled transparently from that local repo.
#
# == GLOBAL OPTIONS
#
# *--arch=* _x86_64|i686_::
#    Architecture to use
# *--scratch-dir=* _path_::
#    Location of chroots.
# *--packager=* name::
#    Packager's name
#
# == COMMANDS
#
# Standard user commands:
#
# *create|c|mkchroot* _[--chroot=x]_::
#    Create a new|clean chroot (template).
# *build|b* [--no-init] [--chroot=chroot] --output=dir [src]::
#    Run makepkg on the specified directory.
#
# Utility commands:
#
# *upgrade|u* [--chroot=x]::
#    Bring chroot to the latest level.
# *depsort* [directories ...]::
#    Sort dependancies.  If no directories specified, it will read
#    from STDIN lines with paths to source folders and/or PKGBUILD's.
#    If directories are provided, it will find in the PKGBUILD files.
#    It will then process the found sources and output an ordered
#    list of packages suitable for building.
# *nuke|n* _[--chroot=x]_::
#    Remove the specified chroots
# *list|l* _[--chroot=x]_::
#    List the packages available in a chroot's local repo.
# *inject|i* _[--chroot=x]_ pkgs::
#    Inject the specified pkgs into a chroot's local repo.
# *delete|d*  _[--chroot=x]_::
#    Delete all the pkgs in a chroot's local repo.
# *help|h*::
#    Show help manual.
#
# == FILES
#
# $HOME/.ccw_prefs::
#    Defaults for the ccw script
#
# == ENVIRONMENT
#
# - CCW_CHROOTS:: chroots directory
# - CCW_ARCH:: Architecture
# - CCW_PACKAGER:: Packager
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
query_pkg() {
  ## Query PKGBUILD file
  ## # USAGE
  ##   query_pkg PKGBUILD [var ...]
  ## # ARGS
  ## * PKGBUILD -- Path to PKGBUILD file
  ## * var -- one or more variables to query
  ## # OUTPUT
  ## Will print the value of `var`.  If multiple `var`s are specified
  ## then they will printed so that the output can be eval'ed.
  ## If no `var` is specified, `pkgname` will be printed.
  ## # RETURNS
  ## 1 if PKGBUILD is not found.
  [ ! -f "$1" ] && return 1
  local pkg="$(readlink -f "$1")" # We do a readlink because "." requires a full path...
  shift

  (
    [ $# -eq 0 ] && set - pkgname
    set +euf # Make the environment as expected by script...
    . "$pkg"
    if [ $# -eq 1 ] ; then
      eval 'var="$'"$1"'"'
      echo $var
    else
      (
	for var in "$@"
	do
	  declare -p "$var"
	done
      ) | sed -e 's/^declare -. //'
    fi
  )
}

create_chroot() {
  ## Create a new chroot from scratch
  ## # USAGE
  ##   create_chroot chroot arch
  ## # ARGS
  ## * chroot -- target chroot
  ## * arch -- architecture (x86_64|i686)
  ## 
  local \
    chroot="$1" \
    x_arch="$2"

  [ -d "$chroot" ] && die 138 "$chroot: already exists"
  $root mkdir -p "$chroot"

  local pkglist="base-devel"
  if [ "$host_arch" = "$x_arch" ] ; then
    $root mkarchroot "$chroot"/root $pkglist
  else
    case "$host_arch" in
      x86_64)
	case "$x_arch" in
	  i686)
	    setarch "i686" mkarchroot \
		-C /usr/share/devtools/pacman-extra.conf \
		-M /usr/share/devtools/makepkg-i686.conf \
		"$chroot"/root $pkglist
	    ;;
	  *)
	    die 93 "$host_arch: Unsupported target $x_arch"
	    ;;
	esac
	;;
      *)
	die 93 "$host_arch: Unsupported target $x_arch"
    esac
  fi

  $root tee "$chroot/.ccw_cfg" <<-EOF
	created=$(date +%s) # $(date +%Y-%m-%d_%H:%M:%S)
	creator=$(id -u -n)
	creator_id=$(id -u)
	x_arch=$x_arch
	EOF

  $root tee -a $chroot/root/etc/sudoers <<-EOF
	%ccw ALL=(ALL) NOPASSWD: ALL
	Defaults env_keep += "http_proxy ftp_proxy https_proxy"
	EOF
	
  $root tee -a $chroot/root/etc/pacman.conf <<-EOF
	# Added by ccw
	[chroot_local]
	SigLevel = Never
	Server = file:///repo

	EOF
  $root mkdir -p $chroot/root/repo
  $root repo-add $chroot/root/repo/chroot_local.db.tar.gz
}


chroot_arch() {
  ## Checks if it is a valid chroot and display its architecture
  ## # USAGE
  ##   chroot_arch chroot
  ## # ARGS
  ## * chroot -- chroot directory to check
  ## # RETURNS
  ## 0 on success, 1 on error
  ## # OUTPUT
  ## The architecture of the chroot
  ##
  [ ! -d "$1" ] && return 1
  [ ! -f "$1"/.ccw_cfg ] && return 1
  ( . "$(readlink -f "$1/.ccw_cfg")" && echo "$x_arch" )
  return $?
}

run_makepkg() {
  ## Run makepkg in a clean chroot
  ## # USAGE
  ##   run_makepkg chroot outdir init src
  local \
    chroot="$1" \
    outdir="$2" \
    init="$3" \
    src="$4"

  local chroot_arch="$(chroot_arch "$chroot")"
  [ -z "$chroot_arch" ] && die 164 "Invalid template directory"
  [  ! -d "$outdir" ] && die 165 "Missing output directory: $outdir"
  
  wsrc="$(mktemp -d -p "$outdir")"
  debug "Creating build directory..."
  cp -a "$src/." "$wsrc"
  # Get rid of any pre-existing pkgs...
  find "$wsrc" -maxdepth 1 -type f -name '*.pkg.tar*' -exec rm -f '{}' ';'

  (
    cd "$wsrc"
    PACKAGER="$packager" nice -19 makechrootpkg $($init && echo -c || :) -u -r "$chroot"
  )
  rv=$?
  (
    [ $rv -ne 0 ] && exit $rv
    pkgs="$(find "$wsrc" -maxdepth 1 -type f -name '*.pkg.tar*')"
    [ -z "$pkgs" ] && exit 1


    echo "$pkgs" | (
      pkgs=""
      while read l
      do
	cp -a "$l" "$outdir"
	$root cp -a "$l" "$chroot/root/repo"
	pkgs="$pkgs $(basename "$l")"
      done
      [ -n "$pkgs" ] && (
	cd "$chroot/root/repo"
	$root repo-add chroot_local.db.tar.gz $pkgs
      )
    )
    exit 0
  )
  rv=$?
  rm -rf "$wsrc"
  return $rv
}

sysupd() {
  local chroot="$(readlink -f "$1" )"
  [ ! -d "$chroot" ] && die 121 "Missing $1 chroot"
  shift
  [ -f /etc/resolv.conf ] && $root cp -L /etc/resolv.conf "${chroot}/root/etc"
  arch-nspawn "$chroot/root" pacman -Syu --noconfirm
}

depsort() {
  local f

  (
    if [ $# -eq 0 ] ; then
      cat
    else
      find "$@" -name PKGBUILD -type f
    fi
  ) | (
    local x_arch="$host_arch"
    while read f
    do
      [ -d "$f" ] && f="$f/PKGBUILD"
      [ x"$(basename "$f")" != x"PKGBUILD" ] && continue

      d=$(dirname "$f")

      (
	local pkgname="" depends=() makedepends=()
	eval "$(set +euf ; query_pkg "$f" pkgname depends makedepends)"
	#x="$(  set +euf ; query_pkg "$f" pkgname depends makedepends)"
	#eval "$x"
	#set +x
	echo "$pkgname $d"
	for s in "${depends[@]}" "${makedepends[@]}"
	do
	  echo "$s $pkgname"
	done
      )
    done
  ) | tsort | (
    while read d
    do
      [ -d "$d" ] && echo "$d"
    done
  )
}

check_envs() {
  local x a b v
  for x in "$@"
  do
    a=$(echo $x | cut -d: -f1)
    b=$(echo $x | cut -d: -f2)

    eval 'v="${'"$a"':-}"'
    [ -z "$v" ] && continue
    eval ${b}'="$v"'
  done
}

default_chroot() {
  echo "$scratch_dir"/chroot-"$x_arch"
}

##################################################################
# Globals
##################################################################

host_arch="$(uname -m)"
case "$host_arch" in
  x86_64) ;;
  i686) ;;
  *) die 45 "Unsupported Host architecture: $host_arch"
esac

scratch_dir=/var/lib/ccw_chroots
x_arch=$host_arch
packager='# unknown #'

type mkarchroot >/dev/null || die 54 "This program requires devtools to be installed"
if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root=sudo
  type $root >/dev/null || die 136 "This program requires sudo to be installed"
fi
cleanup=:
type declare >/dev/null || die 99 "Unsupported shell"


if [ -f $HOME/.ccw_prefs ] ; then
 . $HOME/.ccw_prefs
else
  echo "Creating default configuration file"
  tee $HOME/.ccw_prefs <<-EOF
	#
	# You can usually leave these alone...
	#
	# Directory where to store all CHROOTS
	#scratch_dir=/var/lib/ccw_chroots
	# Default arch (auto-detected)
	#x_arch=\$(uname -m)
	# Packager
	#packager="joe <nobody@nowhere>"
	EOF
fi
check_envs \
  CCW_CHROOTS:scratch_dir \
  CCW_ARCH:x_arch \
  CCW_PACKAGER:packager

##################################################################
# Command line overrides
##################################################################
while [ $# -gt 0 ]
do
  case "$1" in
    --scratch-dir=*)
      scratch_dir=${1#--scratch-dir=}
      ;;
    --arch=*)
      x_arch=${1#--arch=}
      ;;
    --packager=*)
      packager=${1#--packager=}
      ;;
    *)
      break
      ;;
  esac
  shift
done

[ -z "${x_arch:-}" ] && x_arch="$host_arch"
if [ -n "${scratch_dir:-}" ] ; then
  [ ! -d "$scratch_dir" ] && $root mkdir -p "$scratch_dir"
  scratch_dir="$(readlink -f "$scratch_dir" |sed -e 's!/*$!!')"
fi
[ -z "${packager:-}" ] && packager="_empty_"

##################################################################
# User visible commands
##################################################################
op_create() {
  local chroot="$(default_chroot)"

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ -d "$chroot" ] && die 46 "$chroot: template chroot already exists"
  [ $# -ne 0 ] && die 132 "Usage: $0 create [--chroot=x]"
  create_chroot "$chroot" "$x_arch"
}

op_nuke() {
  local chroot="$(default_chroot)"

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [  ! -d "$chroot" ] && exit
  [ ! -f "$chroot/.ccw_cfg" ] && die 132 "Invalid chroot: $chroot"
  $root rm -rf "$chroot"
}

op_upgrade() {
  local chroot=$(default_chroot)
  
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing chroot"
  [ ! -f "$chroot/.ccw_cfg" ] &&  die 48 "$chroot: Invalid chroot"
  sysupd "$chroot"
}

op_ccm() {
  local chroot=$(default_chroot) op="$1" ; shift

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing chroot"
  [ ! -f "$chroot/.ccw_cfg" ] &&  die 48 "$chroot: Invalid chroot"

  case "$op" in
    list|l)
      find "$chroot/root/repo" -type f -name "*.pkg.tar*" -printf '%f\n'
      ;;
    inject|i)
      local pkg pkgs=""
      for pkg in "$@"
      do
	if $root cp $(debug -v) "$pkg" "$chroot/root/repo" ; then
	  pkgs="$pkgs $(basename "$pkg")"
	fi
      done
      [ -n "$pkgs" ] && (
	cd "$chroot/root/repo"
	$root repo-add chroot_local.db.tar.gz $pkgs
      )
      ;;
    delete|d)
      $root find "$chroot/root/repo" -type f -name "*.pkg.tar*" -exec rm -f '{}' ';'
      $root find "$chroot/root/repo" -type f -name "chroot_local.*" -exec rm -f '{}' ';'
      $root repo-add "$chroot"/root/repo/chroot_local.db.tar.gz
      ;;
    *)
      die 50 "Internal error!"
  esac
}

op_build() {
  local chroot="$(default_chroot)"
  local init=true outdir=

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --output=*)
	outdir="$(readlink -f "${1#--output=}"  | sed -e 's!/*$!!')"
	;;
      --no-init)
	init=false
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing chroot"
  [ ! -f "$chroot/.ccw_cfg" ] &&  die 48 "$chroot: Invalid chroot"

  [ $# -eq 0 ] && set - .

  local src rv=0
  
  for src in "$@"
  do
    ( run_makepkg "$chroot" "$outdir" "$init" "$src" ) && continue
    rv=$(expr $rv + 1)
  done
  return $rv
}

##################################################################
# Main
##################################################################

[ $# -eq 0 ] && usage "$0"

op="$1" ; shift
case "$op" in
  c|create|mkchroot)
    op_create "$@"
    ;;
  n|nuke)
    op_nuke "$@"
    ;;
  b|build)
    op_build "$@"
    ;;  
  depsort)
    depsort "$@"
    ;;
  u|upgrade)
    op_upgrade "$@"
    ;;
  l|list|i|inject|d|delete)
    op_ccm "$op" "$@"
    ;;
  h|help)
    manual "$0"
    ;;
  *)
    die 228 "Invalid op $op. Use help"
    ;;
esac



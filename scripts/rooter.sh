#!/bin/sh
#
# Retrieves root permission (authenticates sudo)
# at the start of the script and then keeps
# calling sudo to keep it warm
#
# usage:
#  $0 cmd
#

cleanup() {
  if [ -n "$rootkeepr" ] ; then
    kill "$rootkeepr" || kill -9 "$rootkeepr"
  fi
}
trap cleanup EXIT


if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root=sudo
  echo 'Obtaining root permissions'
  $root true || exit 1
  (
    while true
    do
      sleep 60
      $root true
    done
  ) &
  rootkeepr=$!
fi

"$@"


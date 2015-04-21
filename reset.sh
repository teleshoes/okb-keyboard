#! /bin/sh -x
# clean up after test mode

rm -vf "$HOME/.config/maliit.org/server.conf"
systemctl --user stop maliit-server.service
killall maliit-server 2>/dev/null
systemctl --user restart maliit-server.service



#! /bin/sh -ex

cd `dirname "$0"`
. ../okb-engine/tools/env.sh

cd qml
OKBOARD_TEST=1 ../build/okboard-settings

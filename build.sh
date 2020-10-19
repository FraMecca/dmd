#!/bin/bash -e
_OLD=$(sha512sum /usr/bin/dmd)
make -f posix.mak clean
rm /usr/bin/dmd
ln -s /usr/bin/dmd-2.088 /usr/bin/dmd

# NOW BUILD
make -f posix.mak -j8 ENABLE_DEBUG=1
rm /usr/bin/dmd
ln -s /home/user/dlang/koch/generated/linux/release/64/dmd /usr/bin/dmd
echo $_OLD
sha512sum /usr/bin/dmd
python3 -c "input('OK? ')"

cd /home/user/dlang/autowrap/examples/phobos && ./build.sh

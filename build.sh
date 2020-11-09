#!/bin/bash -e
cd /home/user/dlang/clean
touch /usr/bin/mdmd
_OLD=$(sha512sum /usr/bin/mdmd)
make -f posix.mak clean

# NOW BUILD
make -f posix.mak -j8 ENABLE_DEBUG=1
ln -fs /home/user/dlang/clean/generated/linux/release/64/dmd /usr/bin/mdmd
echo $_OLD
sha512sum /usr/bin/mdmd
python3 -c "input('OK? ')"

# cd /home/user/dlang/autowrap/examples/phobos && ./build.sh

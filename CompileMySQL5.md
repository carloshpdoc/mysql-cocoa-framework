# Introduction #

In order to use the dynamic version of this library, you'll need a Universal Binary version of MySQL to link against.  As it is right now, MySQL does not provide this to link against.  Below is what I did to make a dynamically linked Universal Binary version of MySQL to link against.


# Details #

First, set the following command line environment variables:

export MACOSX\_DEPLOYMENT\_TARGET=10.5

export PATH="/usr/X11R6/bin:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin"

export LDFLAGS="-lz"

export CC=gcc

export CFLAGS="-arch ppc -arch ppc64 -arch i386 -arch x86\_64 -g -Os -fno-omit-frame-pointer -Wl,-
syslibroot,/Developer/SDKs/MacOSX10.5.sdk"

export CPPFLAGS=""

export CXX=gcc

export CXXFLAGS="-arch ppc -arch ppc64 -arch i386 -arch x86\_64 -g -Os -fno-omit-frame-pointer -fno-exceptions -fno-rtti -Wl,-syslibroot,/Developer/SDKs/MacOSX10.5.sdk"

Then, this is the _configure_ command line options. Use whatever command line options you see fit for your build of MySQL.  Note: you _must_ use **--disable-dependency-tracking** gcc-4.0 won't do the necessary dependency tracking when compiling for multiple architectures.

./configure --prefix=/opt/mysql --with-extra-charsets=complex --enable-local-infile --enable-largefile --with-innodb --with-big-tables --with-unix-socket-path=/private/tmp/mysql.sock --with-comment --with-gnu-ld --disable-dependency-tracking --with-federated-storage-engine --with-csv-storage-engine --with-archive-storage-engine --with-blackhole-storage-engine --enable-assembler --enable-static --enable-shared
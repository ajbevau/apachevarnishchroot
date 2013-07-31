#!/bin/bash
#
# Apache 2.4 Varnished CHROOTED PHP-FPM WordPress Virtual Host
# Andrew Bevitt <me@andrewbevitt.com>
# http://andrewbevitt.com/tutorials/apache-varnish-chrooted-php-fpm-wordpress-virtual-host/
#
# Copyright (c) 2013 Andrew Bevitt <me@andrewbevitt.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# This script downloads and builds Apache 2.4 and then installs it into
# the /opt/apache24 directory as per the tutorial. You do NOT need to use
# this script it literally just follows the commands in the tutorial.
#

INSTALL_PATH="/opt/apache24"
LOG_FILE="/tmp/apache24build.log"

[[ ! -d $PWD/build ]] && mkdir -p $PWD/build

# Move into the build directory and get the sources
echo 
echo "Fetching the Apache and APR sources"
echo
cd build
git clone --branch 2.4.x https://github.com/apache/httpd httpd-2.4.x
cd httpd-2.4.x
git clone --branch 1.4.x https://github.com/apache/apr srclib/apr
git clone --branch 1.5.x https://github.com/apache/apr-util srclib/apr-util
# For Linux we don't need APR-ICONV but you would on Windows

# Setup the configure scripts
echo "Creating configuration scripts"
./buildconf

# Do the configuration
echo "Configuring Apache for build..."
CFLAGS="-O2 -pipe -fomit-frame-pointer" \
./configure --prefix=${INSTALL_PATH} --enable-nonportable-atomics=yes --enable-pie --enable-mods-shared=all --enable-mods-static='alias authz_core authz_host log_config proxy proxy_fcgi proxy_http rewrite ssl unixd' --enable-auth-digest --enable-so --disable-include --enable-deflate --enable-http --enable-expires --enable-headers --disable-lua --disable-luajit --enable-mime-magic --enable-proxy --disable-proxy-connect --disable-proxy-ftp --enable-proxy-http --enable-proxy-fcgi --disable-proxy-scgi --disable-proxy-fdpass --disable-proxy-ajp --enable-proxy-balancer --disable-proxy-express --enable-slotmem-shm --enable-ssl --disable-autoindex --enable-negotiation --enable-dir --enable-alias --enable-rewrite --enable-v4-mapped --with-mpm=event --with-included-apr --with-ldap --with-crypto > ${LOG_FILE} 2>&1

# Build and if successful do the install
echo "Compiling now..."
if ( make >> ${LOG_FILE} ); then
	echo "  ... success will now install to ${INSTALL_PATH}"
	read -p "Do you want to install? (yes/no) -> " DO_INSTALL
	[[ "${DO_INSTALL}" == "yes" ]] && \
		sudo make install >> ${LOG_FILE} && \
		sudo chown -R root:root ${INSTALL_PATH}
else
	echo "  ... build failed please check errors above and ${LOG_FILE}"
fi

# END



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
# This script copies files from the local system into the given chroot
# parameter directory. The make_chroot.sh script calls this during the
# install ... because an install is just an update from nothing.
#
# You should call this script directly when upgrading packages.
#
# This is based off the work by Wolfgang Fuschlberger
#   http://www.fuschlberger.net/programs/ssh-scp-sftp-chroot-jail/
#
# For more details see make_chroot.sh
#
# USAGE:
#  update_chroot.sh /path/to/chroot
#

# First lets make sure parameters are correct and define some globals
CHROOT_DIR="$1"
[[ ! -d ${CHROOT_DIR} ]] && \
	echo "ERROR: The jail '${CHROOT_DIR}' does not exist" && exit 1

# We use the placeholder file ${CHROOT_DIR}/.isvhc to identify
# that this was built using these scripts - check that it's there
# and if so continue otherwise error out.
CONF_FILE=".isvhc"
[[ ! -e ${CHROOT_DIR}/${CONF_FILE} ]] && \
	echo "ERROR: This does not appear to be a jail created by this script" && exit 1

# This script MUST run as root because of file permissions
if [[ "$(whoami 2> /dev/null)" != "root" ]] && [[ "$(id -un 2> /dev/null)" != "root" ]]; then
	echo "ERROR: $0 must be run as root!"
	exit 1
fi

# Force the existing of /etc/debian_version 
if [[ ! -e /etc/debian_version ]]; then
	echo "ERROR: $0 only supports Ubuntu (and probably other Debian derived distributions)"
	exit 1
fi

# Read the settings from the ${CHROOT_DIR}/.isvhc
APPS=$(. ${CHROOT_DIR}/${CONF_FILE} && echo $INSTALLED_APPS)
EXTRALIBS=$(. ${CHROOT_DIR}/${CONF_FILE} && echo $INSTALLED_XLIBS)
INSTALL_IM=$(. ${CHROOT_DIR}/${CONF_FILE} && echo $INSTALLED_IM)

# Make sure we have the necessary local installed programs
# 1. which
if ( ! ( ( test -f /usr/bin/which ) || ( test -f /bin/which ) || \
        ( test -f /sbin/which ) || ( test -f /usr/sbin/which ) ) ); then
    cat << EOF
ERROR: Your system does not have the 'which' program installed.
       Please install debianutils:
         sudo apt-get install debianutils

NOTE: This really should be part of the base system!
EOF
    exit 1
fi
# 2. dirname
if ( ! which dirname &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'dirname' program installed.
	   Please install coreutils:
		 sudo apt-get install coreutils

NOTE: This really should be part of the base system!
EOF
	exit 1
fi
# 3. awk
if ( ! which awk &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'awk' program installed.
	   Please install an awk package:
		 sudo apt-get install mawk
EOF
	exit 1
fi
# 4. convert (if installing ImageMagick)
if [[ "$INSTALL_IM" == "yes" ]]; then
	if ( ! which convert &> /dev/null ); then
		cat << EOF
ERROR: Your system does not have the 'convert' program installed.
       This is part of the ImageMagick package which you have said
       you would like included in the chroot. Please install:
         sudo apt-get install imagemagick
EOF
		exit 1
	fi
fi

# Setup some temporary env vars for later in the script
CHROOT_PARENT=$(dirname ${CHROOT_DIR})
IM_SHARE=""
IM_LIBS=""
IM_ETC=""
if [[ "$INSTALL_IM" == "yes" ]]; then
	IM_SHARE=$(convert -list configure | grep SHARE_PATH | awk '{ print $2 }')
	IM_LIBS=$(convert -list configure | grep LIBRARY_PATH | awk '{ print $2 }')
	IM_ETC=$(convert -list configure | grep CONFIGURE_PATH | awk '{ print $2 }')

	[[ -z "$IM_SHARE" || ! -d "$IM_SHARE" ]] && \
		echo "ERROR: No ImageMagick SHARE_PATH available" && exit 1
	[[ -z "$IM_LIBS" || ! -d "$IM_LIBS" ]] && \
		echo "ERROR: No ImageMagick LIBRARY_PATH available" && exit 1
	[[ -z "$IM_ETC" || ! -d "$IM_ETC" ]] && \
		echo "ERROR: No ImageMagick CONFIGURE_PATH available" && exit 1
fi

# The CHROOT_DIR should exist so create child folders
echo "Checking jail root file system"
CHROOT_DIRS="dev etc etc bin sbin usr tmp var"
for d in $CHROOT_DIRS ; do
	[[ ! -d ${CHROOT_DIR}/$d ]] && \
		echo "  creating /$d" &&
		mkdir -p ${CHROOT_DIR}/$d
done
echo

# Creating necessary devices - if they don't already exist
echo "Checking jail devfs"
[[ -r $CHROOT_DIR/dev/urandom ]] || mknod $CHROOT_DIR/dev/urandom c 1 9
[[ -r $CHROOT_DIR/dev/null ]]    || mknod -m 666 $CHROOT_DIR/dev/null	c 1 3
[[ -r $CHROOT_DIR/dev/zero ]]    || mknod -m 666 $CHROOT_DIR/dev/zero	c 1 5
[[ -r $CHROOT_DIR/dev/tty ]]     || mknod -m 666 $CHROOT_DIR/dev/tty	 c 5 0 

# Copy the apps and the related libs
echo "Copying system applications to $CHROOT_DIR (may take some time)"
TMPFILE1=`mktemp`
TMPFILE2=`mktemp`
for app in $APPS; do
	# First of all, check that this application exists
	if [ -x $app ]; then
		echo "  $(basename $app)"
		app_path=`dirname $app`
		[[ ! -d $CHROOT_DIR/$app_path ]] && \
			mkdir -p $CHROOT_DIR/$app_path

		# Copy the application file into the jail and get libraries
		cp -p $app $CHROOT_DIR/$app
		ldd $app >> ${TMPFILE1}
	fi
done

# Loop over the required libs and remove "virtual" libraries
for lib in `cat ${TMPFILE1}`; do
   first_c=$(echo $lib | cut -c1)
   [[ "$first_c" == "/" ]] && echo "$lib" >> ${TMPFILE2}
done

# Loop over the real libs and copy them into jail
echo 
echo "Copying system libraries to $CHROOT_DIR (may take some time)"
for lib in `cat ${TMPFILE2}`; do
	lib_path=$(dirname $lib)
	[[ ! -d $CHROOT_DIR/$lib_path ]] && \
		mkdir -p $CHROOT_DIR/$lib_path
	# Copy the libraries into the chroot; note here we don't 
	# preserve symlinks because all we really care about is
	# the library name that the application links to.
	echo "  $lib"
	cp -p $lib $CHROOT_DIR/$lib
done

# Now, cleanup the 2 files we created for the library list
/bin/rm -f ${TMPFILE1}
/bin/rm -f ${TMPFILE2}

# There are a few libraries not listed by ldd which we copy now
cat << EOF

WARNING: This script is about to use 'locate' to find a series
of libraries on your system and copy them into the chroot jail.
If your locate database is out of date this will not work.

Would you like to run 'updatedb' first?
EOF
read -p "(yes/no) -> " RUNUPDATEDB
[[ "$RUNUPDATEDB" == "yes" ]] && updatedb

# Find the extra libs on the filesystem and only match file name
for xtra in `locate -b $EXTRALIBS`; do
	# Make sure this is not one of the existing virtual hosts
	xtra_path=`dirname $xtra`
	if [[ "${xtra_path##$CHROOT_PARENT}" == "${xtra_path}" ]]; then
		[[ ! -d ${CHROOT_DIR}/$xtra_path ]] && \
			mkdir -p $CHROOT_DIR/$xtra_path
		# Copy the library but preserve symlinks this time because
		# here we're specifically asking for a set of libs which
		# we won't know the names which are used for linking.
		# The symlinks are relative so it doesn't matter.
		echo "  $xtra"
		cp -p -P $xtra $CHROOT_DIR/$xtra_path
	fi
done

# If installing ImageMagick then we need to copy config and libs
if [[ "$INSTALL_IM" == "yes" ]]; then
	echo
	echo "Copying ImageMagick libs and configs into jail"
	for imp in ${IM_SHARE} ${IM_LIBS} ${IM_ETC}; do
		BP=$(dirname ${imp})
		[[ ! -d $CHROOT_DIR/$BP ]] && mkdir -p $CHROOT_DIR/$BP
		cp -rp ${imp} $CHROOT_DIR/$BP
	done
fi

# If you are using PAM you need stuff from /etc/pam.d/ in the jail,
echo
echo "Copying login modules to jail"
cp /etc/login.defs ${CHROOT_DIR}/etc/
cp -pr /etc/pam.d ${CHROOT_DIR}/etc
cp -pr /etc/security ${CHROOT_DIR}/etc
for pammod in `locate *security/pam_*.so`; do
	modpath=`dirname $pammod`
	[[ ! -d $CHROOT_DIR/$modpath ]] && \
		mkdir -p $CHROOT_DIR/$modpath
    # Copy the pam modules
    cp -p $pammod $CHROOT_DIR/$pammod
done

# Do we need SSL certificates
INSTALL_SSL="check"
[[ -d $CHROOT_DIR/etc/ssl ]] && INSTALL_SSL="yes"
if [[ "$INSTALL_SSL" == "check" ]]; then
	cat << EOF

QUESTION: Do you want the system SSL certificates copied into
the chroot jail for this user? This is required if the users'
scripts make HTTPS API requests.
EOF
	read -p "(yes/no) -> " INSTALL_SSL
fi

# If SSL is required then instal the certificates 
if [[ "$INSTALL_SSL" == "yes" ]]; then
	echo "Adding SSL certificates to the chroot jail"
	mkdir -p $CHROOT_DIR/etc/ssl/certs
	for c in `ls /etc/ssl/certs`; do
		LNKFIL="$c"
		[[ -L /etc/ssl/certs/$c ]] && \
			LNKFIL=$(dirname `readlink /etc/ssl/certs/$c`)
		if [[ "$LNKFIL" == "." ]]; then
			# If is a local link copy as a link
			cp -P /etc/ssl/certs/$c $CHROOT_DIR/etc/ssl/certs/
		else
			# Is a file or a non-local link so copy file
			cp /etc/ssl/certs/$c $CHROOT_DIR/etc/ssl/certs/
		fi
	done
fi


# Don't give more permissions than necessary
chown root:root ${CHROOT_DIR}/bin/su
chmod 700 ${CHROOT_DIR}/bin/su

# Finsihed
echo
echo "The applications/libraries have been added to '$CHROOT_DIR'"
exit 0


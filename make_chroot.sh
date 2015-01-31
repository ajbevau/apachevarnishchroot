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
# This script creates a basic chroot environment for each users websites.
# It is designed to work with the directory structure in the tutorial.
# You can call this script directly but it is designed to be called
# from the usersite.sh script when setting up a new user account.
#
# The actual application and library copy process is managed by the
# update_chroot.sh script which this script calls after setting up the
# static environment.
#
# This is based off the work by Wolfgang Fuschlberger
#   http://www.fuschlberger.net/programs/ssh-scp-sftp-chroot-jail/
#
# Features in this version:
#  - Ubuntu specific 
#  - Moved to bash for better shell coding
#  - Added php,curl,unzip,tar,false to the list of applications
#  - Builds mini_sendmail automatically for mail support
#  - Includes ImageMagick if required for a particular user
#  - Include timezone and zoneinfo in chroot
#  - Creates skeleton /etc/hosts, /etc/resolv.conf and /etc/nsswitch.conf
#  - Create new users and build chroot for them
#  - Use the chroot root directory as $HOME
#	i.e. separate chroot jail for each user
#  - Use /etc/sudoers.d/ scripts for each user
#  - Does not greate a group for the user
#  - Enable SCP and SFTP in the chroot jail
# 
# This version does NOT support moving existing users into a chroot.
#
# USAGE:
#  make_chroot.sh username group chroot
#   username - the user name to create (must NOT exist)
#   group	 - the users primary group (must already exist)
#   chroot   - where to create the users chroot directory
#              the username will be appended automatically
#

# First lets make sure parameters are correct and define some globals
USERNAME="$1"
PRI_GROUP="$2"
CHROOT_DIR="$3/$USERNAME"
MYPWD=$(echo $PWD)

# User must NOT exist
if [[ "$(id -un $USERNAME 2> /dev/null)" == "$USERNAME" ]]; then
	echo "ERROR: User '$USERNAME' already exists"
	exit 1
fi

# Group MUST exist
if ( ! groups $PRI_GROUP &> /dev/null ); then
	echo "ERROR: Group '$PRI_GROUP' does not exist"
	exit 1
fi

# The chroot user directory must not exist
if [[ -e "$CHROOT_DIR" ]];  then
	echo "ERROR: The chroot '$CHROOT_DIR' already exist"
	exit 1
fi


# Path to SSHD config so we can find sftp-server
SSHD_CONFIG="/etc/ssh/sshd_config"


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


# The chroot does not include ImageMagick by default
cat << EOF

QUESTION: The chroot does NOT include ImageMagick by default,
however if you want the script can copy in the ImageMagick
commands and libraries. This will provide support for:
  JPEG, PNG, TIFF
And the ImageMagick commands:
  /usr/bin/identify
  /usr/bin/composite
  /usr/bin/convert
  /usr/bin/montage
  /usr/bin/mogrify

Do you want ImageMagick setup in this user’s chroot?
EOF
read -p "(yes/no) -> " INSTALL_IM


# Define the applications to include in the chroot
APPS="/bin/bash /bin/cp /usr/bin/dircolors /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /sbin/unix_chkpwd /usr/bin/php /usr/bin/curl /usr/bin/unzip /bin/tar /bin/false"
[[ "${INSTALL_IM}" == "yes" ]] && \
	APPS="${APPS} /usr/bin/identify /usr/bin/composite /usr/bin/convert /usr/bin/montage /usr/bin/mogrify"

# There are a few libraries not will not get listed by ldd so 
# we manually specify them to be installed. Use wildcards to
# match the file and symlinks so we can copy both. 
EXTRALIBS="*libnss_compat*.so* *libnss_dns*.so* *libnss_files*.so* *libnsl*.so* *libcidn*.so* *libcap.so*"
# Add JPEG, PNG and TIFF if using ImageMagick
[[ "${INSTALL_IM}" == "yes" ]] && \
	EXTRALIBS="${EXTRALIBS} *libjpeg.so* libjpeg.a *libpng*.so* *libtiff.so*"


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
# 2. chroot 
if ( ! which chroot &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'chroot' program installed.
	   Please install coreutils:
		 sudo apt-get install coreutils

NOTE: This really should be part of the base system!
EOF
	exit 1
fi
# 3. sudo
if ( ! which sudo &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'sudo' program installed.
	   Please install sudo:
		 su -c "apt-get install sudo"

The virtual host configuration requires the use of the chroot
command which requires superuser privileges. The easiest way
to allow the user '$USERNAME' to execute chroot is to install
the sudo package.
EOF
	exit 1
fi
# 4. dirname
if ( ! which dirname &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'dirname' program installed.
	   Please install coreutils:
		 sudo apt-get install coreutils

NOTE: This really should be part of the base system!
EOF
	exit 1
fi
# 5. awk
if ( ! which awk &> /dev/null ); then
	cat << EOF
ERROR: Your system does not have the 'awk' program installed.
	   Please install an awk package:
		 sudo apt-get install mawk
EOF
	exit 1
fi


# Get location of sftp-server binary from /etc/ssh/sshd_config
# check for existence of /etc/ssh/sshd_config and for
# (uncommented) line with sftp-server filename. If neither exists,
# just skip this step and continue without sftp-server
SFTP_SERVER=""
if [[ ! -f ${SSHD_CONFIG} ]]; then
	echo "File ${SSHD_CONFIG} not found."
	echo "Not checking for path to sftp-server."
	echo "Please adjust the \$SSHD_CONFIG variable in $0"
else
	if ( ! (grep -v "^#" ${SSHD_CONFIG} | grep -i sftp-server &> /dev/null) ); then
		echo "No sftp-server is running on this system"
	else
		SFTP_SERVER=$(grep -v "^#" ${SSHD_CONFIG} | grep -i sftp-server | awk  '{ print $3}')
		echo "Adding $SFTP_SERVER to chroot applications"
		APPS="$APPS $SFTP_SERVER"
	fi
fi


# The original script allowed specifying a shell for chroot
# this script creates a simple sudo chroot wrapper and uses
# forces its use.
SHELL=/usr/local/bin/vhost-shell
if [[ ! -e $SHELL ]]; then
	echo "Creating $SHELL"
	echo '#!/bin/bash' > $SHELL
	echo "`which sudo` `which chroot` $CHROOT_DIR /bin/su -c /bin/bash -l \$USER" \"\$@\" >> $SHELL
	chmod 755 $SHELL
fi


# Make sure the parent directory for the chroot exists
# but don't create chroot as useradd will do that next
if [[ ! -d `dirname $CHROOT_DIR` ]]; then
	mkdir -p `dirname $CHROOT_DIR`
fi


# Create the system user account now and their chroot
echo
echo "Create new user: $USERNAME"
useradd -d $CHROOT_DIR -g $PRI_GROUP -m -s "$SHELL" $USERNAME
# Prevent the user from writing to their chroot root dir
# we create a /home below which is their home in the chroot
# however $CHROOT_DIR remains home globally - this means
# something like vsftpd could work in chrooted mode.
chown root $CHROOT_DIR
chmod 710 $CHROOT_DIR


# Create a /etc/sudoers.d file for this user
SUDOERS=/etc/sudoers.d/$USERNAME
echo "# Allow $USERNAME to sudo chroot to their jail home" > $SUDOERS
echo "$USERNAME ALL=NOPASSWD: `which chroot`, /bin/su -c /bin/bash -l $USERNAME" >> $SUDOERS
chmod 0440 $SUDOERS


# Create /usr/bin/groups in the jail
echo
echo "Setup user and groups in the new jail"
mkdir -p ${CHROOT_DIR}/usr/bin
echo "#!/bin/bash" > ${CHROOT_DIR}/usr/bin/groups
echo "id -Gn" >> ${CHROOT_DIR}/usr/bin/groups
chmod 755 ${CHROOT_DIR}/usr/bin/groups

# Add root to etc/passwd and etc/group in the jail
mkdir -p ${CHROOT_DIR}/etc
grep /etc/passwd -e "^root" > ${CHROOT_DIR}/etc/passwd
grep /etc/group -e "^root" > ${CHROOT_DIR}/etc/group
# plus add the system defaulted users group
# extract the user from the global /etc/passwd and add it to the
# jail etc/passwd file but replace the $HOME with /home as that's 
# what it looks like in the jail and use the included bash shell
grep -e "^$USERNAME:" /etc/passwd | \
 sed -e "s#$CHROOT_DIR#/home#"		\
	 -e "s#$SHELL#/bin/bash#"	   >> ${CHROOT_DIR}/etc/passwd

# Need to create the /home folder and give the user ownership
mkdir -p ${CHROOT_DIR}/home
chown $USERNAME:nogroup ${CHROOT_DIR}/home
chmod 700 ${CHROOT_DIR}/home
mv ${CHROOT_DIR}/.bash* ${CHROOT_DIR}/home/
mv ${CHROOT_DIR}/.profile ${CHROOT_DIR}/home/

# We need to include the $USERNAME primary group and 'users' group
# in the jailed etc/group to allow for proper group lookups. It is
# NOT necessary though to list users who are in either of these two
# groups where not the primary group for that user though.
grep -e "^users" /etc/group | \
	awk '{ split($0,x,":"); print x[1]":"x[2]":"x[3]":" }' >> ${CHROOT_DIR}/etc/group
grep -e "^$PRI_GROUP" /etc/group | \
	awk '{ split($0,x,":"); print x[1]":"x[2]":"x[3]":" }' >> ${CHROOT_DIR}/etc/group

# Write the users line from /etc/shadow to jail etc/shadow
grep -e "^$USERNAME:" /etc/shadow >> ${CHROOT_DIR}/etc/shadow
chown root:shadow ${CHROOT_DIR}/etc/shadow
chmod 640 ${CHROOT_DIR}/etc/shadow
grep -e "^shadow" /etc/group | \
	awk '{ split($0,x,":"); print x[1]":"x[2]":"x[3]":" }' >> ${CHROOT_DIR}/etc/group
grep -e "^nogroup" /etc/group | \
	awk '{ split($0,x,":"); print x[1]":"x[2]":"x[3]":" }' >> ${CHROOT_DIR}/etc/group


# Copy the timezone and zone info data into the chroot
echo
echo "Adding timezone and zoneinfo data to jail"
cp -p /etc/localtime ${CHROOT_DIR}/etc
cp -p /etc/timezone ${CHROOT_DIR}/etc
mkdir -p ${CHROOT_DIR}/usr/share/zoneinfo
cp -pr /usr/share/zoneinfo/* ${CHROOT_DIR}/usr/share/zoneinfo


# Adding hosts and resolv is necessary
echo
echo "Copying hosts, resolve.conf etc..."
cat > ${CHROOT_DIR}/etc/hosts << EOF
127.0.0.1       localhost
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
cat /etc/resolv.conf | grep nameserver > ${CHROOT_DIR}/etc/resolv.conf
cp /etc/nsswitch.conf ${CHROOT_DIR}/etc


# Add mini_sendmail for sendmail support 
echo 
echo "Downloading and installing mini_sendmail..."
cd build
[[ ! -d "mini_sendmail-1.3.6" ]] && \
	curl -X GET http://www.acme.com/software/mini_sendmail/mini_sendmail-1.3.6.tar.gz | tar xzf -
cd mini_sendmail-1.3.6
make 2> /dev/null
if [[ -x ./mini_sendmail ]]; then
	mkdir -p ${CHROOT_DIR}/usr/sbin
	cp mini_sendmail ${CHROOT_DIR}/usr/sbin/sendmail
else
	echo
	echo "WARNING: Failed to build mini_sendmail for this chroot"
	echo "this means that the PHP mail() function will NOT work"
	echo
fi


# Restore current working directory
cd $MYPWD


# Create the .isvhc file that update_chroot.sh requires
cat > ${CHROOT_DIR}/.isvhc << EOF
INSTALLED_APPS="${APPS}"
INSTALLED_XLIBS="${EXTRALIBS}"
INSTALLED_IM="${INSTALL_IM}"
EOF
chown root:root ${CHROOT_DIR}/.isvhc
chmod 0400 ${CHROOT_DIR}/.isvhc


# Call the update_chroot.sh script to update the blank chroot with apps/libs
if ( ! $MYPWD/update_chroot.sh ${CHROOT_DIR} ); then
	echo
	echo "ERROR: Failed to install applications and libraries into the chroot!"
	echo 
	exit 1
fi


# Finsihed
echo "The chroot '$CHROOT_DIR' is ready"
exit 0


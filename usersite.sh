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
# This script creates user accounts and/or site profiles for the virtual
# hosting structure defined by the tutorial. It also copies in default
# configuration files if necessary and points to what may need changing.
#
# The default configuration files are in the skel directory.
#
# NOTES:
#  If you're not familiar with bash scripting 0=TRUE, 1=FALSE
#  sed s/\\//\\\\\\//g means replace / with \/ - regex fun!
#

HOSTING_ROOT="/srv/www"
PHP_FPM_POOLS="/etc/php5/fpm/pool.d"
APACHE_VHOSTS="/opt/apache24/conf/vhosts.d"
APACHE_GROUP="www-data"
# Relative to the chroot root
USER_CONF_DIR="etc/apache"
USER_HTTP_DIR="var/www"
USER_LOGS_DIR="var/log/apache"
USER_TEMP_DIR="tmp"
# Where is $HOSTING_ROOT/$USERNAME relative to 
#    $HOSTING_ROOT/$USERNAME/$HOSTING_ROOT/$USER_HTTP_DIR
USER_SYMLINKS="../../.."

# Check for root permission as this is required for this process
if [[ "$(whoami 2> /dev/null)" != "root" ]] && [[ "$(id -un 2> /dev/null)" != "root" ]] ; then
	echo "Error: You must be root to run this script."
	exit 1
fi

# Function for printing script usage
usage() {
	cat << EOF
ERROR: Incorrect parameters
USAGE:
 usersite.sh create_user <user> <port> <email>
  Creates a user with the given username or errors if user already exists.
   <port> the port number to use for PHP5-FPM processes for this user.
   <email> the server admin and PHP from address email.

 usersite.sh create_site <user> <port> <domain> <admin> [<ssl_required> [<site_alias> ...]]
  Creates a virtual host site for the given user:
   <port> is the PHP5-FPM service port for the user.
   <domain> is the primary domain name for the site.
   <admin> email address of the site server admin.
   <ssl_required> Y or N if this site requires SSL.
   <site_alias> any number of FQDN aliases for this site.
  NOTE: New sites are NOT automatically enabled in Apache.
  NOTE: You can use . for the port if the user already exists.

 usersite.sh enable <user> <site_domain>
  Enable the given users site in the Apache configuration.
  NOTE: You will still need to reload Apache.

 usersite.sh disable <user> [<site_domain>]
  Disable the given users site if no sites given all are disabled.
  NOTE: You will still need to reload Apache.

 usersite.sh remove_site <user> [<site_domain>]
  Removes the users site from the system or all sites if none given.
  NOTE: This does NOT remove the user account (remove_user does that).

 usersite.sh remove_user <user>
  Removes the user from the system - and all site files.
  NOTE: This operation is final etc...

 usersite.sh wordpress <user> <site> <dbname> <dbprefix> [<dbhost>]
  Install WordPress into the user site document root.
   <dbname> the database name
   <dbprefix> the WordPress database table prefix
   <dbhost> the MySQL server (defaults to localhost if not specified)
  NOTE: Will automatically generate a secure password and print to log
EOF
	# Terminate the script
	exit 1
}


# Returns TRUE if the given user $1 exists
user_exists() {
	local username=${1,,}
	[[ "$(id -un $1 2> /dev/null)" == "$username" ]] && return 0 || return 1
}

# Create a user account with the given username
create_user() {
	# Extract the parameters
	local username=${1,,}
	local fpmport=${2,,}

	# Check the user doesn't already exist
	if ( user_exists $username ); then
		echo "ERROR: User $username already exists"
		exit 2
	fi

	# Sanity check the domain site admin
	if ( ! email_sanity_check $3 ); then
		echo "ERROR: The site admin '$3' email is invalid"
		exit 3
	fi

	# Make sure the port number is a ctually a number
	portreg="^[1-9][0-9]{1,4}\$"
	if [[ $fpmport =~ $portreg ]]; then
		# port is ok check in range
		if [[ $fpmport -gt 65535 ]]; then
			echo "ERROR: FPM service port '$fpmport' is too large"
			exit 2
		fi
	else
		echo "ERROR: FPM service port '$fpmport' is not a valid port number"
		exit 2
	fi

	# Use the make_chroot.sh script to add the user
	if ( ! $PWD/make_chroot.sh $username $APACHE_GROUP $HOSTING_ROOT ); then
		echo "ERROR: Could not create chroot for '$username'"
		exit 2
	fi
	
	# Make configuration and log directories
	CR="$HOSTING_ROOT/$username"
	[[ ! -d $CR/$USER_CONF_DIR ]] && mkdir -p $CR/$USER_CONF_DIR
	[[ ! -d $CR/$USER_LOGS_DIR ]] && mkdir -p $CR/$USER_LOGS_DIR
	chown root:$APACHE_GROUP $CR/{$USER_CONF_DIR,$USER_LOGS_DIR}
	chmod 750 $CR/{$USER_CONF_DIR,$USER_LOGS_DIR}
	[[ ! -d $CR/$USER_TEMP_DIR ]] && mkdir -p $CR/$USER_TEMP_DIR
	chown $username:$APACHE_GROUP $CR/$USER_TEMP_DIR
	chmod 700 $CR/$USER_TEMP_DIR

	# Create a link from /var/log/apache24 for users logs
	ln -sf $CR/$USER_LOGS_DIR /var/log/apache24/vh_$username 

	# Perform the ugly symlink hack just in case
	SYMHACK=`dirname $CR/$HOSTING_ROOT/$USER_HTTP_DIR`
	SYMTRGT=`basename $CR/$HOSTING_ROOT/$USER_HTTP_DIR`
	mkdir -p $SYMHACK
	cat >> $SYMHACK/README << EOF
This folder exists to preserve the DOCUMENT_ROOT in PHP.
A symlink exists from here to /$USER_HTTP_DIR where your
web site and files are really hosted. This is because of
the restricted environment in which PHP runs.
EOF
	ln -s $USER_SYMLINKS/$USER_HTTP_DIR $SYMHACK/$SYMTRGT

	# Copy the PHP5-FPM config file into the config directory
	phpconf="$CR/$USER_CONF_DIR/php5-fpm.conf"
	escuserhome=`echo $CR | sed 's/\\//\\\\\\//g'`
	cp skel/php5-fpm.tpl $phpconf
	sed -i s/USERNAME_REPLACE/$username/g $phpconf
	sed -i s/CHROOT_PATH_REPLACE/$escuserhome/g $phpconf
	sed -i s/APACHE_GROUP_REPLACE/$APACHE_GROUP/g $phpconf
	sed -i s/PHP_FPM_PORT/$fpmport/g $phpconf
	sed -i s/SITE_ADMIN_REPLACE/$3/g $phpconf

	# Output some results
	echo "Successfully created user account: $username"
	ls -l $HOSTING_ROOT/$username
}

fqdn_sanity_check() {
	local regex="^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
	local domain=${1,,}
	[[ $domain =~ $regex ]] && return 0 || return 1
}

email_sanity_check() {
	local regex="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
	local email=${1,,}
	[[ $email =~ $regex ]] && return 0 || return 1
}


# Check the parameters we received make sense 
# One of: create_user create_site enable disable
if [ "$1" != "create_user" ] && [ "$1" != "remove_user" ] && \
		[ "$1" != "create_site" ] && [ "$1" != "remove_site" ] && \
		[ "$1" != "enable" ] && [ "$1" != "disable" ] && \
		[ "$1" != "wordpress" ]; then
	usage
fi

# Decide what to do based on the first parameter
if [ "$1" == "create_user" ]; then

	# Make sure we have been given a username
	[[ -z "$2" ]] && usage
	[[ -z "$3" ]] && usage
	[[ -z "$4" ]] && usage
	create_user $2 $3 $4

elif [ "$1" == "remove_user" ]; then

	# Make sure we got given a user and the user exists
	[[ -z "$2" ]] && usage
	username=${2,,}
	if ( ! user_exists $username ); then
		echo "ERROR: No such user '$username' to remove"
		exit 1
	fi

	# This is a very broad stick 
	cat << EOF

===== WARNING =====
You are about to completely remove a user account and all files!
This operation CAN NOT be undone without backups.

You will remove user: $username
They have sites:
`ls -l $HOSTING_ROOT/$username/$USER_HTTP_DIR`

This will run: userdel -rf $username
The directory $HOSTING_ROOT/$username will be removed!

Are you sure you want to do this?
EOF
	read -p "(yes/no) -> " KILLUSER
	[[ "$KILLUSER" != "yes" ]] && exit 0

	# Ok proceed to kill the user
	echo
	echo "You can't say we didn't warn you :)"
	echo

	# First remove any config links
	rm -f $APACHE_VHOSTS/$username.*.conf $PHP_FPM_POOLS/$username.conf \
		/var/log/apache24/vh_$username

	# Remove the user from the sudoers include
	rm -f /etc/sudoers.d/$username

	# Delete the user account
	echo "Running: userdel -rf $username"
	userdel -rf $username
	if [[ -d $HOSTING_ROOT/$username ]]; then
		echo
		echo "WARNING: $HOSTING_ROOT/$username was not removed"
		echo
	fi

	# That's it
	cat << EOF

All done the user '$username' is no more!!!

WARNING: This script does NOT remove users from MySQL.

You should now restart the apache and php-fpm services:
  sudo service php5-fpm restart
  sudo service apache24 restart

EOF

elif [ "$1" == "create_site" ]; then

	# Make sure we have been given at least a username and site domain
	[[ -z "$2" ]] && usage
	[[ -z "$3" ]] && usage
	[[ -z "$4" ]] && usage
	[[ -z "$5" ]] && usage
	username=${2,,}

	# If we were given SSL_REQUIRED check it otherwise use NOT required
	if [ -n "$6" ] && [ "$6" != "Y" ] && [ "$6" != "N" ]; then
		echo "ERROR: ssl_required should be Y or N"
		usage
	fi

	# Make sure the FPM port is valid
	portnum="$3"
	portreg="^[1-9][0-9]{1,4}\$"
	if [[ "$3" == "." ]]; then
		if ( ! user_exists $2 ); then
			echo "ERROR: The FPM service port must be specified for new users"
			exit 2
		fi
		# Get the port number from the config file
		CF="$HOSTING_ROOT/$username/$USER_CONF_DIR/php5-fpm.conf"
		portnum=`grep -e "^listen\ =" $CF | awk '{ split($0,x,":"); print x[2] }'`
		if [[ -n "$portnum" ]]; then
			echo
			echo "Found port number '$portnum' in $CF"
			echo
		fi
	fi

	# Sanity check the port number
	if [[ $portnum =~ $portreg ]]; then
		# Port is a number so check range
		if [[ $portnum -gt 65535 ]]; then
			echo "ERROR: FPM service port '$portnum' is too large"
			exit 2
		fi
	else
		echo "ERROR: FPM service port '$portnum' is not a valid port number"
		exit 2
	fi

	# Sanity check the site domain name
	if ( ! fqdn_sanity_check $4 ); then
		echo "ERROR: The site domain '$4' is invalid"
		exit 3
	fi

	# Sanity check the domain site admin
	if ( ! email_sanity_check $5 ); then
		echo "ERROR: The site admin '$5' email is invalid"
		exit 3
	fi

	# If there are site aliases sanity check them too
	if [[ $# -ge 7 ]]; then 
		for alias in "${@:7}"; do
			if ( ! fqdn_sanity_check $alias ); then
				echo "ERROR: The site alias '$alias' is invalid"
				exit 3
			fi
		done
	fi

	# If the user does not exist then create them
	if ( ! user_exists $2 ); then
		create_user $2 $portnum $5
	fi

	# Now create the site based on templates
	template="http_noalias"
	if [[ "x$6" == "xY" ]]; then
		template="https_noalias"
		if [[ $# -ge 7 ]]; then
			template="https_aliases"
		fi
	elif [[ $# -ge 7 ]]; then
		template="http_aliases"
	fi

	# Create the site directory 
	domain=${4,,}
	username=${2,,}
	userhome="$HOSTING_ROOT/$username"
	docroot="$userhome/$USER_HTTP_DIR/$domain"
	echo "Creating site document root: $docroot"
	mkdir -p $docroot
	chown $username:$APACHE_GROUP $docroot
	chmod 750 $docroot
	chmod g+s $docroot # make sure files keep same perms

	# Copy the template scripts to the conf directory
	userconf="$userhome/$USER_CONF_DIR"
	cp skel/$template.tpl $userconf/$domain.conf
	sed -i s/PHP_FPM_PORT/$portnum/g $userconf/$domain.conf
	sed -i s/SITE_ADMIN_REPLACE/$5/g $userconf/$domain.conf
	sed -i s/SITE_DOMAIN_REPLACE/$domain/g $userconf/$domain.conf
	# $IFS defaults to <space><tab><newline> so the "${*:7}" gives
	# a single quoted string of each alias separated by <space>
	sed -i s/SITE_ALIASES_REPLACE/"${*:7}"/g $userconf/$domain.conf
	escdocroot=`echo $docroot | sed 's/\\//\\\\\\//g'`
	escuserlogs=`echo $userhome/$USER_LOGS_DIR | sed 's/\\//\\\\\\//g'`
	escuserhttp=`echo $USER_HTTP_DIR | sed 's/\\//\\\\\\//g'`
	sed -i s/DOCUMENT_ROOT_REPLACE/$escdocroot/g $userconf/$domain.conf
	sed -i s/USER_LOGS_DIR_REPLACE/$escuserlogs/g $userconf/$domain.conf
	sed -i s/USER_HTTP_DIR_REPLACE/$escuserhttp/g $userconf/$domain.conf
	echo "Created configuration file: $userconf/$domain.conf"
	echo ""
	cat << EOF
The new site $domain for user $username has been created.

If this site uses SSL you will need to install certificates.

You now need to upload files to the document root.
If you're installing wordpress:
 usersite.sh wordpress $username $domain <dbname> <dbprefix> [<dbhost>]

Once the site is ready:
 usersite.sh enable $username $domain
EOF

elif [ "$1" == "remove_site" ]; then

	# Make sure the user and the site exists
	[[ -z "$2" ]] && usage
	username=${2,,}
	if ( ! user_exists $username ); then
		echo "ERROR: User $username does not exist..."
		exit 2
	fi

	# Now decide if a domain was given or not
	domain=${3,,}
	if [[ -n "$domain" ]]; then

		# This is a very broad stick
		cat << EOF

===== WARNING =====
You are about to completely remove a site and all files!
This operation CAN NOT be undone without backups.

You will remove the site '$domain' from user: $username

Are you sure you want to do this?
EOF
		read -p "(yes/no) -> " KILLSITE
		[[ "$KILLSITE" != "yes" ]] && exit 0
		echo
		echo "Ok you were warned..."
		echo
		
		# A domain was given so just remove it
		rm -f $APACHE_VHOSTS/$username.$domain.conf
		rm -f $HOSTING_ROOT/$username/$USER_CONF_DIR/$domain.conf
		rm -rf $HOSTING_ROOT/$username/$USER_HTTP_DIR/$domain

	else

		# No domain given so remove all of them...
		cat << EOF

===== WARNING =====
You are about to completely remove ALL sites for user: $username.
This operation CAN NOT be undone without backups.

The following sites will be removed:
`ls -l $HOSTING_ROOT/$username/$USER_HTTP_DIR`

Are you sure you want to do this?
EOF
		read -p "(yes/no) -> " KILLSITE
		[[ "$KILLSITE" != "yes" ]] && exit 0
		echo
		echo "Ok you were warned..."
		echo

		# Remove all of the apache links 
		rm -f $APACHE_VHOSTS/$username.*.conf
		for site in `ls $HOSTING_ROOT/$username/$USER_HTTP_DIR`; do
			rm -f $HOSTING_ROOT/$username/$USER_CONF_DIR/$site.conf
			rm -rf $HOSTING_ROOT/$username/$USER_HTTP_DIR/$site
		done
	
	fi


	# If there are no active sites then disable PHP
	if ( ! ls $APACHE_VHOSTS/$username.*.conf &> /dev/null ); then
		echo
		echo "There are no active sites left for user '$username'"
		echo "Disabling the PHP-FPM process pool for them"
		echo
		rm -f $PHP_FPM_POOLS/$username.conf
	fi

	cat << EOF

The user site(s) have been removed you should now:
  sudo service apache24 restart
  sudo service php5-fpm restart

EOF

elif [ "$1" == "enable" ] || [ "$1" == "disable" ]; then

	# Make sure we have a valid user and site
	[[ -z "$2" ]] && usage
	[[ -z "$3" ]] && [[ "$1" == "enable" ]] && usage

	# Make sure the user and the site exists
	username=${2,,}
	if ( ! user_exists $username ); then
		echo "ERROR: User $username does not exist..."
		exit 2
	fi

	# Make sure PHP5-FPM config is a symlink
	if [[ -e $PHP_FPM_POOLS/$username.conf ]] && \
			[[ ! -L $PHP_FPM_POOLS/$username.conf ]]; then
		echo "ERROR: PHP5-FPM config for '$username' exists bus is not a symlink"
		echo "	   should point to: $HOSTING_ROOT/$username/$USER_CONF_DIR/php5-fpm.conf"
		exit 3
	fi

	# Now the site based on domain directory and config
	domain=${3,,}
	if [[ -n "$domain" ]]; then

		# Domain was specified so check that one specific instance
		if [[ ! -d $HOSTING_ROOT/$username/$USER_HTTP_DIR/$domain ]] || \
				[[ ! -f $HOSTING_ROOT/$username/$USER_CONF_DIR/$domain.conf ]]; then
			echo "ERROR: User site '$domain' does not exist..."
			exit 2
		fi

		# Check if the config links exist as something else
		if [[ -e $APACHE_VHOSTS/$username.$domain.conf ]] && \
				[[ ! -L $APACHE_VHOSTS/$username.$domain.conf ]]; then
			echo "ERROR: Apache config for '$domain' exists but is not a symlink"
			echo "	   should point to: $HOSTING_ROOT/$username/$USER_CONF_DIR/$domain.conf"
			exit 3
		fi

		# Remove the apache config link either way and then recreate to enable
		rm -f $APACHE_VHOSTS/$username.$domain.conf

		# If we're enabling then recreate links
		if [[ "$1" == "enable" ]]; then
			# Create Apache link 
			ln -s $HOSTING_ROOT/$username/$USER_CONF_DIR/$domain.conf \
				$APACHE_VHOSTS/$username.$domain.conf
			# Create the PHP5-FPM config for the user if it doesn't exist
			if [[ ! -e $PHP_FPM_POOLS/$username.conf ]]; then
				ln -s $HOSTING_ROOT/$username/$USER_CONF_DIR/php5-fpm.conf \
					$PHP_FPM_POOLS/$username.conf
			fi
			# List the links so we can see what happened
			ls -l $PHP_FPM_POOLS/$username.conf $APACHE_VHOSTS/$username.$domain.conf
			echo
		fi

	else
	
		# No domain specified so want to disable everything
		for link in `ls $APACHE_VHOSTS/$username.*.conf`; do
			if [[ ! -L $link ]]; then
				echo "ERROR: Apache config '$link' exists but is not a symlink"
				echo "	   should point to config in $HOSTING_ROOT/$username/$USER_CONF_DIR"
				exit 3
			fi
			# Remove the link 
			rm -f $link
		done
	
	fi

	# If we're disabling and no more active domains for this user remove PHP
	if [[ "$1" == "disable" ]]; then
		if ( ! ls $APACHE_VHOSTS/$username.*.conf &> /dev/null ); then
			[[ -n "$domain" ]] && echo "There are no more sites enabled for '$username'"
			rm -f $PHP_FPM_POOLS/$username.conf
		fi
	fi
	
	# Output the result
	cat << EOF
Links to the configuration files have been updated.

You will need to reload the Apache and PHP5-FPM services:
 sudo service apache24 reload
 sudo service php5-fpm reload
EOF

elif [ "$1" == "wordpress" ]; then

	# Make sure we received the parameters
	# ./usersite.sh wordpress <user> <site> <dbname> <dbprefix> [<dbhost>]
	[[ -z "$2" ]] && usage
	username=${2,,}
	if ( ! user_exists $username ); then
		echo "ERROR: No such user '$username' exists"
		exit 2
	fi

	[[ -z "$3" ]] && usage
	domain=${3,,}
	if [[ ! -d $HOSTING_ROOT/$username/$USER_HTTP_DIR/$domain ]]; then
		echo "ERROR: No such domain '$domain' for user '$username'"
		exit 2
	fi

	[[ -z "$4" ]] && usage
	dbname="${4,,}"
	dbname=$(echo $dbname | sed "s/'//g" | sed 's/"//g' | sed 's/;//g') 

	[[ -z "$5" ]] && usage
	dbprefix="$5"

	# If set then will be used, otherwise localhost
	dbhost="$6"
	dbfrom=$(hostname -f)
	[[ -z "$dbhost" ]] && dbhost="127.0.0.1" && dbfrom="localhost"

	INSTALL_PATH="$HOSTING_ROOT/$username/$USER_HTTP_DIR/$domain/"
	INSTALL_PATH=$(echo $INSTALL_PATH | sed 's/\/\//\//g')

	cat << EOF

=== WORDPRESS INSTALL ===
You're about to install WordPress into:
  $INSTALL_PATH

A mysql user '$username' will be created with all privileges for database '$dbname'
If the database does not exist it will be created too.

The database password will be automatically generated using:
  pwgen -cns 30 1
Gives something like: N97hXl02xXo642yAwLhv2YVDoUR3GF
If pwgen is not installed you will be prompted for a password.

The password will be printed below.

Are you ready to proceed?
EOF
	read -p "(yes/no) -> " INSTALLWP
	[[ "$INSTALLWP" != "yes" ]] && exit 0

	dbpwd=""
	if ( ! which pwgen &> /dev/null ); then
		echo
		echo "Password generator not installed!"
		echo "Please enter a database password (do not use any of ;'\"&)"
		read dbpwd
		echo
		[[ "$dbpwd" != "$(echo $dbpwd | sed "s/'//g" | sed 's/"//g' | sed 's/;//g' | sed 's/\&//g')" ]] \
			&& echo "Password contains illegal characters" && exit 2
	else
		dbpwd=$(pwgen -cns 30 1 | sed "s/'//g" | sed 's/"//g' | sed 's/;//g')
		echo
		echo "Database password will be: $dbpwd"
		echo
	fi

	# Get an existing db user who can create DB/User
	echo
	echo "Please enter your database administrator username:"
	read dbroot
	[[ -z "$dbroot" ]] && echo "That's not a valid database user" && exit 2


	# Create database and user entry
	cat << EOF
CREATE DATABASE IF NOT EXISTS $dbname;
GRANT ALL PRIVILEGES ON $dbname.* TO '$username'@'$dbfrom' IDENTIFIED BY '$dbpwd';
FLUSH PRIVILEGES;
EOF
	mysql -u $dbroot -p --host $dbhost << EOF
CREATE DATABASE IF NOT EXISTS $dbname;
GRANT ALL PRIVILEGES ON $dbname.* TO '$username'@'$dbfrom' IDENTIFIED BY '$dbpwd';
FLUSH PRIVILEGES;
EOF
	
	# Change into the install path and download wordpress
	OLDPWD=$(echo $PWD)
	cd $INSTALL_PATH
	echo "Downloading WordPress from http://wordpress.org/latest.tar.gz"
	curl -X GET http://wordpress.org/latest.tar.gz | tar -xzf -
	[[ $? -ne 0 ]] && echo "ERROR: Failed to download WordPress..." && exit 2
	mv wordpress/* ./
	rm -rf wordpress

	# Now we need to inline edit the config file
	cp -f wp-config-sample.php wp-config.php
	chmod 600 wp-config.php

	# Database name
	echo "Updating wp-config.php:"
	echo "  DB_NAME = $dbname"
	sed -i "s/define('DB_NAME',.*);/define('DB_NAME', '$dbname');/g" wp-config.php
	echo "  DB_USER = $username"
	sed -i "s/define('DB_USER',.*);/define('DB_USER', '$username');/g" wp-config.php
	echo "  DB_PASSWORD = $dbpwd"
	sed -i "s/define('DB_PASSWORD',.*);/define('DB_PASSWORD', '$dbpwd');/g" wp-config.php
	echo "  DB_HOST = $dbhost"
	sed -i "s/define('DB_HOST',.*);/define('DB_HOST', '$dbhost');/g" wp-config.php
	echo "  \$table_prefix = $dbprefix"
	sed -i "s/\$table_prefix.*;/\$table_prefix = '$dbprefix';/g" wp-config.php

	# If we have pwgen then do the keys also
	if ( which pwgen &> /dev/null ); then
		echo "Generating secret keys:"
		for key in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
				AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
			newkey=$(pwgen -cnys 65 1 | sed 's/\\/\\\\/g' | sed "s/'//g" | sed s/\\///g | sed s/\&//g)
			echo "  $key = $newkey"
			sed -i "s/define('$key',.*);/define('$key', '$newkey');/g" wp-config.php
		done
	else
		echo
		echo "Because pwgen is not available the secret keys have not been generated"
		echo "please copy the following into $INSTALL_PATH/wp-config.php:"
		curl -X GET https://api.wordpress.org/secret-key/1.1/salt/ 2> /dev/null
		echo
	fi
	
	# Set the owner of the files
	chown -R $username:$APACHE_GROUP *
	chmod -R o-rwx *
	chmod g-rwx wp-config.php
	cd $OLDPWD

	# All done
	cat << EOF

WordPress has been extracted and a wp-config.php file created
please point your browser to the URL to complete the WordPress
install (i.e. create tables and default user)

Remember to enable this site in Apache if you haven't already:
  usersite.sh enable $username $domain

EOF

else

	# This is a fail safe
	usage
	exit 1 

fi

exit 0


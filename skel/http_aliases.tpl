#
# Apache 2.4 Virtual Host
# SITE_DOMAIN_REPLACE
# SITE_ALIASES_REPLACE
#
# Apache 2.4 Varnished CHROOTED PHP-FPM WordPress Virtual Host
# Andrew Bevitt <me@andrewbevitt.com>
# http://andrewbevitt.com/tutorials/apache-varnish-chrooted-php-fpm-wordpress-virtual-host/
#
# As per the tutorial we have Apache sitting behind Varnish
# for HTTP but not HTTPS and we have statically linked the
# mod_ssl module. Varnish is configured to send requests to
# 127.0.0.1:80; however we use *:80 below because:
#  1) Listen directive in ports.conf limits to 127.0.0.1
#  2) Makes this still work if you remove Varnish
#	 (all you need to do is change ports.conf)
#

<VirtualHost *:80>

	# Virtual host details
	ServerName SITE_DOMAIN_REPLACE
	ServerAdmin SITE_ADMIN_REPLACE
	ServerAlias SITE_ALIASES_REPLACE
	DocumentRoot DOCUMENT_ROOT_REPLACE

	# Configuration details for the document root
	<Directory DOCUMENT_ROOT_REPLACE/>
		Require all granted
		Options +FollowSymLinks
		AllowOverride AuthConfig FileInfo Options Limit

		# Send a simple 404 for favicon if missing
		<Files favicon.ico>
			ErrorDocument 404 "No favicon.ico exists"
		</Files>
	</Directory>

	# Site log files piped through cronolog
	ErrorLog "|/usr/bin/cronolog USER_LOGS_DIR_REPLACE/error_log_%B"
	CustomLog "|/usr/bin/cronolog USER_LOGS_DIR_REPLACE/access_log_week%U" combined

	# Send all PHP scripts to chrooted PHP5-FPM service
	ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:PHP_FPM_PORT/USER_HTTP_DIR_REPLACE/SITE_DOMAIN_REPLACE/$1

</VirtualHost>


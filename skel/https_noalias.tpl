#
# Apache 2.4 Virtual Host
# SITE_DOMAIN_REPLACE
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
# There is an SSL catch all virtual host which means that
# any clients which do NOT support Server Name Indication
# (SNI) will not be able to access the SSL virtual host.
# This is basically IE on Windows XP. If this is a problem
# IP-based virtual hosting can be used for SSL by replacing
# the *:443 with IP:443 below.
#

<VirtualHost *:80>

	# Virtual host details
	ServerName SITE_DOMAIN_REPLACE
	ServerAdmin SITE_ADMIN_REPLACE
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

<VirtualHost *:443>

	# Virtual host details
	ServerName SITE_DOMAIN_REPLACE
	ServerAdmin SITE_ADMIN_REPLACE
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
	NOTE: SSL is not run through Varnish Cache so use combined log
	ErrorLog "|/usr/bin/cronolog USER_LOGS_DIR_REPLACE/error_log_%B"
	CustomLog "|/usr/bin/cronolog USER_LOGS_DIR_REPLACE/access_log_week%U" combined

	# Send all PHP scripts to chrooted PHP5-FPM service
	ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:PHP_FPM_PORT/USER_HTTP_DIR_REPLACE/SITE_DOMAIN_REPLACE/$1

	# Turn on SSL and use snakeoil certificate
	# NOTE: You should replace this with a real certificate
	SSLEngine on
	SSLCertificateFile	/etc/ssl/certs/ssl-cert-snakeoil.pem
	SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
	#SSLCACertificateFile /path/to/CA/cert.crt

	#   SSL Protocol Adjustments:
	#   The safe and default but still SSL/TLS standard compliant shutdown
	#   approach is that mod_ssl sends the close notify alert but doesn't wait for
	#   the close notify alert from client. When you need a different shutdown
	#   approach you can use one of the following variables:
	#   o ssl-unclean-shutdown:
	#	 This forces an unclean shutdown when the connection is closed, i.e. no
	#	 SSL close notify alert is send or allowed to received.  This violates
	#	 the SSL/TLS standard but is needed for some brain-dead browsers. Use
	#	 this when you receive I/O errors because of the standard approach where
	#	 mod_ssl sends the close notify alert.
	#   o ssl-accurate-shutdown:
	#	 This forces an accurate shutdown when the connection is closed, i.e. a
	#	 SSL close notify alert is send and mod_ssl waits for the close notify
	#	 alert of the client. This is 100% SSL/TLS standard compliant, but in
	#	 practice often causes hanging connections with brain-dead browsers. Use
	#	 this only for browsers where you know that their SSL implementation
	#	 works correctly.
	#   Notice: Most problems of broken clients are also related to the HTTP
	#   keep-alive facility, so you usually additionally want to disable
	#   keep-alive for those clients, too. Use variable "nokeepalive" for this.
	#   Similarly, one has to force some clients to use HTTP/1.0 to workaround
	#   their broken HTTP/1.1 implementation. Use variables "downgrade-1.0" and
	#   "force-response-1.0" for this.
	BrowserMatch "MSIE [2-6]" \
		nokeepalive ssl-unclean-shutdown \
		downgrade-1.0 force-response-1.0
	# MSIE 7 and newer should be able to use keepalive
	BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown

</VirtualHost>


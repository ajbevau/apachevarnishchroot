;
; Apache 2.4 PHP5-FPM Virtual Host
; User account: USERNAME_REPLACE
;
; Apache 2.4 Varnished CHROOTED PHP-FPM WordPress Virtual Host
; Andrew Bevitt <me@andrewbevitt.com>
; http://andrewbevitt.com/tutorials/apache-varnish-chrooted-php-fpm-wordpress-virtual-host/
;
; Start a new pool named 'USERNAME_REPLACE'.
; The variable $pool can be used and will be replaced with this name.
; This file is designed to work within a CHROOT for the user at:
;    CHROOT_PATH_REPLACE
;
; All Apache configs that address this process will need to set paths
; relative to this CHROOT path. They should not put the full path.
;

; Pool name
[USERNAME_REPLACE]

; Pool prefix which is applied to:
; - 'slowlog'
; - 'listen' (unixsocket)
; - 'chroot'
; - 'chdir'
; - 'php_values'
; - 'php_admin_values'
prefix = CHROOT_PATH_REPLACE

; Unix user/group of processes
user = USERNAME_REPLACE
group = APACHE_GROUP_REPLACE

; The address on which to accept FastCGI requests.
listen = 127.0.0.1:PHP_FPM_PORT

; List of ipv4 addresses of FastCGI clients which are allowed to connect.
listen.allowed_clients = 127.0.0.1

; Choose how the process manager will control the number of child processes.
;  ondemand - no children are created at startup. Children will be forked when
;             new requests will connect. The following parameter are used:
;             pm.max_children           - the maximum number of children that
;                                         can be alive at the same time.
;             pm.process_idle_timeout   - The number of seconds after which
;                                         an idle process will be killed.
pm = ondemand

; Maximum number of child processes when pm is set to 'dynamic' or 'ondemand'.
; This value sets the limit on the number of simultaneous requests.
pm.max_children = 25

; The number of seconds after which an idle process will be killed.
; The default value of 10s is for a server that needs to reclaim resources
; quickly; we have adjusted this to 120s to limit process thrashing.
pm.process_idle_timeout = 120s;
 
; The access log file - designed for tutorial chroot location
; Does NOT inherit prefix or get jailed to chroot
access.log = CHROOT_PATH_REPLACE/var/log/php5fpm_access_log

; The access log format.
; This gives: time method request_uri?params status length memory cpu%
access.format = "%t \"%m %r%Q%q\" %s %{mili}d %{kilo}M %C%%"
 
; The log file for slow requests - designed for tutorial chroot location
; Does NOT inherit prefix or get jailed to chroot
slowlog = CHROOT_PATH_REPLACE/var/log/php5fpm_slow_log
 
; The timeout for serving a single request after which a PHP backtrace will be
; dumped to the 'slowlog' file. A value of '0s' means 'off'.
; Available units: s(econds)(default), m(inutes), h(ours), or d(ays)
request_slowlog_timeout = 25s
 
; The timeout for serving a single request after which the worker process will
; be killed. This option should be used when the 'max_execution_time' ini option
; does not stop script execution for some reason. A value of '0' means 'off'.
; Available units: s(econds)(default), m(inutes), h(ours), or d(ays)
request_terminate_timeout = 30s
 
; Chroot to this directory at the start. This value must be an absolute path.
; Note: chrooting is a great security feature and should be used whenever 
;       possible. However, all PHP paths will be relative to the chroot
;       (error_log, sessions.save_path, ...).
chroot = $prefix
 
; Chdir to this directory at the start.
chdir = /
 
; Limits the extensions of the main script FPM will allow to parse.
; Note: set an empty value to allow all extensions.
;
; The tutorial Apache config files match on .php only but just in case.
security.limit_extensions = .php
 
;   php_value/php_flag             - you can set classic ini defines which can
;                                    be overwritten from PHP call 'ini_set'. 
;   php_admin_value/php_admin_flag - these directives won't be overwritten by
;                                     PHP call 'ini_set'
; For php_*flag, valid values are on, off, 1, 0, true, false, yes or no.
php_value[session.save_path] = /tmp
php_admin_value[session.name] = HSTD_FPM_SSSN
php_admin_value[error_log] = /var/log/php5fpm_error_log
php_admin_flag[log_errors] = on
php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -fSITE_ADMIN_REPLACE


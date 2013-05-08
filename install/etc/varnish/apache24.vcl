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
# This should be used as your varinish config file:
#  i.e. -f /path/to/apache24.vcl
#
# This is designed to provide maximum WordPress onsite function
# and maximum cache hits. We drop all cookies unless there is
# a logged in user i.e. wordpres_sec_ or wordpress_logged_in_
# prefixed cookies. In which case we don't cache the site.
#
# The wordpress comment_ prefixed cookies are dropped as they
# are simply for reader convenience. It only stores their name,
# email and URL so nothing lost and easy to re-enter.
#
# You can force a cache miss / pre-warm using:
#  curl -X GET -H 'X-REFRESH: NOW' http://yourdomain.com/
#
# This file uses subroutines (e.g. cstm_purge_recv) to group
# code for reusability etc. Other similar projects have used 
# multiple files and include them in the builtin subroutines.
# There is no functional difference in the two approaches.
#
# NOTE: This setup assumes you have configured Apache as per the
# tutorial (i.e. listening on 127.0.0.1:80). If this is not the
# case then you will need to change the backend.
#
# This file draws inspiration from:
#   https://www.varnish-cache.org/docs/3.0/reference/vcl.html
#   https://www.varnish-cache.org/trac/wiki/VarnishAndWordpress
#   https://github.com/pothi/WordPress-Varnish
#   https://github.com/pkhamre/wp-varnish
#
# FINALLY: There is a lot of documentation that uses version 2.1
# configuration syntax. You will save yourself loads of time if
# you read up on the changes from v2.1 to v3.0 now:
#   https://www.varnish-cache.org/docs/3.0/installation/upgrade.html
#

#
# Apache 2.4 Server Backend
# A backend is a server / service varnish will send requests to
# when the cache does not have content or content has expired or
# when the request should not be cached etc...
#
# I've used the name default as that's the assumed name unless
# it is specified in the request processing - which it isn't.
#
# WARNING: This backend has a health probe in use. It assumes
# you have the default vhost configured as per the tutorial.
# If the /helloworld.html URI fails then Varnish will blacklist
# this backend - meaning your site will go offline.
#
backend default {
	.host = "127.0.0.1";
	.port = "80";
	.probe = {
		.url = "/helloworld.html";
		.interval = 60s;
		.timeout = 3s;
		.window = 10;
		.threshold = 7;
		.initial = 10;
	}
}

#
# Access Control Lists
# The varnish ACL's work to identify clients as belonging to a
# specific group. In this setup we use ACL's in two ways:
#  1) Allow PURGE access to localhost
#  2) List clients that should not be cached
# You should use IP addresses here unless you really know what
# you're doing - hostnames that cannot be resolved will match
# all clients (which is probably not what you want).
#
# Yes by default these are the same but you can change them!
#

acl purgeallowed {
	"localhost";
	"127.0.0.1";
}

acl donotcache {
	"localhost";
	"127.0.0.1";
}

#
# ========================= CUSTOM SUBROUTINES =========================
#

#
# CSTM_PURGE_RECV
# Checks if this is a PURGE request and if the client has
# access to trigger a cache purge. If not allowed then 
# return HTTP 405; if allowed then return lookup which
# forward processing to VCL_HIT or VCL_MISS.
#
# Cache purging is performed in CSTM_PURGE_CACHE.
#
sub cstm_purge_recv {
	if (req.request == "PURGE") {
		if (! client.ip ~ purgeallowed) {
			error 405 "Not allowed";
		}
		return(lookup);
	}
}

#
# CSTM_DO_NOT_CACHE_RECV
# Checks if the client is in the donotcache ACL and if so
# then passes the connection so it doesn't get cached.
#
sub cstm_do_not_cache_recv {
	if (client.ip ~ donotcache) {
		return (pass);
	}
}

#
# CSTM_HAS_WP_COOKIES_RECV
# Passes the request to the backend if it has WP logged in
# cookies. As noted in the top comments we only keep the
# logged in user cookies NOT commenter cookies.
#
# NOTE: The a FETCH of this is not required as the cookies
# are correctly removed by CSTM_KILL_COOKIES_FETCH which
# means you can only set the cookies during login/admin
# page requests - which is really quite good!
#
sub cstm_has_wp_cookies_recv {
    if (req.http.Cookie ~ "wordpress_logged_in_" || req.http.Cookie ~ "wordpress_sec_") {
        return (pass);
    }
}

#
# CSTM_KILL_COOKIES_RECV
# This will remove cookies from the request if not using the
# WordPress admin or login pages. This might stop a somethings
# from working properly.
#
# NOTE: You also need to look at CSTM_KILL_COOKIES_FETCH.
#
sub cstm_kill_cookies_recv {
	if (!(req.url ~ "wp-(login|admin)")) {
		unset req.http.cookie;
	}
}

#
# CSTM_KILL_COOKIES_FETCH
# As above but removes cookies sent from the backend.
#
sub cstm_kill_cookies_fetch {
	if (!(req.url ~ "wp-(login|admin)")) {
		unset beresp.http.set-cookie;
	}
}

#
# CSTM_BINARY_FILES_RECV
# Sends requests for binary format files via pipe so they don't 
# touch the cache. Afterall we don't need to cache static content.
#
sub cstm_binary_files_recv {
	if (req.url ~ "^[^?]*\.(zip|tar|gz|tgz|bz2|mp[34]|pdf|rar|rtf|swf|wav|xc|7z|doc|docx|xls|xlsx|ppt|pptx|ods|odt)(\?.*)?$") {
		return (pipe);
	}
}

#
# CSTM_IS_WP_ADMIN_PREVIEW_RECV
# Passes the request to the backend if using the WP admin,
# login or preview functions. These should NOT be cached.
#
sub cstm_is_wp_admin_preview_recv {
	# The login/admin and preview views
	if (req.url ~ "wp-(login|admin)" || req.url ~ "preview=true") {
		return (pass);
	}
	# Any other directly addressed url
	if (req.url ~ "^/wp-cron\.php$" ||
			req.url ~ "^/xmlrpc\.php$" ||
			req.url ~ "^/wp-admin/.*$" ||
			req.url ~ "^/wp-includes/.*$") {
		return (pass);
	}
	# Don't cache contact pages so we don't leak info
	if (req.url ~ "contact") {
		return (pass);
	}
}

#
# CSTM_IS_WP_ADMIN_PREVIEW_FETCH
# Generates a hit for pass object for the document if it
# is part of the admin, login or preview functions. This
# effectively means these will not be cached.
#
sub cstm_is_wp_admin_preview_fetch {
	# The login/admin and preview views
	if (req.url ~ "wp-(login|admin)" || req.url ~ "preview=true") {
		set beresp.http.X-Cacheable = "NO - Admin/Preview";
		set beresp.http.Cache-Control = "max-age=0";
		return (hit_for_pass);
	}
	# Any other directly addressed url
	if (req.url ~ "^/wp-cron\.php$" ||
			req.url ~ "^/xmlrpc\.php$" ||
			req.url ~ "^/wp-admin/.*$" ||
			req.url ~ "^/wp-includes/.*$") {
		return (hit_for_pass);
	}
	# Contact Pages
	if (req.url ~ "contact") {
		set beresp.http.X-Cacheable = "NO - Contact Page";
		return (hit_for_pass);
	}
}

#
# CSTM_PASS_STATIC_CONTENT_RECV
# If the requested content is static then simply pass the
# request to the backend. There is no need to cache something
# that is not built on the fly.
#
sub cstm_pass_static_content_recv {
	# Images - alphabetical
	if (req.url ~ "\.(bmp|gif|ico|jpg|jpeg|png|pgm|ppm|psd|svg|tif|tiff|webp|xcf)") {
		return (pass);
	}
	
	# CSS & JS
	if (req.url ~ "\.(css|js)") {
		return (pass);
	}
	
	# Fonts
	if (req.url ~ "\.(woff|eot|otf|ttf)") {
		return (pass);
	}
	
	# Other static content
	if (req.url ~ "\.(txt|sql|ini|conf)") {
		return (pass);
	}
}

#
# CSTM_PASS_STATIC_CONTENT_FETCH
# If the content received from the cache is "static" then remove
# any cookies and set it as non-cached. This might seem odd but
# it doesn't make sense to cache static files which you can get
# from the disk quickly enough.
#
# NOTE: The primary purpose of doing this in my configuration
# is to limit the in memory cache to actual dynamic content.
#
sub cstm_pass_static_content_fetch {
	# Images - alphabetical 
	if (req.url ~ "\.(bmp|gif|ico|jpg|jpeg|png|pgm|ppm|psd|svg|tif|tiff|webp|xcf)") {
		unset beresp.http.set-cookie;
		set beresp.http.X-Cacheable = "NO - Static Content";
		return (hit_for_pass);
	}

	# CSS & JS
	if (req.url ~ "\.(css|js)") {
		unset beresp.http.set-cookie;
		set beresp.http.X-Cacheable = "NO - Static Content";
		return (hit_for_pass);
	}

	# Fonts
	if (req.url ~ "\.(woff|eot|otf|ttf)") {
		unset beresp.http.set-cookie;
		set beresp.http.X-Cacheable = "NO - Static Content";
		return (hit_for_pass);
	}

	# Other static content
	if (req.url ~ "\.(xml|htm|html|txt|sql|ini|conf)") {
		unset beresp.http.set-cookie;
		set beresp.http.X-Cacheable = "NO - Static Content";
		return (hit_for_pass);
	}
}

#
# CSTM_KILL_GET_PARAMS_RECV
# Remove the GET parameters:
#  ver - cache busting timestamps for static files
#  google analytics params - because only needed in javascript
#      utm_source, utm_medium, utm_campaign, gclid, ...
#
sub cstm_kill_get_params_recv {
	set req.url = regsub(req.url, "\?ver=.*$", "");
	if (req.url ~ "(\?|&)(gclid|cx|ie|cof|siteurl|zanpid|origin|utm_[a-z]+|mr:[A-z]+)=") {
		set req.url = regsuball(req.url, "(gclid|cx|ie|cof|siteurl|zanpid|origin|utm_[a-z]+|mr:[A-z]+)=[%.-_A-z0-9]+&?", "");
    }
	# If there are no parameters left them remove the ?
    set req.url = regsub(req.url, "(\?&?)$", "");
}

#
# CSTM_IS_WP_SEARCH_RECV
# Passes the conten on if this is a search request.
#
sub cstm_is_wp_search_recv {
	if (req.url ~ "\?s=") {
		return (pass);
	}
}

#
# CSTM_IS_WP_SEARCH_FETCH
# Create a hit pass for search results.
#
sub cstm_is_wp_search_fetch {
	if (req.url ~ "\?s=") {
		return (hit_for_pass);
	}
}


#
# =========================     END CUSTOM     =========================
#

#
# VCL_INIT
# Called when VCL is loaded before any requests pass through.
# Simply return an ok to make sure VCL continues loading.
#
sub vcl_init {
	return (ok);
}

#
# VCL_RECV
# Called at the begining of a request after received from client.
# This subroutine should decide if varnish will serve the request,
# how to serve and the backend to use if passing to a backend.
#
sub vcl_recv {

	# Seems obvious but just in case - use the Apache backend
	if (! req.backend.healthy) {
		set req.grace = 1h;
	} else {
		set req.grace = 1m;
	}

	# Is this the first request? If so set the real client IP for backend.
	if (req.restarts == 0) {
		if (req.http.x-forwarded-for) {
			set req.http.X-Forwarded-For =
				req.http.X-Forwarded-For + ", " + client.ip;
		} else {
			set req.http.X-Forwarded-For = client.ip;
		}
	}

	# Forced refresh/cache miss
	if (req.http.X-REFRESH) {
		set req.hash_always_miss = true;
	}

	# Manipulate the URL to clean it up
	call cstm_kill_get_params_recv;

	# Check for cache purge requests
	call cstm_purge_recv;
	call cstm_do_not_cache_recv;

	# Make sure we have a valid HTTP verb
	if (req.request != "GET" &&
			req.request != "HEAD" &&
			req.request != "PUT" &&
			req.request != "POST" &&
			req.request != "TRACE" &&
			req.request != "OPTIONS" &&
			req.request != "DELETE") {
		# Non-RFC2616 or CONNECT so just pipe through to backend.
		return (pipe);
	}

	# Only cache data requests (POST should redirect to GET on success)
	if (req.request != "GET" && req.request != "HEAD") {
		return (pass);
	}

	# Compressed files do not need to be compressed again
	if (req.http.Accept-Encoding) {
		# To work around the IE6 (and only early versions of IE6 had it) bug with gzip
		if (req.http.user-agent ~ "MSIE 6") {
			unset req.http.accept-encoding;
		}

		# Normalize accept encoding because we return and don't fall to defaults
		if (req.url ~ "\.(jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|mp4|flv)$") {
			remove req.http.Accept-Encoding;
		} elsif (req.http.Accept-Encoding ~ "gzip") {
			set req.http.Accept-Encoding = "gzip";
		} elsif (req.http.Accept-Encoding ~ "deflate" && req.http.user-agent !~ "MSIE") {
			set req.http.Accept-Encoding = "deflate";
		} else {
		    # unkown algorithm
			remove req.http.Accept-Encoding;
		}
	}

	# Don't cache large files
	call cstm_binary_files_recv;

	# Check for WordPress cookies, admin, login and previews
	call cstm_has_wp_cookies_recv;
	call cstm_is_wp_admin_preview_recv;
	call cstm_is_wp_search_recv;
	call cstm_kill_cookies_recv;

	# Don't cache static content files
	call cstm_pass_static_content_recv;

	# -------- ADD YOUR CUSTOM RULES HERE --------
	# --------------------------------------------

	# Things requiring auth or cookies are not cacheable
	# NOTE: Cookies should be gone by now but just in case.
	if (req.http.Authorization || req.http.Cookie) {
		return (pass);
	}

	# Tell varnish to lookup the object in the cache which means
	# will go to either VCL_HIT or VCL_MISS depending on status.
	return (lookup);
}

#
# VCL_PIPE
# This basically creates a pipe between the backend and the client
# data passed between the two unaltered after this returns.
#
# This is just the default implementation. We're only piping for
# binary files that exist on disk so we don't need to close the
# connection for each request.
#
sub vcl_pipe {
    # Note that only the first request to the backend will have
    # X-Forwarded-For set.  If you use X-Forwarded-For and want to
    # have it set for all requests, make sure to have:
    # set bereq.http.connection = "close";
    # here.  It is not set by default as it might break some broken web
    # applications, like IIS with NTLM authentication.
    return (pipe);
}

#
# VCL_PASS
# Pass mode sends the backend response directly to the client and
# vice-versa. Data is not entered into the cache but can be modified
# by varnish in this subroutine.
#
# This is just the default implementation: just transfer data.
#
sub vcl_pass {
	return (pass);
}

#
# VCL_HASH
# Calculates a hash for how to find the content in the cache
# This is the default with an addition to look at the 
#  req.http.Accept-Encoding
# header because we adjust that in VCL_RECV
#
sub vcl_hash {
	# Hash based on the URL and host/server 
	hash_data(req.url);
    if (req.http.host) {
		hash_data(req.http.host);
	} else {
		hash_data(server.ip);
	}

	# Client compression because we need to cache for each type
	if (req.http.Accept-Encoding) {
		hash_data(req.http.Accept-Encoding);
	}

	# Return that hash was successful
    return (hash);
}

#
# VCL_HIT
# Called after a cache lookup when document is found in the cache.
#
sub vcl_hit {
	# If a PURGE was requested and not blocked by VCL_RECV then process
	if (req.request == "PURGE") {
		purge;
		error 200 "Purged";
	}

	# Deliver the content otherwise
	return (deliver);
}

#
# VCL_MISS
# Called after a cache lookup when document is NOT found in the cache.
#
sub vcl_miss {
	# If a PURGE was requested and not blocked by VCL_RECV then process
    if (req.request == "PURGE") {
        purge;
        error 200 "Purged";
    }

	# Send a request to the backend via returns via VCL_FETCH
    return (fetch);
}

#
# VCL_FETCH
# Called after a document has been retreived from the backend
#
sub vcl_fetch {
	# Remove the Apache / PHP headers
	unset beresp.http.Server;
	unset beresp.http.X-Powered-By;

	# If we get a server error of some form then restart with some more grace
	set beresp.grace = 1h;
	if (beresp.status == 500) {
		set beresp.saintmode = 20s;
		if (req.request != "POST") {
			return (restart);
		} else {
			error 500 "Failed";
		}
	}

	# Handle cookies, static pages and admin views
	call cstm_kill_cookies_fetch;
	call cstm_pass_static_content_fetch;
	call cstm_is_wp_admin_preview_fetch;
	call cstm_is_wp_search_fetch;

	# Don't cache PHP documents (obviously they're dynamic)
	if (req.url ~ "\.php$") {
		set beresp.http.X-Cacheable = "NO - PHP";
		return (hit_for_pass);
	}

	# If backend response is NOT 200.
	if (beresp.status != 200) {
		set beresp.http.Cache-Control = "max-age=0";
		set beresp.http.X-Cacheable = "NO - HTTP!=200";
		return (hit_for_pass);
	}

	# Finally don't cache things that require authentication
	if (req.http.Authorization) {
		return (hit_for_pass);
	}

	# GZip the cached content if possible
	if (beresp.http.content-type ~ "text") {
		set beresp.do_gzip = true;
	}

	# If we reach this point then content is cacheable
	set beresp.http.X-Cacheable = "YES";
	set beresp.ttl = 24h;
	return (deliver);
}

#
# VCL_DELIVER
# Called before a cached object is sent to the client
#
sub vcl_deliver {
	# Hide server headers
	unset resp.http.X-Powered-By;
	unset resp.http.Server;
	unset resp.http.Via;
	unset resp.http.X-Varnish;
	unset resp.http.X-Pingback;

	# Display the number of hits
	if (obj.hits > 0) {
		set resp.http.X-Cache = "HIT - " + obj.hits;
	} else {
		set resp.http.X-Cache = "MISS";
	}

	# Deliver the content
    return (deliver);
}

#
# VCL_ERROR
# Called when varnish hits an error
#
# NOTE: By not calling return (..) this will fall through
# to the default implementation. If you want a specific
# error message then define it here. See the VCL reference:
#  http://www.varnish-cache.org/docs/3.0/reference/vcl.html
#
sub vcl_error {
}

#
# VCL_FINI
# Called when VCL is discarded (after all requests have exited).
# Simply return an ok to make sure clean up works properly.
#
sub vcl_fini {
	return (ok);
}


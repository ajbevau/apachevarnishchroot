# Apache 2.4 Varnished CHROOTED PHP-FPM WordPress Virtual Host

Andrew Bevitt <me@andrewbevitt.com>

Read the [tutorial](http://andrewbevitt.com/tutorials/apache-varnish-chrooted-php-fpm-wordpress-virtual-host/) to learn how this all fits together.

The tutorial outlines how I configured an Ubuntu 12.04 LTS server to run:

* Apache 2.4 with the Event MPM
* Virtual hosts separated by users
* Each user having a chrooted home
* PHP 5.4 with FPM and APC
* WordPress
* Varnish
* MOD_WSGI

I spent about a week making sure this process is repeatable but of course I can't predict every scenario and configuration so please get in touch if you have some suggested improvements. The code, scripts and configuration files in this tutorial are released under an MIT license. See the LICENSE file in the download archive or [http://opensource.org/licenses/MIT](http://opensource.org/licenses/MIT) for details.

If you find this useful, and want to give something back, I accept [donations](http://andrewbevitt.com/donations/) for use in [Kiva](http://kiva.org).


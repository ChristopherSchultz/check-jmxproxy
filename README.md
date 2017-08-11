# check-jmxproxy
Nagios/Ichinga plug-in for obtaining samples from Tomcat's jmxproxy

Thie script is written in Perl.

## Perl Dependencies
You will need to install the following modules in order to use check-jmxproxy:

1. [Getopt::Long](http://search.cpan.org/~jv/Getopt-Long-2.50/lib/Getopt/Long.pm)
1. [LWP::UserAgent](http://search.cpan.org/~oalders/libwww-perl-6.26/lib/LWP/UserAgent.pm)
1. [HTTP::Request](http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Request.pm)
1. [HTTP::Response](http://search.cpan.org/~oalders/HTTP-Message-6.13/lib/HTTP/Response.pm)
1. [URI::Heuristic](http://search.cpan.org/~ether/URI-1.72/lib/URI/Heuristic.pm)

Most of these can be installed using the command `cpan install LWP::UserAgent` because the others are prerequisites for `LWP::UserAgent`.
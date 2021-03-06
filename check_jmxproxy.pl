#!/usr/bin/perl
#
# check_jmxproxy
#
# Contacts a JMX proxy (like that which Apache Tomcat provides)
# and compares the return value to the warning and critical values
# provided as parameters to this script.
#
# Copyright (c) 2012-2017 Christopher Schultz
#
# Christopher Schultz licenses this file to You under the Apache License,
# Version 2.0 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
# Special thanks to Susan Burgee for her help with Perl.
#
use strict;

# For getopt:
use Getopt::Long qw(:config no_ignore_case bundling);

# For strftime
use POSIX qw(strftime);

# For HTTP stuff:
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use URI::Heuristic;

my $help     = '';
my $url      = '';
my $warn     = '';
my $critical = '';
my $verbose = '';
my $authorization = '';
my $useragent = 'Nagios check_jmxproxy/0.1';
my $timeout = 180;
my $fetchingRegexp = '^OK.*=\s*([0-9]+)$';
# $fetchingRegexp = 'OK.*used=([0-9]+).*';
my $outputFilterRegexp;
my $writeFilename;
my $appendFilename;
my $compareFilename;

GetOptions(
    'U=s'             => \$url,
    'url=s'           => \$url,
    'w=s'             => \$warn,
    'warn=s'          => \$warn,
    'c=s'             => \$critical,
    'critical=s'      => \$critical,
    'h'               => \$help,
    'help'            => \$help,
    '+v'              => \$verbose,
    '+verbose'        => \$verbose,
    'a=s'             => \$authorization,
    'authorization=s' => \$authorization,
    'A'               => \$useragent,
    'useragent'       => \$useragent,
    't=i'             => \$timeout,
    'timeout=i'       => \$timeout,
    'r=s'             => \$fetchingRegexp,
    'regexp=s'        => \$fetchingRegexp,
    'R=s'             => \$outputFilterRegexp,
    'filtering-regexp=s' => \$outputFilterRegexp,
    'write=s'         => \$writeFilename,
    'append=s'        => \$appendFilename,
    'compare=s'       => \$compareFilename
) or $help = '-h';

$help = 1 if ( $url eq '' || $warn eq '' || $critical eq '' );

if( $help ) {
    print <<USAGE;
Usage: $0 [-v] [-a auth] [-A agent] -U <url> -w <warn> -c <critical>

Contacts a Tomcat jmxproxy to request a sample of information provided through
a JMX Bean. Information about Tomcat's jmxproxy can be found here:
http://tomcat.apache.org/tomcat-8.5-doc/manager-howto.html#Using_the_JMX_Proxy_Servlet

  -A, --useragent
    Specify the User-Agent that will be sent when contacting the server.

  -a, --authorization
    Specify the BASIC authorization string that will be used to satisfy
    a WWW-Authenticate challenge. Should be in the form 'user:password'.

  -c, --critical
    Specifies the 'critical' level against which the number returned
    from the JMX proxy will be compared. Append a ':' to the end of
    the critical value in order to perform a less-than comparison.

  -h, --help
    Shows this help message.

  -r, --regexp
    Specifies the regular expression that will be used to capture the
    numeric portion of the JMX proxy's response. The first capture group
    in the regular expression will be used as the numeric response.
    Default: '^OK.*=\\s*([0-9]+)\$'

  -R, --filtering-regexp
    Specifies the regular expresison that will be used to filter the
    response from the JMX proxy before echoing it to the output stream
    after a "JMX OK", "JMX WARN", or "JMX CRITICAL" message. If the
    response from the JMX proxy is malformed, the response will not be
    filtered.

  -t, --timeout
    Specifies the timeout, in seconds, to wait for a response before
    the request to the server is considered a failure. Default is 180
    (3 minutes).

  -U, --url
    Specifies the URL that check_jmxproxy will contact.

  -v, --verbose
    Enabled verbose logging of what check_jmxproxy is doing.

  -w, --warn
    Specifies the 'warning' level against which a number returned
    from the JMX proxy will be compared. Append a ':' to the end of
    the warning value in order to perform a less-than comparison.

  --write filename
    Specifies a filename to which the (possibly filtered) sample will be
    written. Only the most recent sample will be present in the file.
    
  --append filename
    Specifies a filename to which the (possibly filtered) sample will be
    appended with a leading date/time stamp. This keeps a running log of
    samples.

  --compare filename
    Compares the current sample with sample previously collected with --write.
    Sample-checking becomes relative to the previously-collected value instead
    of an absolute value.

Examples:
  \$ ${0} -U 'http://host/manager/jmxproxy?get=java.lang:type=Memory&att=HeapMemoryUsage&key=used' -w 33554432 -c 50331648

  This example will report CRITICAL if the current JVM heap size exceeds
  48MiB or WARN if the heap size exceeds 32MiB.

  \$ ${0} -U 'http://host/manager/jmxproxy?get=Catalina%3Atype%3DManager%2Ccontext%3D%2FMyWebapp%2Chost%3Dlocalhost&att=activeSessions' -w 10 -c 20 -r '^OK.*=\\s*([0-9]+)\\s*$$' --write /tmp/sessions.value --compare /tmp/sessions.value

  This example will report CRITICAL if the session count is greater than 20
  more than the previously-collected value, or WARN if the session count is
  greater than 10 more than the previously-colelcted value.

USAGE
    exit();
}

if ($verbose) {
  print "url = $url\n" if ($url);
  print "cricital = $critical\n" if ($critical);
  print "warn = $warn\n" if ($warn);
}

my $comparisonValue;

if($compareFilename) {
  if(open(DATA, "<$compareFilename")) {
  $comparisonValue = <DATA>;
  chomp($comparisonValue);
  close(DATA);
  printf "(v) loaded comparison value %s from %s\n", $comparisonValue, $compareFilename if $verbose;
  } else {
    printf "(v) no comparison value could be loaded from %s. Delta will be 0.\n", $compareFilename if $verbose;
    $comparisonValue = 'none';
  }
}

my $full_url = URI::Heuristic::uf_urlstr($url);
my $ua = LWP::UserAgent->new();
$ua->agent($useragent);
my $req = HTTP::Request->new(GET => $url);

# Set the authentication information if necessary
if (!($authorization eq '')) {
  $req->authorization_basic(split /:/, $authorization, 2);
}

$ua->timeout($timeout);

my $response = $ua->request($req);

if ($response->is_error()) {
  printf "JMX CRITICAL: Response: %s\n", $response->status_line;
  exit 2;
} else {
  my $content = $response->content();

  # Remove any trailing newlines
  chomp($content);

  if($verbose) {
    print "(v) Using fetching regexp '$fetchingRegexp'\n";
  }
  my($num) = ($content =~ /$fetchingRegexp/);

  if($verbose) {
    print "(v) Response from JMX proxy: '$content'\n";
    print "(v) got number from JMX: $num\n";
  }

  if($num eq '') {
    printf "JMX CRITICAL: Bad Response: %s\n", $content;
    exit 2;
  } else {
    if($outputFilterRegexp) {
      print "Filtering JXM proxy response using filter: $outputFilterRegexp" if $verbose;
      ($content) = $content =~ /$outputFilterRegexp/;
    }

    if($appendFilename) {
      printf "(v) appending %s to %s\n", $num, $appendFilename if $verbose;
      open(DATA, ">>$appendFilename");
      print DATA strftime "%Y-%m-%d %H:%M:%S", localtime();
      print DATA " ";
      print DATA "$num\n";
      close(DATA);
    }
    if($writeFilename) {
      printf "(v) writing %s to %s\n", $num, $writeFilename if $verbose;
      open(DATA, ">$writeFilename");
      print DATA "$num\n";
      close(DATA);
    }

    if($comparisonValue) {
      if('none' == $comparisonValue) {
        printf "(v) No previous comparison value. Setting delta to 0.\n" if $verbose;
        $num = 0;
      } else {
      printf "(v) adjusting %s by comparison value %s\n", $num, $comparisonValue if $verbose;
        $num -= $comparisonValue;
        $content .= ", delta=" . $num;
      }
    }

    if ($critical =~ /:$/) {
      printf "(v) checking if %s < %s (critical)\n", $num, $critical if $verbose;

      if($num < $critical) {
        print "(v) $num < $critical\n" if $verbose;
        printf "JMX CRITICAL: %s\n", $content;
        exit 2;
      } elsif ($warn =~ /:$/) {
        printf "(v) checking if %s < %s (warn)\n", $num, $warn if $verbose;

        if($num < $warn) {
          print "(v) $num < $warn\n" if $verbose;

          printf "JMX WARN: %s\n", $content;
          exit 1;
        } else {
          print "(v) $num > $warn\n" if $verbose;

          printf "JMX OK: %s\n", $content;
        }
      } elsif ($num > $warn) {
        print "(v) $num > $warn\n" if $verbose;

        printf "JMX WARN: %s\n", $content;
        exit 1;
      } else {
        print "(v) $num < $warn\n" if $verbose;

        printf "JMX OK: %s\n", $content;
      }
    } else {
      if($num > $critical) {
        print "(v) $num > $critical\n" if $verbose;

        printf "JMX CRITICAL: %s\n", $content;
        exit 2;
      } elsif ($warn =~ /:$/) {
        if($num < $warn) {
          print "(v) $num < $warn\n" if $verbose;

          printf "JMX WARN: %s\n", $content;
          exit 1;
        } else {
          print "(v) $num > $warn\n" if $verbose;

          printf "JMX OK: %s\n", $content;
        }
      } elsif ($num > $warn) {
        print "(v) $num > $warn\n" if $verbose;

        printf "JMX WARN: %s\n", $content;
        exit 1;
      } else {
        print "(v) $num < $warn\n" if $verbose;

        printf "JMX OK: %s\n", $content;
      }
    }
  }
}

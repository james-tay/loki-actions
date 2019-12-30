#!/usr/bin/perl -w
#
# This script takes an smtp server as its only argument, reads an email
# on standard input, and delivers it to the smtp server for relaying to
# the final destination. For example,
#
#  % mailsend.pl smtp.mycompany.com < myemail.txt
#
# Where "myemail.txt" contains the necessary mail headers, as well as
# the body text. For example,
#
#  From: smith@example.com
#  To: john@company.net
#  Subject: hello world
#  Date: Sun, 16 Nov 2008 16:25:38 +0800
#
#  this is my message
#

use Socket ;

# -----------------------------------------------------------------------------

my $timeout = 10 ;	# smtp inactivity timeout (seconds) 
my $line = "" ;		# general purpose line buffer
my $host = "" ;		# the remote host that we'll connect to
my $mail_from = "" ;	# "From:" pulled off mail headers
my $rcpt_to = "" ;	# "To:" pulled off mail headers
my @header = () ;	# array of lines, which form the mail headers

# -----------------------------------------------------------------------------

# This function is supplied a email address in the format
#   Joe Smith <joe@example.com>
# and it returns :
#   joe@example.com

sub f_email_addr
{
  my $addr = $_[0] ;

  $addr =~ s/^.+\<//g ;
  $addr =~ s/\>.*$//g ;
  return ($addr) ;
}

# This function sends a line to the remote smtp server, and reads a reply.
# The first argument is expected to be an established tcp connection. The
# line is supplied as the second argument, and the expected smtp reply
# code (number) is specified as the third argument. If the supplied smtp
# code is received, we return an empty string, otherwise something is
# presumed to have gone wrong and we return the entire reply string.
# Finally, an inactivity timeout is enforced. If triggered, the string
# "inactivity timed out" is returned.

sub f_smtp_dialog
{
  my $fd = $_[0] ;
  my $msg = $_[1] ;
  my $expect = $_[2] ;
  my $buf = "" ;

  # deliver a message to the remote smtp server, if one is specified.

  if (length ($msg) > 0)
    { printf ($fd "$msg") ; }

  eval
  {
    alarm ($timeout) ;
    $buf = <$fd> ;
    alarm (0) ;
  } ;

  if ($buf =~ /^$expect/)
    { return ("") ; }
  chomp ($buf) ;
  return ($buf) ;
}

# -----------------------------------------------------------------------------

# check usage first ...

if ($#ARGV != 0)
{
  printf ("Usage : %s <smtp server> < mail.txt\n", $0) ;
  exit (1) ;
}

# try to read in mail header from stdin.

while ($line = <STDIN>)
{
  chomp ($line) ;
  if ($line =~ /^To:/)
  {
    $rcpt_to = $line ;
    $rcpt_to =~ s/To: // ;
    $rcpt_to = f_email_addr ($rcpt_to) ;
  }
  if ($line =~ /^From:/)
  {
    $mail_from = $line ;
    $mail_from =~ s/From: // ;
    $mail_from = f_email_addr ($mail_from) ;
  }
  if ($line =~ /^$/)
  {
    last ;
  }
  $header[$#header+1] = $line ;
}

# check that we know who we're sending mail from, and to.

if (length ($mail_from) < 1)
{
  printf ("FATAL! Do not know who this mail is from. No 'From: xx'.\n") ;
  exit (1) ;
}
if (length ($rcpt_to) < 1)
{
  printf ("FATAL! Do not know who this mail is to. No 'To: xx'.\n") ;
  exit (1) ;
}

# now attempt to connect to smtp server.

$host = inet_aton ($ARGV[0]) ||
  die ("FATAL! Host not found $ARGV[0],$!") ;
socket ($SD, PF_INET, SOCK_STREAM, getprotobyname ("tcp")) ||
  die ("FATAL! socket() failed,$!") ;

eval
{
  local $SIG{ALRM} = sub
    { printf ("FATAL! Connect to $ARGV[0] timed out.\n") ; exit (1) ; } ;
  alarm ($timeout) ;
  connect ($SD, sockaddr_in (25, inet_aton ($ARGV[0]))) ||
    die ("FATAL! Cannot connect to $ARGV[0] on port 25,$!") ;
  alarm (0) ;
} ;

# Force socket to be flushed right away after every write or printf.

select ($SD) ;
$| = 1 ;
select (STDOUT) ;
printf ("NOTICE: Connected to $ARGV[0].\n") ;

# perform the standard dialog with the smtp server.

$line = f_smtp_dialog ($SD, "", 220) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; exit (1) ; }

printf ("NOTICE: Sending HELO.\n") ;
$line = f_smtp_dialog ($SD, "HELO localhost\r\n", 250) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; exit (1) ; }

printf ("NOTICE: Sending MAIL FROM.\n") ;
$line = f_smtp_dialog ($SD, "MAIL FROM: <$mail_from>\r\n", 250) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; exit (1) ; }

printf ("NOTICE: Sending RCPT TO.\n") ;
$line = f_smtp_dialog ($SD, "RCPT TO: <$rcpt_to>\r\n", 250) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; exit (1) ; }

printf ("NOTICE: Sending DATA.\n") ;
$line = f_smtp_dialog ($SD, "DATA\r\n", 354) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; exit (1) ; }

# now print out the mail header and read the rest of the mail body.

printf ("NOTICE: Now transmitting header.\n") ;
foreach (@header)
  { print ($SD "$_\r\n") ; }
print ($SD "\r\n") ;
printf ("NOTICE: Now transmitting body.\n") ;
while ($line = <STDIN>)
  { chomp ($line) ; print ($SD "$line\r\n") ; }

printf ("NOTICE: Finishing up body.\n") ;
$line = f_smtp_dialog ($SD, ".\r\n", 250) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; }

printf ("NOTICE: Now transmitting quit.\n") ;
$line = f_smtp_dialog ($SD, "QUIT\r\n", 221) ;
if (length ($line) > 0)
  { printf ("FATAL! $ARGV[0] said: %s\n", $line) ; }

printf ("NOTICE: Completed.\n") ;
exit (0) ;


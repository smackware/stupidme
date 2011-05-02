#!/usr/bin/env perl
use strict;
use warnings;

our $DB_NAME = "stupidme";
our $DB_PATH = "/tmp/";
our $LOG_PATH = "$DB_PATH/$DB_NAME.log";
our $DISPATCH_PID_PATH = "$DB_PATH/$DB_NAME.pid";

our $HOUR = 3600;
our $WEEK = $HOUR*24*7;

*STDERR = *STDOUT;
open STDOUT, ">> $LOG_PATH" or die "Failed opening log file";

sub start_dispatcher($) {
    my ($pid_filepath) = @_;
    if (my $pid = fork()) {
        open(my $pid_fh, ">", $pid_filepath) or die "Failed to open pid file: $pid_filepath: $!\n";
        print $pid_fh $pid;
        close($pid_fh);
        return;
    }
    while (1) {
        sleep(30);
        my $now = time();
        for my $filepath ( glob("$DB_PATH/*.next_delivery") ) {
            $filepath =~ /^(.+)\.next_delivery$/;
            my $body_filepath = "$1.body";
            open(my $fh, "<", $filepath) or next;
            chomp(my ($when, $to, $subject) = <$fh>);
	    close($fh);
            if ($when < $now) {
                print "Sending '$subject' to $to...\n";
                if (system("cat $body_filepath | mail -s '$subject' $to")) {  warn "Failed sending $body_filepath ($subject) to $to\n"; }
		else { rename($filepath, "$filepath.sent"); }
            }
        }
    }
    exit(0); # Never get here...
}

my $buffer;
my $body = "";
my $key;
my $from = "";
my $subject = "";

my $header_end = 0;
while ($_ = <STDIN>) {
    if ($from eq '' and /^From:.*\s<?([^\s]+@[^\s>]+)>?.*/) { $from = $1; }
    elsif ($subject eq '' and /^Subject:\s(.+)$/) { $subject = $1; }
    $_ eq "\n" and $header_end = 1;
    $body.= $_ if $header_end;
}
if ($subject =~ /::(\X+)/) {
   $key = $1;
   die "No such account: $key.\n" unless ( -f "$DB_PATH/$key.body" );
} else {
   $key = join('', map(sprintf('%X', ord($_)), split('', crypt($from, int(rand(99))))));
   print "Creating new account with key: $key\n";
   $subject .= "$subject ::$key";
}
print "Received from: $from ($key)\n";

my $mail_filepath = "$DB_PATH/$key.body";
my $timestamp_filepath = "$DB_PATH/$key.next_delivery";
my $delivery_timestamp = int(rand($WEEK)) + ($HOUR*6) + int(time());
die "Failed to open mail file: $mail_filepath\n" unless open(my $mail_fh, ">", "$mail_filepath");
die "Failed to open timestamp file: $timestamp_filepath\n" unless open(my $time_fh, ">", "$timestamp_filepath");
print "Will deliver on $delivery_timestamp, to $from\n";
print $mail_fh $body;
print $time_fh "$delivery_timestamp\n$from\n$subject\n";
close($mail_fh);
close($time_fh);

# Fire-up the dispatcher daemon unless its up already
my $pid = 0;
if (open(my $pid_fh, "<", $DISPATCH_PID_PATH)) {
    chomp($pid = <$pid_fh>);
    close($pid_fh);
}
if ($pid and kill(0, $pid)) {
    print "Existing daemon pid is $pid.\n";
} else {
    print "Starting dispatcher daemon...\n";
    start_dispatcher($DISPATCH_PID_PATH);
}

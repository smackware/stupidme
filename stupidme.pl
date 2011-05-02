use strict;
use warnings;

our $DB_NAME = "pastme";
our $DB_PATH = "/tmp/$DB_NAME";
our $DISPATCH_PID_PATH = "/tmp/$DB_NAME.pid";

our $HOUR = 3600;
our $WEEK = $HOUR*24*7;

sub start_dispatcher($) {
    my ($pid_filepath) = @_;
    if (my $pid = fork()) {
        open(my $pid_fh, ">", $pid_filepath) or die "Failed to open pid file: $pid_filepath: $!\n";
        print $pid_fh $pid;
        close($pid_fh);
        return;
    }
    while (1) {
        sleep(20);
        my $now = time();
        my @delivery_files = glob("$DB_PATH/*.next_delivery");
        for my $filepath (@delivery_files) {
            $filepath =~ /^(.+)\.next_delivery$/;
            my $body_filepath = "$1.body";
            open (my $fh, "<", $filepath) or next;
            chomp(my $when = <$fh>);
            chop(my $to = <$fh>);
            chomp(my $subject = "Re: ".<$fh>);
            if ($when < $now) {
                print "Sending '$subject' to $to...\n";
                system("cat $body_filepath | mail -s '$subject' $to") and warn "Failed sending $body_filepath ($subject) to $to\n";
		rename($filepath, "$filepath.sent")
            }
        }
    }
    exit(0); # Never get here...
}

my $buffer;
my $body = "";
my $body_tail = "";
my $key;
my $from = "";
my $new = 0;
my $subject = "";

my $header_end = 0;
while ($_ = <STDIN>) {
    if ($from eq '' and /^From:.*\s<?([^\s]+@[^\s]+)>?.*/) { $from = $1; }
    elsif ($subject eq '' and /^Subject:\s(.+)$/) { $subject = $1; }
    $_ eq "\n" and $header_end = 1;
    $body.= $_ if $header_end;
}
print "Received from: $from\n";
if ($body_tail =~ /[\r\n]KEY::([0-9A-F]+)/) { 
    $key = $1; 
    print "Got mail with key: $key\n";
} else { 
   $key = crypt($from, int(time()));
   print "Creating new account with key: $key\n";
   $body .= "\n\n\n\nKEY::$key\n\n";
   $new = 1;
}

my $mail_filepath = "$DB_PATH/$key.body";
die "No such account.\n" unless ( -f $mail_filepath or $new );
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
print "Daemon pid is $pid.\n";
unless ($pid and kill(0, $pid)) {
    print "Starting dispatcher daemon...\n";
    start_dispatcher($DISPATCH_PID_PATH);
}

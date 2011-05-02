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
        sleep(30);
        my $now = time();
        my @delivery_files = glob("$DB_PATH/*.next_delivery");
        for my $filepath (@delivery_files) {
            $filepath =~ /^(.+)\.next_delivery$/;
            my $body_filepath = "$1.body";
            open (my $fh, "<", $filepath) or next;
            my $when = <$fh>;
            my $to = <$fh>;
            my $subject = "Re: ".<$fh>;
            if ($when < $now) {
                print "Sending '$subject' to $to...";
                system("cat $body_filepath | mail -s '$subject' $to") and warn "Failed sending $body_filepath ($subject) to $to\n";
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

while (my $byte_count = read(STDIN, $buffer, 1024)) {
    $body.= $buffer;
    $body_tail = $byte_count < 1024 ? $body_tail.$buffer : $buffer;
    if ($from eq "" and $body =~ /^From:\s*([^\n\r]+)/m) {
        $from = $1;
        $from =~ /\<(.+@.+)\>/ and $from = $1;
    }
    if ($subject eq "" and $body =~/^Subject:\s(.+)$/m) {
        $subject = $1;
    }
}
1 while( shift(@$body) ne "\n");
print "Received from: $from\n";
if ($body_tail =~ /[\r\n]KEY::([0-9A-F]+)/) { 
    $key = $1; 
    print "Got mail with key: $key\n";
} else { 
   $key = crypt($from, int(time()));
   print "Creating new account with key: $key\n";
   $body .= "\n\n\n\nKEY::$key\n";
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

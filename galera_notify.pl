#!/usr/bin/env perl

# Created by Pavel Raykov aka 'rabbit' / 2015-03-24 (c)

use strict;
use warnings;
use Sys::Hostname;
use Getopt::Long;

my $hostname = hostname || 'unknown';
my $options  = Getopt::Long::Parser->new();
my $message  = '';
my %members  = ();
my %smtp_settings = (
			to   => 'email_to_notify@example.com',
			from => 'galera-notify@'.$hostname,
			subj => 'Galera status changed on',
		    );
my %galera = (
		uuid    => '',
		status  => '',
		primary => '',
		index   => '',
		members => '',
	     );

sub PrintUsage()
{
    printf "Usage: %s <options>\n\n", __FILE__;
    printf "Options:\n";
    printf "\t--uuid <UUID>\n";
    printf "\t--status <status str>\n";
    printf "\t--primary <yes/no>\n";
    printf "\t--index <n>\n";
    printf "\t--members <members UUID>\n";

    exit 1;
}

sub SendEmail($)
{
    my $body = shift;
    my $sendmail = "/usr/sbin/sendmail";

    #open(MAIL, "|cat")
    open(MAIL, "|$sendmail -t")
	or die "Can't execute $sendmail: $?";
 
	# Message
	print MAIL "To: $smtp_settings{'to'}\n";
	print MAIL "From: $smtp_settings{'from'}\n";
	print MAIL "Subject: $smtp_settings{'subj'}\n\n";
	print MAIL $body;
    close(MAIL);
}

# --------------------------------------------------
# Main code
# --------------------------------------------------

$options->configure("no_ignore_case", "no_auto_abbrev");
$options->getoptions(
                        "help|h|?"  => \&PrintUsage,
			"uuid=s"    => \$galera{'uuid'},
			"status=s"  => \$galera{'status'},
			"primary=s" => \$galera{'primary'},
			"index=s"   => \$galera{'index'},
			"members=s" => \$galera{'members'},
                    ) or die("Error in command line arguments, check usage information\n");

# Checking required parameters
PrintUsage() unless ($galera{'status'});

# Parsing nodes membership
if ($galera{'members'})
{
    my $index = 0;

    foreach my $member (split ',', $galera{'members'})
    {
	if ($member =~ m#^(?<_uuid>[-0-9a-f]{36})/(?<_hostname>.+)/(?<_socket>([0-9]{1,3}\.){3}([0-9]{1,3}):[0-9]+$)?#)
	{
	    my $_hostname = $+{_hostname} || '';

	    if ($_hostname)
	    {
		$members{$_hostname}{'index'}  = defined($index) ? $index : '';
		$members{$_hostname}{'uuid'}   = $+{_uuid}   || '';
		$members{$_hostname}{'socket'} = $+{_socket} || '';
	    }
	}

	$index++;
    }
}

# Updating message body (if required)
$message  = "Galera cluster status:\n";
$message  = "Galera cluster (" . $galera{'uuid'} .") status:\n" if ($galera{'uuid'});
$message .= "\n\t". $galera{'status'} ." (Node ";
$message .= "is not in the cluster"			if ($galera{'status'} =~ /Undefined/);
$message .= "is receiving a state snapshot transfer"	if ($galera{'status'} =~ /Joiner/);
$message .= "is now allowed to process transactions"	if ($galera{'status'} =~ /Joined/);
$message .= "is sending a state snapshot transfer"	if ($galera{'status'} =~ /Donor/);
$message .= "is synchronized with the cluster"		if ($galera{'status'} =~ /Synced/);
$message .= "has error"					if ($galera{'status'} =~ /Error/);
$message .= ")";

if (int(keys(%members)) > 0)
{
    $message .= "\n\nAffected component members:\n";

    foreach my $member (sort keys %members)
    {
	next unless $member;

	($members{$member}{'index'} == $galera{'index'})
	    ? ($message .= "-> ")
	    : ($message .= "   ");

	$message .= sprintf("%-15s\t%-23s\t%-32s\n", $member, $members{$member}{'socket'}, $members{$member}{'uuid'});
    }
}

# Updating subject
$smtp_settings{'subj'} .= " ". $hostname. " (". $galera{'status'};
$smtp_settings{'subj'} .= ", Primary: ". $galera{'primary'} if ($galera{'primary'});
$smtp_settings{'subj'} .= ")";

# Sending email message
SendEmail($message);

__END__


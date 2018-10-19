#!/usr/bin/env perl

use strict;
use warnings;

use LWP;
use URL::Encode qw(url_encode);

my $req = HTTP::Request->new(
    GET => 
    "https://maker.ifttt.com/trigger/phone_notify/with/key/$ENV{IFTTT_API_KEY}?value1=".`hostname`."&value2=".url_encode(join(' ', @ARGV))
);

my $res = LWP::UserAgent->new->request($req);
if(!$res->is_success) {
    print STDERR "Failed: ".$res->content."\n";
    exit(1);
} else {
    print "OK\n";
    exit(0);
}

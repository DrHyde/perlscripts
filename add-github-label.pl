#!/usr/bin/env perl

use strict;
use warnings;

use JSON::Parse qw(parse_json);
use LWP::UserAgent;

my($noisy, $target, $label, $colour, $owner, $token) = (1, '');

while(@ARGV) {
    my $arg = shift();
    if($arg eq '--quiet') { $noisy-- }
     elsif($arg eq '--label')  { $label  = shift() }
     elsif($arg eq '--colour') { $colour = shift() }
     elsif($arg eq '--owner')  { $owner  = shift() }
     elsif($arg eq '--token')  { $token  = shift() }
     elsif($arg eq '--target') { $target = shift() } # specify this to update a forked repo, they're stkipped otherwise
     else { die("$arg is unrecognized\n"); }
}

die("--owner is compulsory\n") unless($owner);
die("--token is compulsory\n") unless($token);
die("--label is compulsory\n") unless($label);
die("--colour is compulsory and must be six hex digits\n")
    unless($colour && $colour =~ /[0-9A-F]{6}/i);

my $ua = LWP::UserAgent->new();

my $next_url = "https://api.github.com/users/$owner/repos";

while($next_url) {
    my $req = HTTP::Request::WithAuth->new(GET => $next_url);
    print "  fetching $next_url\n" if($noisy);
    my $res = $ua->request($req);
    if(!$res->is_success()) {
        die("Couldn't fetch $next_url; ".$res->status_line()."\n");
    }

    if($res->header('Link') && $res->header('Link') =~ /<([^>]+)>;\s+rel="next"/) {
        $next_url = $1;
    } else {
        $next_url = '';
    }

    my $repos = parse_json($res->content());
    my @repos = grep { $_->{name} eq $target || !$_->{fork} } @{$repos};

    REPO: foreach my $repo (@repos) {
        my $full_name = $repo->{full_name};
        (my $send_url = $repo->{labels_url}) =~ s/\{.*//;
        my $send_method  = 'POST';

        my $check_label_exists_req = HTTP::Request::WithAuth->new(GET => "$send_url/$label");
        my $res = $ua->request($check_label_exists_req);
        if($res->is_success()) {
            my $label_data = parse_json($res->content());
            if(lc($label_data->{color}) eq lc($colour)) {
                print "Label '$label' with colour '$colour' already exists for $full_name, skipping\n";
                next REPO;
            } else {
                print "Label '$label' exists with wrong colour for $full_name, updating\n";
                $send_method  = 'PATCH';
                $send_url    .= "/$label";
            }
        }

        my $create_label_req = HTTP::Request::WithAuth->new($send_method  => $send_url);
        $create_label_req->header('Content-Type'  => 'application/json');
        my $name_or_new_name = ($send_method eq 'PATCH') ? 'new_name' : 'name';
        $create_label_req->content('{"'.$name_or_new_name.'":"'.$label.'","color":"'.$colour.'"}');
        $res = $ua->request($create_label_req);
        if(!$res->is_success()) {
            die("Couldn't post to $send_url: ".$res->status_line()."\n".$res->content()."\n");
        } else {
            print "Created/updated label $label with colour $colour on $full_name\n";
        }
    }
}

package HTTP::Request::WithAuth;
use MIME::Base64;
use base 'HTTP::Request';
sub new {
    my($class, @args) = @_;
    my $req = $class->SUPER::new(@args);
    $req->header('Authorization' => "Bearer $token");
    $req->header('X-GitHub-Api-Version' => '2022-11-28');

    return $req;
}

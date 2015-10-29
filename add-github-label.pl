use strict;
use warnings;

use JSON::Parse qw(parse_json);
use LWP::UserAgent;
use MIME::Base64;

my($noisy, $label, $colour, $owner, $user, $pass) = (1);

while(@ARGV) {
    my $arg = shift();
    if($arg eq '--quiet') { $noisy-- }
     elsif($arg eq '--label')  { $label  = shift() }
     elsif($arg eq '--colour') { $colour = shift() }
     elsif($arg eq '--owner')  { $owner  = shift() }
     elsif($arg eq '--user')   { $user   = shift() }
     elsif($arg eq '--pass')   { $pass   = shift() }
     else { die("$arg is unrecognized\n"); }
}

die("--owner is compulsory\n") unless($owner);
die("--user is compulsory\n")  unless($user);
die("--pass is compulsory\n")  unless($pass);
die("--label is compulsory\n") unless($label);
die("--colour is compulsoryi and must be six hex digits\n")
    unless($colour && $colour =~ /[0-9A-F]{6}/i);

my $ua = LWP::UserAgent->new();

my $next_url = "https://api.github.com/users/$owner/repos";

while($next_url) {
    my $req = HTTP::Request->new(GET => $next_url);
    print "  fetching $next_url\n" if($noisy);
    my $res = $ua->request($req);
    if(!$res->is_success()) {
        die("Couldn't fetch $next_url; ".$res->status_line()."\n");
    }

    if($res->header('Link') =~ /^<(.*)>;\s+rel="next"/) {
        $next_url = $1;
    } else {
        $next_url = '';
    }

    my $repos = parse_json($res->content());
    my @repos = grep { !$_->{fork} } @{$repos};
    
    REPO: foreach my $repo (@repos) {
	my $full_name = $repo->{full_name};
        (my $labels_url = $repo->{labels_url}) =~ s/\{.*//;
	my $check_label_exists_req = HTTP::Request->new(GET => "$labels_url/$label");
	my $res = $ua->request($check_label_exists_req);
	if($res->is_success()) {
	    print "Label '$label' already exists for $full_name, skipping\n";
	    next REPO;
	} else {
	    my $create_label_req = HTTP::Request->new(POST => "$labels_url");
	    $create_label_req->header('Content-Type'  => 'application/json');
	    $create_label_req->header('Authorization' => 'Basic '.encode_base64("$user:$pass"));
	    # use Data::Dumper;
	    # die(Dumper($create_label_req));
	    $create_label_req->content('{"name":"'.$label.'","color":"'.$colour.'"}');
	    my $res = $ua->request($create_label_req);
	    if(!$res->is_success()) {
	        die("Couldn't post to $labels_url: ".$res->status_line()."\n".$res->content()."\n");
	    } else {
	        print "Created label $label with colour $colour on $full_name\n";
	    }
	}
    }
}

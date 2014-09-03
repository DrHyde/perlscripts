#!/home/david/perl5/perlbrew/perls/perl-5.20.0/bin/perl

use strict;
use warnings;

use Template;
use Data::Dumper;
use MIME::Types;
use File::Slurp;
use Getopt::Long;
use HTTP::Date;

my($source, $target, $httpdir);

GetOptions(
    'source=s' => \$source,
    'target=s' => \$target,
    'httpdir=s' => \$httpdir,
);

die("source must be a directory\n") unless(-d $source);
die("target must be a directory\n") unless(-d $target);
die("httpdir must be sane\n") unless($httpdir =~ /^https?:\/\//);

opendir(SOURCE, $source) || die("Can't read $source\n");
my @files = grep { -f "$source/$_" && $_ =~ /\.(mp3|m4a|mp4|m4v)$/ } readdir(SOURCE);
closedir(SOURCE);
foreach my $file (@files) {
    unlink("$target/$file");
    link("$source/$file", "$target/$file");
}

Template->new()->process(
# print Dumper(
    \(''.read_file(\*DATA)),
    {
        title => "Podcast of $source",
        homepage => $httpdir,
        description => "The media files from $source",
        pubdate => time2str(),
        items => [ map {
            my ($size, $mtime) = (stat("$target/$_"))[7, 9];
            {
                title => $_,
                description => $_,
                pubdate => time2str($mtime),
                size => $size,
                url => "$httpdir/$_",
                mime => MIME::Types->new()->mimeTypeOf("$target/$_"),
            }
        } sort { (stat("$target/$a"))[9] <=> (stat("$target/$b"))[9] } @files ]
    },
    "$target/feed.xml"
);

__DATA__
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:wfw="http://wellformedweb.org/CommentAPI/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <!-- fuck yeah this is cargo culted. i dunno shit about podcasts -->
    <title>[% title %]</title>
    <link>[% homepage %]</link>
    <description>[% description %]</description>
    <pubDate>[% pubdate %]</pubDate>
    [% FOREACH item IN items %]
    <item>
      <title>[% item.title %]</title>
      <description>[% item.description %]</description>
      <pubDate>[% item.pubdate %]</pubDate>
      <enclosure url="[% item.url %]" type="[% item.mime %]" length="[% item.size %]"/>
    </item>
    [% END %]
  </channel>
</rss>

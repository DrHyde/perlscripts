#!/usr/bin/env perl

=head1 NAME

mkpodcasts

=head1 DESCRIPTION

Turn a directory of media files into a podcast

=head1 ARGUMENTS

The first three arguments are mandatory.

=head2 --source

The directory to get files from. Currently files ending in .mp3, .m4a, .mp4,
or .m4v are considered media files.

=head2 --target

The directory to put the podcast in. This must not be the same as the source,
but must be on the same filesystem because hard-links are created for the
media files. If it doesn't exist it will be created. If it does exist its
contents will be deleted before it is populated. A 'feed.xml' file is also
created. An 'update.sh' file is also created which, when run, will re-scan the
source and re-build the target.

=head2 --httpdir

The address in HTTP-land of the directory containing the podcast

=head2 --sortby (optional)

Podcast items will be sorted by this field. Valid values are 'mtime' and 'name'.

=head1 AUTHOR, LICENCE, ETC

Written by David Cantrell <david@cantrell.org.uk>.

You may use, modify and distribute this software in accordance with the
terms laid out in the GNU General Public Licence version 2.

=cut

use strict;
use warnings;

use Cwd;
use Template;
use Data::Dumper;
use MIME::Types;
use File::Slurp;
use Getopt::Long;
use HTTP::Date;
use Pod::Usage;

my $sortby = 'mtime';
my($source, $target, $httpdir, $help);

GetOptions(
    'source=s'  => \$source,
    'target=s'  => \$target,
    'sortby=s'  => \$sortby,
    'httpdir=s' => \$httpdir,
    'help|?'    => \$help,
);

sub spew_args {
    print "You said:\n";
    print "  --source  '$source'\n"  if(defined($source));
    print "  --target  '$target'\n"  if(defined($target));
    print "  --httpdir '$httpdir'\n" if(defined($httpdir));
    print "  --sortby  '$sortby'\n"  if(defined($sortby));
    print "\n";
}

pod2usage(0) if($help);

my %sorters = (
    mtime => sub { (stat($_[0]))[9] <=> (stat($_[1]))[9] },
    name  => sub { $_[0] cmp $_[1] },
);

unless($source && -d $source) {
    spew_args();
    pod2usage({ -message => "source must be a directory", -exitval => 1 });
}
unless($target && -d $target || mkdir $target) {
    spew_args();
    pod2usage({ -message => "target must be a directory\n", -exitval => 1 })
}
unless($httpdir && $httpdir =~ /^https?:\/\//) {
    spew_args();
    pod2usage({ -message => "httpdir must be sane\n", -exitval => 1 })
}
my $sortsub; unless($sortsub = $sorters{$sortby}) {
    spew_args();
    pod2usage({ -message => "sortby must be one of [".join(', ', sort keys %sorters)."]", -exitval => 1 })
}

$source = '' if($source eq '.');
($source, $target) = map { ($_ !~ /^\// ? getcwd.'/' : '').$_ } ($source, $target);

opendir(TARGET, $target) || die("Can't read $target\n");
unlink grep { -f } map { "$target/$_" } readdir(TARGET);
closedir(TARGET);

opendir(SOURCE, $source) || die("Can't read $source\n");
my @files = grep { -f "$source/$_" && $_ =~ /\.(mp3|m4a|mp4|m4v)$/ } readdir(SOURCE);
closedir(SOURCE);
foreach my $file (@files) {
    link("$source/$file", "$target/$file");
}
my $title = "Podcast of ".(grep { $_ } split('/', $source))[-1];
my $count = time();

Template->new()->process(
# print Dumper(
    \(''.read_file(\*DATA)),
    {
        title       => $title,
        homepage    => $httpdir,
        description => "The media files from $source",
        pubdate     => time2str(),
        items       => [ map {
            $count++;
            my ($size, $mtime) = (stat($_))[7, 9];
            (my $filename = $_) =~ s/.*\///;
            (my $url = $_) =~ s/^$target/$httpdir/;
            {
                title       => $filename,
                description => $_,
                pubdate     => time2str($sortby eq 'mtime' ? $mtime : $count),
                size        => $size,
                url         => $url,
                mime        => MIME::Types->new()->mimeTypeOf($_),
            }
        } sort { $sortsub->($a, $b) } map { "$target/$_" } @files ]
    },
    "$target/feed.xml"
);

open (my $fh, '>', "$target/update.sh") || die("Can't write $target/update.sh\n");
print $fh "#!/bin/sh\n";
print $fh join(' ', map { "\"$_\"" } (
    $0,
    '--source'  => $source,
    '--target'  => $target,
    '--sortby'  => $sortby,
    '--httpdir' => $httpdir
));
close($fh);
chmod 0700, "$target/update.sh";

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

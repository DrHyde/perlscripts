use strict;
use utf8;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin ();
use Test2::V0;

my $temp_root = tempdir('iplayer-tree-tests-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
my $fresh_cache_copy_seq = 0;
my $script_loaded = 0;

sub run_script {
    my (@args) = @_;

    if (!$script_loaded) {
        require "$FindBin::Bin/../iplayer-tree";
        $script_loaded = 1;
    }

    my $stdout = '';
    my $stderr = '';
    open my $out_fh, '>:encoding(UTF-8)', \$stdout or die "open stdout scalar: $!";
    open my $err_fh, '>:encoding(UTF-8)', \$stderr or die "open stderr scalar: $!";

    my $exit = 0;
    {
        local *STDOUT = $out_fh;
        local *STDERR = $err_fh;

        my $ok = eval {
            $exit = main(@args);
            1;
        };
        if (!$ok) {
            $stderr .= $@ if defined $@;
            $exit = 255;
        }
    }

    close $out_fh or die "close stdout scalar: $!";
    close $err_fh or die "close stderr scalar: $!";
    utf8::decode($stdout) if !utf8::is_utf8($stdout);
    utf8::decode($stderr) if !utf8::is_utf8($stderr);

    return {
        exit   => $exit,
        stdout => $stdout,
        stderr => $stderr,
    };
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh or die "close $path: $!";
    return $content;
}

sub fixture_cache_dir {
    return File::Spec->catdir($FindBin::Bin, 'fixtures', 'iplayer-tree-cache');
}

sub expected_output_path {
    my ($pid) = @_;
    return File::Spec->catfile($FindBin::Bin, 'fixtures', 'iplayer-tree-expected', "$pid.out");
}

sub fresh_cache_copy {
    my $source = fixture_cache_dir();
    my $dest = File::Spec->catdir($temp_root, sprintf('cache-%04d', ++$fresh_cache_copy_seq));
    my $now = time;

    make_path($dest);

    opendir my $dh, $source or die "opendir $source: $!";
    while (my $entry = readdir $dh) {
        next if $entry =~ /^\.\.?$/;
        my $from = File::Spec->catfile($source, $entry);
        my $to = File::Spec->catfile($dest, $entry);
        next unless -f $from;
        copy($from, $to) or die "copy $from -> $to: $!";
        utime $now, $now, $to or die "utime $to: $!";
    }
    closedir $dh or die "closedir $source: $!";

    return $dest;
}

subtest '--help prints CLI usage' => sub {
    my $result = run_script('--help');

    is($result->{exit}, 0, 'help exits successfully');
    like($result->{stdout}, qr/\AUsage: iplayer-tree \[--debug\] \[--clear-cache\] <pid-or-bbc-url>\n/m, 'prints usage line');
    like($result->{stdout}, qr/requested PID: green/, 'documents requested-pid colour');
    like($result->{stdout}, qr/available episode PIDs: pink/, 'documents available-episode colour');
    like($result->{stdout}, qr/unavailable episode PIDs: dull red/, 'documents unavailable-episode colour');
    like($result->{stdout}, qr/URL fetches are cached in \/tmp\/iplayer-tree-cache for one hour\./, 'documents cache behaviour');
    unlike($result->{stdout}, qr/--cache-dir/, 'does not document the hidden cache override');
    is($result->{stderr}, '', 'help prints no stderr');
};

subtest 'invalid pid fails at the CLI' => sub {
    my $result = run_script('not-a-pid');

    is($result->{exit}, 255, 'invalid pid exits non-zero');
    like($result->{stderr}, qr/\AInvalid PID: not-a-pid\n\z/, 'reports invalid pid on stderr');
    is($result->{stdout}, '', 'prints no stdout for invalid pid');
};

subtest 'fixture-backed outputs remain stable' => sub {
    # These fixtures are a snapshot of BBC responses at the time they were cached.
    # If BBC data changes, real-world output may diverge; when failures are genuine,
    # update both the code and these fixtures together rather than forcing tests to
    # match today's live site accidentally. New pids to test will probably need to
    # be divined manually.
    #
    # m002w9yv - request for an episode in a series in a brand, includes available
    #   and unavailable sibling episodes, with unavailables in both past and present
    # m002twwx - same, but for the series that m002w9yv is part of
    # p02jbmrc - the brand for the above
    # m001tblz - a group page with children drawn from paginated group results
    for my $pid (qw(m002w9yv m002twwx p02jbmrc m001tblz)) {
        my $cache_dir = fresh_cache_copy();
        my $expected = read_file(expected_output_path($pid));

        my $result = run_script('--cache-dir', $cache_dir, $pid);
        is($result->{exit}, 0, "$pid exits successfully");
        is($result->{stderr}, '', "$pid prints no stderr");
        is($result->{stdout}, $expected, "$pid matches the cached expected output exactly");

        my $debug_result = run_script('--debug', '--cache-dir', $cache_dir, $pid);
        is($debug_result->{exit}, 0, "$pid debug run exits successfully");
        is($debug_result->{stderr}, '', "$pid debug run prints no stderr");
        like($debug_result->{stdout}, qr/^\[cache\] /m, "$pid debug run uses cached fixtures");
        unlike($debug_result->{stdout}, qr/^\[fetch\] /m, "$pid debug run does not hit the network");
    }
};

done_testing;

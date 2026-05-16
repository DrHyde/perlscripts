use strict;
use utf8;
use warnings;

use FindBin ();
use File::Spec;
use Test2::V0;

my $script_loaded = 0;

sub script_path {
    return File::Spec->catfile($FindBin::Bin, '..', 'stamp-optimizer');
}

sub run_script {
    my (@args) = @_;

    if (!$script_loaded) {
        my $script = script_path();
        require $script;
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

sub assert_success {
    my ($result, $name) = @_;

    is($result->{exit}, 0, "$name exits successfully");
    is($result->{stderr}, '', "$name prints no stderr");
}

sub run_script_with_env {
    my ($env, @args) = @_;

    local %ENV = (%ENV, %{$env});
    return run_script(@args);
}

sub usage_prefix {
    return 'Usage: stamp-optimizer --target <float> --maxstamps <int> [--maxvalue <float>] --available <float(?:xint)?> [...]';
}

subtest '--help prints usage' => sub {
    my $result = run_script('--help');

    assert_success($result, '--help');
    like(
        $result->{stdout},
        qr/\A\Q@{[ usage_prefix() ]}\E\n/m,
        'prints the usage line',
    );
    like($result->{stdout}, qr/largest possible collection of stamp sets whose totals are at or above/i, 'describes the optimisation goal');
    like($result->{stdout}, qr/^\s+-t,\s+--target\b/m, 'documents -t');
    like($result->{stdout}, qr/^\s+-a,\s+--available\b/m, 'documents -a');
    like($result->{stdout}, qr/^\s+-s,\s+--maxstamps\b/m, 'documents -s');
    like($result->{stdout}, qr/^\s+-v,\s+--maxvalue\b/m, 'documents -v');
    like($result->{stdout}, qr/^\s+-h,\s+--help\b/m, 'documents -h');
    unlike($result->{stdout}, qr/--debug/, 'does not document the hidden debug flag');
};

subtest '-h prints usage' => sub {
    my $result = run_script('-h');

    assert_success($result, '-h');
    like($result->{stdout}, qr/\A\Q@{[ usage_prefix() ]}\E\n/m, 'prints the usage line');
};

subtest '--debug enables debug logging without affecting normal output' => sub {
    my $result = run_script(
        '--debug',
        '--target', '5',
        '--maxstamps', '2',
        '--available', '2', '3',
    );

    is($result->{exit}, 0, '--debug run exits successfully');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.00 = [3.00, 2.00]\n",
        '--debug preserves the normal stdout format',
    );
    like($result->{stderr}, qr/\A\[debug\] starting search:/, '--debug emits progress to stderr');
};

subtest 'argument errors print the error and then usage on stderr' => sub {
    my $missing_target = run_script('--maxstamps', '2', '--available', '2', '3');

    is($missing_target->{exit}, 1, 'missing target exits non-zero');
    is($missing_target->{stdout}, '', 'missing target prints no stdout');
    like(
        $missing_target->{stderr},
        qr/\A--target is required\n\Q@{[ usage_prefix() ]}\E\n/s,
        'missing target prints error followed by usage',
    );

    my $unexpected = run_script('--bogus');

    is($unexpected->{exit}, 1, 'unexpected argument exits non-zero');
    is($unexpected->{stdout}, '', 'unexpected argument prints no stdout');
    like(
        $unexpected->{stderr},
        qr/\AUnexpected argument: --bogus\n\Q@{[ usage_prefix() ]}\E\n/s,
        'unexpected argument prints error followed by usage',
    );
};

subtest 'single-value-only candidates are discarded' => sub {
    my $result = run_script(
        '--target', '5',
        '--available', '2', '3', '1', '4', '5',
        '--maxstamps', '2',
    );

    assert_success($result, 'exact match run');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.00 = [4.00, 1.00]\n".
        "  5.00 = [3.00, 2.00]\n".
        "\n".
        "unused stamps\n".
        "   5.00\n",
        'omits candidates that use only one distinct stamp value',
    );
};

subtest 'maximises the number of non-overlapping sets, then total closeness' => sub {
    my $result = run_script(
        '--target', '6',
        '--maxstamps', '2',
        '--maxvalue', '7',
        '--available', '3', '3', '2.5', '3.8', '4',
    );

    assert_success($result, 'maximising run');
    is(
        $result->{stdout},
        "found sets\n".
        "  6.30 = [3.80, 2.50]\n".
        "  7.00 = [4.00, 3.00]\n".
        "\n".
        "unused stamps\n".
        "   3.00\n",
        'chooses the largest collection of non-overlapping sets and then the closest one',
    );
};

subtest '--available accepts multiplicity notation and repeated option groups' => sub {
    my $result = run_script(
        '--target', '6.5',
        '--maxstamps', '2',
        '--maxvalue', '6.5',
        '--available', '3.2x2',
        '--available', '3.3',
    );

    assert_success($result, 'multiplicity run');
    is(
        $result->{stdout},
        "found sets\n".
        "  6.50 = [3.30, 3.20]\n".
        "\n".
        "unused stamps\n".
        "   3.20\n",
        'expands multiplicity notation and repeated --available groups',
    );
};

subtest 'chooses the best non-overlapping over-target collection when no exact match exists' => sub {
    my $result = run_script(
        '--target', '5.1',
        '--maxstamps', '2',
        '--maxvalue', '5.3',
        '--available', '2.4', '2.7', '2.5', '2.8',
    );

    assert_success($result, 'over-target collection run');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.10 = [2.70, 2.40]\n".
        "  5.30 = [2.80, 2.50]\n",
        'chooses the maximum-size collection within the target and maximum value bounds',
    );
};

subtest 'single-character aliases work for the public options' => sub {
    my $result = run_script(
        '-t', '5.1',
        '-s', '2',
        '-v', '5.3',
        '-a', '2.4', '2.7', '2.5', '2.8',
    );

    assert_success($result, 'short-option run');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.10 = [2.70, 2.40]\n".
        "  5.30 = [2.80, 2.50]\n",
        'short aliases behave the same as the long options',
    );
};

subtest 'reported regression prefers the best two non-overlapping sets' => sub {
    my $result = run_script(
        '--target', '3.6',
        '--maxstamps', '3',
        '--available', '2.55x2', '0.19', '0.93', '0.18', '0.91', '0.92', '0.90',
        '--maxvalue', '3.7',
    );

    assert_success($result, 'reported regression run');
    is(
        $result->{stdout},
        "found sets\n".
        "  3.63 = [2.55, 0.90, 0.18]\n".
        "  3.65 = [2.55, 0.91, 0.19]\n".
        "\n".
        "unused stamps\n".
        "   0.92    0.93\n",
        'uses each available stamp at most once across the chosen collection',
    );
};

subtest 'unused stamps are sorted and emitted in right-aligned columns with up to ten per line' => sub {
    my $result = run_script(
        '--target', '10',
        '--maxstamps', '2',
        '--available',
        '9.89', '0.11',
        '0.10', '34.21', '0.04', '0.02', '0.08', '0.06', '0.01', '0.07', '0.03', '0.09', '0.05',
    );

    assert_success($result, 'unused stamp columns run');
    is(
        $result->{stdout},
        "found sets\n".
        "  10.00 = [9.89, 0.11]\n".
        "\n".
        "unused stamps\n".
        "   0.01    0.02    0.03    0.04    0.05    0.06    0.07    0.08    0.09    0.10\n".
        "  34.21\n",
        'formats sorted unused stamps into ten-wide rows with aligned columns',
    );
};

subtest 'candidate generation timeout returns whatever candidate sets were found so far' => sub {
    my $result = run_script_with_env(
        {
            STAMP_OPTIMIZER_CANDIDATE_TIMEOUT_SECONDS  => 0.001,
            STAMP_OPTIMIZER_COLLECTION_TIMEOUT_SECONDS => 60,
        },
        '--target', '5',
        '--available', '5', '4', '1',
        '--maxstamps', '2',
    );

    assert_success($result, 'candidate-timeout run');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.00 = [4.00, 1.00]\n".
        "\n".
        "unused stamps\n".
        "   5.00\n",
        'uses the partial candidate list when candidate generation times out immediately',
    );
};

subtest 'collection search timeout returns the best collection found so far' => sub {
    my $result = run_script_with_env(
        {
            STAMP_OPTIMIZER_CANDIDATE_TIMEOUT_SECONDS  => 60,
            STAMP_OPTIMIZER_COLLECTION_TIMEOUT_SECONDS => 0,
        },
        '--target', '3.6',
        '--maxstamps', '3',
        '--available', '2.55x2', '0.19', '0.93', '0.18', '0.91', '0.92', '0.90',
        '--maxvalue', '3.7',
    );

    assert_success($result, 'collection-timeout run');
    is(
        $result->{stdout},
        "found sets\n".
        "  3.63 = [2.55, 0.90, 0.18]\n".
        "\n".
        "unused stamps\n".
        "   0.19    0.91    0.92    0.93    2.55\n",
        'returns the seeded best-so-far collection when collection search times out immediately',
    );
};

subtest 'no valid set within the target and maximum value bounds fails clearly' => sub {
    my $result = run_script(
        '--target', '7',
        '--maxstamps', '2',
        '--maxvalue', '7.3',
        '--available', '3.4x3', '4',
    );

    is($result->{exit}, 1, 'no-solution run exits non-zero');
    like(
        $result->{stderr},
        qr/\ANo valid stamp sets found between the target and maximum value\.\n\z/,
        'reports that no admissible set exists',
    );
    is($result->{stdout}, '', 'prints no stdout when no solution exists');
};

subtest '--maxvalue defaults to the target' => sub {
    my $result = run_script('--target', '5', '--maxstamps', '2', '--available', '2', '3');

    assert_success($result, 'default maxvalue run');
    is(
        $result->{stdout},
        "found sets\n".
        "  5.00 = [3.00, 2.00]\n",
        'uses the target as the maximum value when the option is omitted',
    );
};

done_testing;

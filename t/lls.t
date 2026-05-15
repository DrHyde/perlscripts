use strict;
use utf8;
use warnings;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin ();
use IO::Socket::UNIX;
use IPC::Open3 qw(open3);
use Socket qw(SOCK_STREAM);
use Symbol qw(gensym);
use Test2::V0;

my $loaded_lls;
my $config_dir_count = 0;

sub script_path {
    return File::Spec->catfile($FindBin::Bin, '..', 'lls');
}

sub run_script {
    my (%args) = @_;

    my $cwd = delete $args{cwd};
    my $env = delete $args{env} || {};
    my @argv = @{ delete $args{args} || [] };
    my $tmpdir = $env->{LLS_TEST_TMPDIR};

    die 'unknown run_script args' if keys %args;

    my $previous_cwd = getcwd();
    chdir $cwd or die "chdir $cwd: $!" if defined $cwd;

    my $result = eval {
        local %ENV = (%ENV, %{$env});
        if(grep { $_ eq '-h' || $_ eq '--help' || $_ eq '-?' || $_ eq '-H' || $_ eq '--HELP' } @argv) {
            my $stderr = gensym;
            my $pid = open3(my $in, my $out, $stderr, $^X, script_path(), @argv);
            close $in or die "close stdin: $!";

            binmode $out, ':encoding(UTF-8)';
            binmode $stderr, ':encoding(UTF-8)';

            local $/;
            my $stdout = <$out>;
            my $errout = <$stderr>;

            waitpid $pid, 0;

            return {
                exit   => $? >> 8,
                stdout => defined $stdout ? $stdout : '',
                stderr => defined $errout ? $errout : '',
            };
        }
        if(!$loaded_lls) {
            my $script = script_path();
            require $script;
            $loaded_lls = 1;
        }
        local $0 = script_path();

        my ($out, $out_path) = defined $tmpdir ? tempfile(DIR => $tmpdir) : tempfile();
        my ($err, $err_path) = defined $tmpdir ? tempfile(DIR => $tmpdir) : tempfile();
        binmode $out, ':encoding(UTF-8)';
        binmode $err, ':encoding(UTF-8)';
        local *STDOUT = $out;
        local *STDERR = $err;
        my $exit = eval { lls(@argv) };
        my $script_error = $@;
        close $out or die "close stdout: $!";
        close $err or die "close stderr: $!";
        open my $stdout_fh, '<:encoding(UTF-8)', $out_path or die "open $out_path: $!";
        open my $stderr_fh, '<:encoding(UTF-8)', $err_path or die "open $err_path: $!";
        local $/;
        my $stdout = <$stdout_fh>;
        my $stderr = <$stderr_fh>;
        close $stdout_fh or die "close $out_path: $!";
        close $stderr_fh or die "close $err_path: $!";

        return {
            exit   => $script_error ? 2 : $exit,
            stdout => defined $stdout ? $stdout : '',
            stderr => join('', defined $stderr ? $stderr : '', $script_error),
        };
    };
    my $error = $@;

    chdir $previous_cwd or die "chdir $previous_cwd: $!";
    die $error if $error;

    return $result;
}

sub write_file {
    my ($path, $content) = @_;

    open my $fh, '>:raw', $path or die "open $path: $!";
    print {$fh} $content or die "print $path: $!";
    close $fh or die "close $path: $!";
}

sub run_cmd {
    my (@cmd) = @_;
    system(@cmd) == 0 or die "command failed (@cmd): $?";
}

sub set_mtime {
    my ($epoch, @paths) = @_;
    utime($epoch, $epoch, @paths) or die "utime(@paths): $!";
}

sub make_fixture_tree {
    my $tmp = tempdir(CLEANUP => 1);
    my $home = File::Spec->catdir($tmp, 'home');
    my $basic = File::Spec->catdir($tmp, 'basic');
    my $iconbox = File::Spec->catdir($tmp, 'iconbox');
    my $sortbox = File::Spec->catdir($tmp, 'sortbox');
    my $gitrepo = File::Spec->catdir($tmp, 'gitrepo');
    my $config = File::Spec->catdir($tmp, 'config');
    my $tmpfiles = File::Spec->catdir($tmp, 'tmpfiles');

    make_path(
        $home,
        File::Spec->catdir($basic, 'dir', 'sub'),
        File::Spec->catdir($basic, 'skipme'),
        File::Spec->catdir($iconbox, 'dir'),
        File::Spec->catdir($iconbox, 't'),
        $sortbox,
        $gitrepo,
        $config,
        $tmpfiles,
    );

    write_file(File::Spec->catfile($basic, 'a.txt'), 'alpha');
    write_file(File::Spec->catfile($basic, 'b.sh'), 'bee');
    write_file(File::Spec->catfile($basic, 'big.bin'), 'x' x 2048);
    write_file(File::Spec->catfile($basic, '.hidden'), 'dot');
    write_file(File::Spec->catfile($basic, 'SPECIAL'), 'special');
    write_file(
        File::Spec->catfile($basic, 'script'),
        "#!/usr/bin/env perl\nprint qq(x);"
    );
    write_file(File::Spec->catfile($basic, 'dir', 'sub', 'file.t'), 'inside');
    write_file(File::Spec->catfile($basic, 'skipme', 'ignored.txt'), 'x');

    write_file(File::Spec->catfile($iconbox, 'plain'), 'plain');
    write_file(File::Spec->catfile($iconbox, 'archive.bz2'), 'x');
    write_file(File::Spec->catfile($iconbox, '.DS_Store'), 'x');
    write_file(
        File::Spec->catfile($iconbox, 'script'),
        "#!/bin/sh\necho hi\n"
    );

    chmod 0755, File::Spec->catfile($basic, 'b.sh')
        or die "chmod b.sh: $!";
    chmod 0755, File::Spec->catfile($basic, 'script')
        or die "chmod script: $!";
    chmod 0755, File::Spec->catfile($iconbox, 'script')
        or die "chmod iconbox script: $!";
    symlink 'a.txt', File::Spec->catfile($basic, 'link')
        or die "symlink link -> a.txt: $!";
    symlink 'plain', File::Spec->catfile($iconbox, 'linkfile')
        or die "symlink linkfile -> plain: $!";
    symlink 'script', File::Spec->catfile($iconbox, 'linkexec')
        or die "symlink linkexec -> script: $!";
    symlink 'dir', File::Spec->catfile($iconbox, 'linkdir')
        or die "symlink linkdir -> dir: $!";
    symlink 'missing', File::Spec->catfile($iconbox, 'linkbroken')
        or die "symlink linkbroken -> missing: $!";
    system('mkfifo', File::Spec->catfile($iconbox, 'pipe')) == 0
        or die "mkfifo pipe: $?";
    my $iconbox_socket = IO::Socket::UNIX->new(
        Type   => SOCK_STREAM,
        Local  => File::Spec->catfile($iconbox, 'socket'),
        Listen => 1,
    ) or die "socket iconbox/socket: $!";
    symlink 'pipe', File::Spec->catfile($iconbox, 'linkplain')
        or die "symlink linkplain -> pipe: $!";

    set_mtime(
        1704164640,
        File::Spec->catfile($basic, 'a.txt'),
        File::Spec->catfile($basic, '.hidden'),
        File::Spec->catfile($basic, 'SPECIAL'),
        File::Spec->catdir($basic, 'dir'),
        File::Spec->catdir($basic, 'dir', 'sub'),
        File::Spec->catfile($basic, 'dir', 'sub', 'file.t'),
        File::Spec->catdir($basic, 'skipme'),
        File::Spec->catfile($basic, 'skipme', 'ignored.txt'),
    );
    set_mtime(1704164700, File::Spec->catfile($basic, 'b.sh'));
    set_mtime(1704164580, File::Spec->catfile($basic, 'big.bin'));
    set_mtime(1704164760, File::Spec->catfile($basic, 'script'));

    write_file(File::Spec->catfile($sortbox, 'alpha.txt'), 'a');
    write_file(File::Spec->catfile($sortbox, 'beta.txt'),  'bbbbb');
    write_file(File::Spec->catfile($sortbox, 'gamma.txt'), 'g' x 9);

    set_mtime(1704164580, File::Spec->catfile($sortbox, 'alpha.txt'));
    set_mtime(1704164640, File::Spec->catfile($sortbox, 'beta.txt'));
    set_mtime(1704164700, File::Spec->catfile($sortbox, 'gamma.txt'));

    write_file(File::Spec->catfile($gitrepo, '.gitignore'), "*.tmp\n");
    write_file(File::Spec->catfile($gitrepo, 'tracked.txt'), "tracked\n");

    run_cmd('git', 'init', '-q', $gitrepo);
    run_cmd('git', '-C', $gitrepo, 'config', 'user.email', 'test@example.com');
    run_cmd('git', '-C', $gitrepo, 'config', 'user.name', 'tester');
    run_cmd('git', '-C', $gitrepo, 'add', '.gitignore', 'tracked.txt');
    run_cmd('git', '-C', $gitrepo, 'commit', '-qm', 'init');

    write_file(File::Spec->catfile($gitrepo, 'tracked.txt'), "tracked changed\n");
    write_file(File::Spec->catfile($gitrepo, 'untracked.txt'), "untracked\n");
    write_file(File::Spec->catfile($gitrepo, 'ignored.tmp'), "ignored\n");

    return {
        home    => $home,
        basic   => $basic,
        iconbox => $iconbox,
        sortbox => $sortbox,
        gitrepo => $gitrepo,
        config  => $config,
        tmpdir  => $tmpfiles,
        _iconbox_socket => $iconbox_socket,
    };
}

sub fixture_env {
    my ($fixture, $extra) = @_;
    return {
        HOME    => $fixture->{home},
        LLS_TEST_CONFIG_DIR => $fixture->{config},
        LLS_TEST_TMPDIR => $fixture->{tmpdir},
        FIGNORE => '',
        TZ      => 'UTC',
        %{ $extra || {} },
    };
}

sub make_config_dir {
    my ($fixture) = @_;
    my $config_dir = File::Spec->catdir($fixture->{tmpdir}, 'config-' . ++$config_dir_count);
    make_path($config_dir);
    return $config_dir;
}

sub write_config_args {
    my ($config_dir, $name, $content) = @_;
    write_file(File::Spec->catfile($config_dir, $name), $content);
}

sub run_lls {
    my ($fixture, $cwd_key, @args) = @_;
    my $extra_env = ref($args[0]) eq 'HASH' ? shift(@args) : {};

    return run_script(
        cwd  => $fixture->{$cwd_key},
        env  => fixture_env($fixture, $extra_env),
        args => \@args,
    );
}

sub assert_success {
    my ($result, $name) = @_;
    is($result->{exit}, 0, "$name exits successfully");
    is($result->{stderr}, '', "$name prints no stderr");
}

sub first_block_device {
    foreach my $candidate (glob('/dev/*'), glob('/dev/mapper/*')) {
        return $candidate if -b $candidate;
    }
    return;
}

sub assert_alias_pair {
    my ($fixture, $name, $cwd_key, $short_args, $long_args, $check) = @_;

    subtest $name => sub {
        my $short = run_lls($fixture, $cwd_key, @{$short_args});
        my $long  = run_lls($fixture, $cwd_key, @{$long_args});

        is($short->{exit}, $long->{exit}, "$name exits the same");
        is($short->{stderr}, $long->{stderr}, "$name stderr matches");
        is($short->{stdout}, $long->{stdout}, "$name stdout matches");

        $check->($short) if $check;
    };
}

my $fixture = make_fixture_tree();

subtest 'help aliases print the same usage output' => sub {
    my $short = run_lls($fixture, 'basic', '-h');
    my $long  = run_lls($fixture, 'basic', '--help');
    my $quest = run_lls($fixture, 'basic', '-?');

    assert_success($short, '-h');
    is($short->{stdout}, $long->{stdout}, '-h matches --help');
    is($quest->{stdout}, $long->{stdout}, '-? matches --help');
    like($long->{stdout}, qr/\AUsage:\n\s+\$ lls \[OPTIONS\] \[FILES\]\n/m, 'help prints synopsis');
};

subtest 'full help aliases print the same verbose output' => sub {
    my $short = run_lls($fixture, 'basic', '-H');
    my $long  = run_lls($fixture, 'basic', '--HELP');

    assert_success($short, '-H');
    is($short->{stdout}, $long->{stdout}, '-H matches --HELP');
    like($long->{stdout}, qr/^DISPLAY OPTIONS$/m, 'full help includes display section');
    like($long->{stdout}, qr/^FILE TYPES, ICONS, AND COLOURS$/m, 'full help includes type section');
};

assert_alias_pair(
    $fixture,
    'long option alias',
    'basic',
    ['-l', '--noicons', '--iso8601', 'a.txt'],
    ['--long', '--noicons', '--iso8601', 'a.txt'],
    sub {
        my ($result) = @_;
        like(
            $result->{stdout},
            qr/\A-rw-r--r--\s+1\s+\S+\s+\S+\s+5 B\s+2024-01-02 03:04 a\.txt\n\z/,
            '-l shows long-format metadata',
        );
    },
);

assert_alias_pair(
    $fixture,
    'all option alias',
    'basic',
    ['-a', '--noicons', '.'],
    ['--all', '--noicons', '.'],
    sub {
        my ($result) = @_;
        like($result->{stdout}, qr/^\.$/m, '-a includes .');
        like($result->{stdout}, qr/^\.\.$/m, '-a includes ..');
        like($result->{stdout}, qr/^\.hidden$/m, '-a includes hidden files');
    },
);

assert_alias_pair(
    $fixture,
    'hidden option alias',
    'basic',
    ['-A', '--noicons', '.'],
    ['--hidden', '--noicons', '.'],
    sub {
        my ($result) = @_;
        unlike($result->{stdout}, qr/^\.$/m, '-A omits .');
        unlike($result->{stdout}, qr/^\.\.$/m, '-A omits ..');
        like($result->{stdout}, qr/^\.hidden$/m, '-A includes hidden files');
    },
);

assert_alias_pair(
    $fixture,
    'ignore option alias',
    'basic',
    ['-R', '--ascii', '--noicons', '-I', 'skipme', '.'],
    ['--recurse', '--ascii', '--noicons', '--ignore', 'skipme', '.'],
    sub {
        my ($result) = @_;
        unlike($result->{stdout}, qr/\bskipme\b/, '--ignore omits the named directory');
        unlike($result->{stdout}, qr/\bignored\.txt\b/, '--ignore omits the ignored descendants');
        like($result->{stdout}, qr/\bdir\b/, '--ignore leaves other directories visible');
    },
);

assert_alias_pair(
    $fixture,
    'dirs option alias',
    'basic',
    ['-dR', '--ascii', '--noicons', '.'],
    ['--dirs', '--recurse', '--ascii', '--noicons', '.'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            " .\n +- dir\n |  \\- sub\n \\- skipme\n",
            '--dirs only renders directories when recursing',
        );
    },
);

assert_alias_pair(
    $fixture,
    'reverse option alias',
    'sortbox',
    ['-r', '--noicons', '.'],
    ['--reverse', '--noicons', '.'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            "gamma.txt\nbeta.txt\nalpha.txt\n",
            '-r reverses the default lexical order',
        );
    },
);

assert_alias_pair(
    $fixture,
    'time option alias',
    'sortbox',
    ['-t', '--noicons', '.'],
    ['--time', '--noicons', '.'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            "gamma.txt\nbeta.txt\nalpha.txt\n",
            '-t sorts newest first',
        );
    },
);

assert_alias_pair(
    $fixture,
    'size option alias',
    'sortbox',
    ['-S', '--noicons', '.'],
    ['--size', '--noicons', '.'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            "gamma.txt\nbeta.txt\nalpha.txt\n",
            '-S sorts largest first',
        );
    },
);

assert_alias_pair(
    $fixture,
    'recurse option alias',
    'basic',
    ['-R', '--ascii', '--noicons', 'dir'],
    ['--recurse', '--ascii', '--noicons', 'dir'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            " dir\n \\- sub\n    \\- file.t\n",
            '-R draws an ascii tree when asked',
        );
    },
);

assert_alias_pair(
    $fixture,
    'git option alias',
    'gitrepo',
    ['-g', '--show_name', '.gitignore', 'tracked.txt', 'untracked.txt', 'ignored.tmp'],
    ['--git', '--show_name', '.gitignore', 'tracked.txt', 'untracked.txt', 'ignored.tmp'],
    sub {
        my ($result) = @_;
        is(
            $result->{stdout},
            "   .gitignore\n ± tracked.txt\nUn untracked.txt\nIg ignored.tmp\n",
            '-g shows tracked, untracked, and ignored statuses',
        );
    },
);

assert_alias_pair(
    $fixture,
    'ascii option alias',
    'basic',
    ['-7', '-R', 'dir'],
    ['--ascii', '--recurse', 'dir'],
    sub {
        my ($result) = @_;
        like($result->{stdout}, qr/\Q\- sub\E/, '--ascii renders ascii tree branches');
        unlike($result->{stdout}, qr/[└│]/, '--ascii suppresses utf8 tree art and icons');
    },
);

assert_alias_pair(
    $fixture,
    'utf8 option alias',
    'basic',
    ['-7', '-8', '-R', 'dir'],
    ['--ascii', '--utf8', '--recurse', 'dir'],
    sub {
        my ($result) = @_;
        like($result->{stdout}, qr/└─ sub/, '--utf8 restores unicode tree branches');
        like($result->{stdout}, qr//, '--utf8 restores icons after --ascii');
    },
);

assert_alias_pair(
    $fixture,
    'bytes option alias',
    'basic',
    ['-b', '--show_size', 'big.bin'],
    ['--bytes', '--show_size', 'big.bin'],
    sub {
        my ($result) = @_;
        is($result->{stdout}, " 2048\n", '--bytes shows raw byte counts');
    },
);

subtest '--norecurse prunes matching directories' => sub {
    my $result = run_lls($fixture, 'basic', '--recurse', '--ascii', '--noicons', '--norecurse', 'dir', '.');
    assert_success($result, '--norecurse');
    unlike($result->{stdout}, qr/\bfile\.t\b/, '--norecurse prevents descent');
    like($result->{stdout}, qr/\bdir\b/, '--norecurse leaves the directory entry visible');
};

subtest '--iso8601, --iso8601s, and --noiso8601 affect date formatting' => sub {
    my $iso = run_lls($fixture, 'basic', '--show_date', '--iso8601', 'a.txt');
    my $secs = run_lls($fixture, 'basic', '--show_date', '--iso8601s', 'a.txt');
    my $plain = run_lls($fixture, 'basic', '--show_date', '--iso8601', '--noiso8601', 'a.txt');

    assert_success($iso, '--iso8601');
    assert_success($secs, '--iso8601s');
    assert_success($plain, '--noiso8601');

    is($iso->{stdout}, "2024-01-02 03:04\n", '--iso8601 omits seconds');
    is($secs->{stdout}, "2024-01-02 03:04:00\n", '--iso8601s includes seconds');
    is($plain->{stdout}, "02 Jan  2024\n", '--noiso8601 restores the default format');
};

subtest '--noicons suppresses icon output and conflicts with --show_icons' => sub {
    my $plain = run_lls($fixture, 'basic', '--noicons', 'a.txt');
    my $error = run_lls($fixture, 'basic', '--noicons', '--show_icons', 'a.txt');

    assert_success($plain, '--noicons');
    is($plain->{stdout}, "a.txt\n", '--noicons leaves just the filename');

    is($error->{exit}, 2, 'incompatible icon options fail');
    is($error->{stdout}, '', 'incompatible icon options print no stdout');
    is($error->{stderr}, "\n--noicons and --show_icons makes no sense\n\n", 'incompatible icon options explain the failure');
};

subtest 'display column options each expose one column' => sub {
    my %cases = (
        show_icons => [ [qw(--show_icons a.txt)], qr/\A\S+\s+\S+\n\z/, 'prints only icons' ],
        show_name  => [ [qw(--show_name a.txt)],  qr/\Aa\.txt\n\z/, 'prints only the filename' ],
        show_perms => [ [qw(--show_perms a.txt)], qr/\A-rw-r--r--\n\z/, 'prints file mode' ],
        show_links => [ [qw(--show_links a.txt)], qr/\A 1\n\z/, 'prints link count' ],
        show_owner => [ [qw(--show_owner a.txt)], qr/\A \S+\n\z/, 'prints owner' ],
        show_group => [ [qw(--show_group a.txt)], qr/\A \S+\n\z/, 'prints group' ],
        show_size  => [ [qw(--show_size a.txt)],  qr/\A 5 B\n\z/, 'prints human size' ],
        show_date  => [ [qw(--show_date a.txt)],  qr/\A02 Jan  2024\n\z/, 'prints default date format' ],
    );

    for my $name (sort keys %cases) {
        my ($args, $re, $label) = @{ $cases{$name} };
        my $result = run_lls($fixture, 'basic', @{$args});
        assert_success($result, "--$name");
        like($result->{stdout}, $re, $label);
    }
};

subtest '--name_type, --ext_type, --shebang_type, and --default_types affect type matching' => sub {
    my $name = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--name_type', 'SPECIAL', 'custom',
        'SPECIAL',
    );
    my $ext = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--ext_type', 'txt', 'custom',
        'a.txt',
    );
    my $shebang = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--ext_type', 'zzz', 'other',
        '--shebang_type', 'perl', 'custom',
        'script',
    );
    my $defaults = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--icon_type', 'test', 'T',
        '--ext_type', 'txt', 'custom',
        '--default_types',
        'a.txt',
        'dir/sub/file.t',
    );

    assert_success($name, '--name_type');
    assert_success($ext, '--ext_type');
    assert_success($shebang, '--shebang_type');
    assert_success($defaults, '--default_types');

    is($name->{stdout}, "  X SPECIAL\n", '--name_type maps exact filenames');
    is($ext->{stdout}, "  X a.txt\n", '--ext_type maps extensions');
    is($shebang->{stdout}, "  X script\n", '--shebang_type maps executables by shebang');
    like(
        $defaults->{stdout},
        qr/\A(?:  X|   ) a\.txt\n  T dir\/sub\/file\.t\n\z/,
        '--default_types restores built-in type mappings for file.t',
    );
};

subtest '--show_default_types prints the built-in type mappings' => sub {
    my $result = run_lls($fixture, 'basic', '--show_default_types');
    assert_success($result, '--show_default_types');
    like($result->{stdout}, qr/^--ext_type test t$/m, 'shows the default test extension');
    like($result->{stdout}, qr/^--name_type text README$/m, 'shows the default README mapping');
};

subtest '--icon_type and --default_icons control icon lookup' => sub {
    my $custom = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--name_type', 'SPECIAL', 'custom',
        'SPECIAL',
    );
    my $defaults = run_lls(
        $fixture, 'basic',
        '--show_icons', '--show_name',
        '--icon_type', 'custom', 'X',
        '--name_type', 'SPECIAL', 'custom',
        '--default_icons',
        'SPECIAL',
    );

    assert_success($custom, '--icon_type');
    assert_success($defaults, '--default_icons');

    is($custom->{stdout}, "  X SPECIAL\n", '--icon_type overrides the specific icon set');
    like($defaults->{stdout}, qr/\A\S X SPECIAL\n\z/, '--default_icons restores the generic icon too');
};

subtest '--show_default_icons prints the built-in icon mappings' => sub {
    my $result = run_lls($fixture, 'basic', '--show_default_icons');
    assert_success($result, '--show_default_icons');
    like($result->{stdout}, qr/^--icon_type file /m, 'shows the default file icon');
    like($result->{stdout}, qr/^--icon_type perl /m, 'shows the default perl icon');
};

subtest '--colour_type, --force_colour, --nocolour, and --colour_depth control ANSI colouring' => sub {
    my $plain = run_lls(
        $fixture, 'basic',
        '--show_name',
        '--colour_type', 'custom', 'red',
        '--name_type', 'SPECIAL', 'custom',
        '--nocolour',
        'SPECIAL',
    );
    my $force = run_lls(
        $fixture, 'basic',
        '--show_name',
        '--force_colour',
        '--colour_type', 'custom', 'red',
        '--name_type', 'SPECIAL', 'custom',
        'SPECIAL',
    );
    my $depth8 = run_lls(
        $fixture, 'basic',
        '--show_name',
        '--force_colour',
        '--colour_depth', '8',
        '--colour_type', 'custom', 'red',
        '--name_type', 'SPECIAL', 'custom',
        'SPECIAL',
    );
    my $depth4 = run_lls(
        $fixture, 'basic',
        '--show_name',
        '--force_colour',
        '--colour_depth', '4',
        '--colour_type', 'custom', 'red',
        '--name_type', 'SPECIAL', 'custom',
        'SPECIAL',
    );
    my $invalid = run_lls($fixture, 'basic', '--colour_depth', '12', 'SPECIAL');

    assert_success($plain, '--nocolour');
    assert_success($force, '--force_colour');
    assert_success($depth8, '--colour_depth 8');
    assert_success($depth4, '--colour_depth 4');

    is($plain->{stdout}, "SPECIAL\n", '--nocolour leaves the output uncoloured');
    like($force->{stdout}, qr/\A\e\[38;2;255;0;0mSPECIAL\e\[0m\n\z/, '--force_colour enables 24-bit colour');
    like($depth8->{stdout}, qr/\A\e\[38;5;\d+mSPECIAL\e\[0m\n\z/, '--colour_depth 8 uses 256-colour codes');
    like($depth4->{stdout}, qr/\A\e\[[0-9;]+mSPECIAL\e\[0m\n\z/, '--colour_depth 4 uses ANSI 16-colour codes');

    is($invalid->{exit}, 2, 'invalid colour depth exits non-zero');
    is($invalid->{stdout}, '', 'invalid colour depth prints no stdout');
    is(
        $invalid->{stderr},
        "Incorrect option: --colour_depth 12, should be 4, 8, or 24\n\nTry -h for help\n",
        'invalid colour depth reports the allowed values',
    );
};

subtest '--default_colours restores built-in colours alongside custom ones' => sub {
    my $result = run_lls(
        $fixture, 'basic',
        '--show_name',
        '--force_colour',
        '--colour_type', 'custom', 'red',
        '--name_type', 'SPECIAL', 'custom',
        '--default_colours',
        '-d',
        'dir',
    );

    assert_success($result, '--default_colours');
    like($result->{stdout}, qr/\A\e\[38;2;0;255;255mdir\e\[0m\n\z/, '--default_colours restores the default dir colour');
};

subtest '--show_default_colours prints the built-in colour mappings' => sub {
    my $result = run_lls($fixture, 'basic', '--show_default_colours');
    assert_success($result, '--show_default_colours');
    like($result->{stdout}, qr/^--colour_type dir 'cyan'$/m, 'shows the default dir colour');
    like($result->{stdout}, qr/^--colour_type exec 'bold red'$/m, 'shows the default exec colour');
};

subtest '--show_all_args exposes bundled short options after argv rewriting' => sub {
    my $result = run_lls($fixture, 'basic', '--show_all_args', '-lAR', '--', 'name');

    is($result->{exit}, 1, '--show_all_args exits via its callback');
    is($result->{stderr}, '', '--show_all_args prints no stderr');
    is(
        $result->{stdout},
        "--show_all_args\n-l\n-A\n-R\n--\nname\n",
        '--show_all_args reveals the unbundled argv',
    );
};

subtest 'config args file is prepended to argv' => sub {
    my $config_dir = make_config_dir($fixture);
    write_config_args($config_dir, 'args', "--show_all_args\n--show_name\n");

    my $result = run_lls($fixture, 'basic', { LLS_TEST_CONFIG_DIR => $config_dir }, 'name');

    is($result->{exit}, 1, 'args config exits via --show_all_args');
    is($result->{stderr}, '', 'args config prints no stderr');
    is(
        $result->{stdout},
        "--show_all_args\n--show_name\nname\n",
        'args config is loaded before command-line args',
    );
};

subtest 'OS-specific config args file is prepended alongside generic config args' => sub {
    my $config_dir = make_config_dir($fixture);
    write_config_args($config_dir, 'args', "--show_name\n");
    write_config_args($config_dir, "${^O}_args", "--show_size\n--show_all_args\n");

    my $result = run_lls($fixture, 'basic', { LLS_TEST_CONFIG_DIR => $config_dir }, 'name');

    is($result->{exit}, 1, "${^O}_args exits via --show_all_args");
    is($result->{stderr}, '', "${^O}_args prints no stderr");
    is(
        $result->{stdout},
        "--show_size\n--show_all_args\n--show_name\nname\n",
        "${^O}_args and args are both loaded before command-line args",
    );
};

subtest 'generic icon types render the current icons, colours, and formatting' => sub {
    my $blockdev = first_block_device();
    ok($blockdev, 'found a block device for testing');

    my @cases = (
        [ 'file',       ['plain'],         "   plain\n",                 "plain\e[0m\n" ],
        [ 'exec',       ['script'],        "   script\n",                "\e[1m\e[38;2;255;0;0mscript\e[0m\n" ],
        [ 'dir',        ['-d', 'dir'],     "   dir\n",                   "\e[38;2;0;255;255mdir\e[0m\n" ],
        [ 'linkfile',   ['linkfile'],      "   linkfile -> plain\n",     "\e[3mlinkfile -> plain\e[0m\n" ],
        [ 'linkexec',   ['linkexec'],      "   linkexec -> script\n",    "\e[3m\e[1m\e[38;2;139;0;0mlinkexec -> script\e[0m\n" ],
        [ 'linkdir',    ['-d', 'linkdir'], "   linkdir -> dir\n",        "\e[2m\e[38;2;0;255;255mlinkdir -> dir\e[0m\n" ],
        [ 'linkbroken', ['linkbroken'],    "   linkbroken -> missing\n", "\e[38;2;0;0;0m\e[48;2;255;0;0mlinkbroken -> missing\e[0m\n" ],
        [ 'pipe',       ['pipe'],          "ﳣ   pipe\n",                  "pipe\e[0m\n" ],
        [ 'socket',     ['socket'],        "   socket\n",                "\e[1m\e[38;2;255;0;0msocket\e[0m\n" ],
        [ 'link',       ['linkplain'],     "   linkplain -> pipe\n",     "\e[2mlinkplain -> pipe\e[0m\n" ],
        [ 'chardev',    ['/dev/null'],     "   /dev/null\n",             "/dev/null\e[0m\n" ],
    );

    push @cases, [
        'blockdev',
        [$blockdev],
        "   $blockdev\n",
        "$blockdev\e[0m\n",
    ] if $blockdev;

    for my $case (@cases) {
        my ($name, $args, $icons, $colour) = @{$case};
        my $icon_result = run_lls($fixture, 'iconbox', '--show_icons', '--show_name', @{$args});
        my $colour_result = run_lls($fixture, 'iconbox', '--show_name', '--force_colour', @{$args});

        assert_success($icon_result, "$name icons");
        assert_success($colour_result, "$name colour");
        is($icon_result->{stdout}, $icons, "$name icons and formatting match");
        is($colour_result->{stdout}, $colour, "$name forced colour output matches");
    }
};

subtest 'specific bz2, .DS_Store, and /t entries keep the current icons, colours, and formatting' => sub {
    my @cases = (
        [ 'bz2',      ['archive.bz2'], "  archive.bz2\n", "archive.bz2" ],
        [ 'ds_store', ['.DS_Store'],   "  .DS_Store\n",   '.DS_Store' ],
        [ 't_dir',    ['-d', 't'],     "  t\n",           't' ],
    );

    for my $case (@cases) {
        my ($name, $args, $icons, $plain_name) = @{$case};
        my $icon_result = run_lls($fixture, 'iconbox', '--show_icons', '--show_name', @{$args});
        my $colour_result = run_lls($fixture, 'iconbox', '--show_name', '--force_colour', @{$args});

        assert_success($icon_result, "$name icons");
        assert_success($colour_result, "$name colour");
        is($icon_result->{stdout}, $icons, "$name icons and formatting match");
        is($colour_result->{stdout}, "$plain_name\e[0m\n", "$name forced colour output matches");
    }
};

done_testing;

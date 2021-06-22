use strict;
use warnings;
use utf8;

binmode(STDOUT, "encoding(UTF-8)");

my @chars = ( '⠟', '⠯', '⠷', '⠾', '⠽', '⠻' );

$| = 1;
print "\e[?25l"; # turn off cursor
$SIG{INT} = sub { print "\e[0H\e[0J\e[?25h"; exit };

while(@chars) {
    push(@chars, shift(@chars));
    print $chars[0];
    select(undef, undef, undef, 0.1);
    print "\b";
}

package Test::Builder2::CanSet;

use Test::Builder2::Mouse ();
use Test::Builder2::Mouse::Role;

sub eq_set {
    my $self = shift;
    my($have, $want) = @_;
    return 0 unless @$have == @$want;

    my @have = sort @$have;
    my @want = sort @$want;

    for my $idx (0..$#have) {
        return 0 if $have[$idx] ne $want[$idx];
    }

    return 1;
}

no Test::Builder2::Mouse;

1;

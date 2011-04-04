#!/usr/bin/env perl

use strict;
use warnings;

use lib 't/lib';
BEGIN { require 't/test.pl' }

my $CLASS = "Test::Builder2::Result";
use_ok $CLASS;

note "diag"; {
    my $result = $CLASS->new(
        pass    => 1
    );

    $result->diag->{foo} = "bar";

    $result->add_diag({
        some    => "stuff",
        and     => ["some", "things"]
    });

    is_deeply $result->diag, {
        some    => "stuff",
        and     => ["some", "things"],
        foo     => "bar",
    };
}

note "have, want, cmp"; {
    my $result = $CLASS->new(
        pass    => 0
    );

    $result->have(23);
    $result->want(42);
    $result->cmp("==");

    is_deeply $result->diag, {
        have    => 23,
        want    => 42,
        cmp     => "=="
    };
}

done_testing;

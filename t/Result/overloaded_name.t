#!/usr/bin/env perl

use strict;
use warnings;

use lib 't/lib';
BEGIN { require "t/test.pl" }
plan skip_all "need overloading" unless eval { require overload };

my $CLASS = "Test::Builder2::Result";
use_ok $CLASS;

use MyOverload;

note "coerce name from an object"; {
    my $obj = Overloaded::Ify->new( "foo" );
    is "$obj", "foo";

    my $result = $CLASS->new(
        pass    => 1,
        name    => $obj
    );

    is $result->name, "foo";
}

note "coerce name from undef"; {
    my $result = $CLASS->new(
        pass    => 1,
        name    => undef,
    );

    is $result->name, '';
}

done_testing;

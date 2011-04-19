#!/usr/bin/env perl

# Test that results are mutable

use strict;
use warnings;

BEGIN { require "t/test.pl" }

use Test::Builder2::Result;

note "Change pass to fail"; {
    my $result = Test::Builder2::Result->new(
        result  => "pass"
    );

    # Did I say pass?  I meant fail.
    $result->result("fail");
    is $result->result, "fail";
    ok !$result->passed;
    ok $result->failed;
    ok !$result->skipped;
    ok $result->count_as_failure;
}


note "Change fail to skip"; {
    my $result = Test::Builder2::Result->new(
        result  => "fail"
    );

    # Did I say fail?  I meant skip.
    $result->result("skip");
    is $result->result, "skip";
    ok !$result->passed;
    ok !$result->failed;
    ok $result->skipped;
    ok !$result->count_as_failure;
}


note "Change skip to fail"; {
    my $result = Test::Builder2::Result->new(
        skip => "mistakes were made"
    );

    # Did I say skip?  I meant fail.
    $result->result("fail");
    is $result->result, "fail";
    ok !$result->passed;
    ok $result->failed;
    ok !$result->skipped;
    ok $result->count_as_failure;
    is_deeply $result->modifiers, {};
}


done_testing();

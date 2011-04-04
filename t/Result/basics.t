#!/usr/bin/perl -w

use strict;
use warnings;

BEGIN { require 't/test.pl' }

my $CLASS = 'Test::Builder2::Result';
require_ok $CLASS;

note "Pass"; {
    my $result = new_ok($CLASS, [ pass => 1 ]);

    ok $result->passed;
    ok !$result->failed;
    ok !$result->is_todo;
    ok !$result->skipped;
    is_deeply $result->directives, {};
    ok $result;
}

note "Fail"; {
    my $result = new_ok($CLASS, [ pass => 0 ]);

    ok !$result->passed;
    ok $result->failed;
    ok !$result->skipped;
    ok !$result;
}


note "Skip"; {
    my $result = new_ok($CLASS, [ skip => 0 ]);

    ok !$result->passed;
    ok !$result->failed;
    ok $result->skipped;
    is $result->skip_reason, 0;
    ok $result->has_directive("skip");
    ok $result;
}


note "TODO"; {
    my $result = new_ok($CLASS, [ pass => 1, todo => 0 ]);

    ok $result->passed;
    ok $result->is_todo;
    is $result->todo_reason, 0;
    ok $result;
}

note "skip todo"; {
    my $result = new_ok($CLASS, [ skip => "because", todo => "yeah" ]);

    ok $result;
    ok $result->is_todo;
    ok $result->skipped;
    ok !$result->passed;
}

note "TODO with no message"; {
    my $result = new_ok($CLASS, [ pass => 0, todo => undef ]);

    ok $result->is_todo(), 'Todo with no message';
    is $result->todo_reason, '';
    ok $result;
}

note "as_hash"; {
    my $result = new_ok($CLASS, [
        pass            => 1,
        name            => 'something something something test result',
        test_number     => 23,
        file            => 'foo.t',
        line            => 2,
        have            => 23,
        want            => 42,
        cmp             => "==",
    ]);

    is_deeply $result->as_hash, {
        result          => 'pass',
        name            => 'something something something test result',
        test_number     => 23,
        file            => 'foo.t',
        line            => 2,
        diag            => {
            have        => 23,
            want        => 42,
            cmp         => "==",
        },
        directives      => {},
        event_type      => "result"
    }, 'as_hash';
}


done_testing;

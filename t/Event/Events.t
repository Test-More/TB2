#!/usr/bin/perl

use strict;
use warnings;

BEGIN { require "t/test.pl"; }
use Test::Builder2::Events;

my @events = map { "Test::Builder2::Event::".$_ }
                 qw(StreamStart StreamEnd SetPlan StreamMetadata Log Comment);
push @events, "Test::Builder2::Result";

for my $class (@events) {
    ok $class->can("event_type"), "$class loaded";
}

done_testing;

#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    # Ensure things print immediately to make parent/child printing
    # more predictable.
    $|=1;

    require "t/test.pl";
}

my $CLASS = "TB2::SyncStore";

use_ok $CLASS;

note "creation"; {
     new_ok $CLASS;
}


note "object for testing"; {
    package Some::Object;
    use TB2::Mouse;
    with "TB2::HasObjectID";
}

note "files stick around through a fork"; {
    {
        my $store = new_ok $CLASS;

        my $obj = Some::Object->new;

        $store->write_and_unlock($obj);

        my $pid;
        if( $pid = fork ) { # parent
            note "Parent";
            is $store->read_and_lock($obj)->object_id, $obj->object_id;
            $store->write_and_unlock($obj);
        }
        else {       # child
            note "Child";
            sleep 1;       # let the parent go first
            next_test;     # account that the parent has done a test
            is $store->read_and_lock($obj)->object_id, $obj->object_id;
            $store->write_and_unlock($obj);
            exit;
        }

        wait;

        next_test;  # account for the child's test

        is $store->read_and_lock($obj)->object_id, $obj->object_id;
        $store->write_and_unlock($obj);
    }
}

done_testing;

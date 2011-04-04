package Test::Builder2::Formatter::POSIX;

use Test::Builder2::Mouse;

extends 'Test::Builder2::Formatter';

sub accept_event {
    my $self  = shift;
    my $event = shift;

    if( $event->event_type eq 'stream start' ) {
        $self->write(output => "Running $0\n");
    }

    return;
}

sub result_type {
    my $self = shift;
    my $result = shift;

    my $type = $result->passed  ? "PASS"        :
               $result->failed  ? "FAIL"        :
               $result->skipped ? "UNTESTED"    :
                                  "UNKNOWN"     ;
    $type = "X$type" if $result->is_todo && !$result->skipped;
    return $type
}

sub accept_result {
    my($self, $result) = @_;

    my $type = $self->result_type($result);
    my $name = $result->name;
    $self->write(output => "$type: $name\n");

    return;
}

1;

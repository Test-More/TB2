package TB2::Result::Role::todo;

use Mouse ();
use Mouse::Role;

our $VERSION = '1.005000_001';
$VERSION = eval $VERSION;    ## no critic (BuiltinFunctions::ProhibitStringyEval)


sub is_todo { 1 }
sub is_fail { 0 }

no Mouse::Role;

1;


=head1 NAME

TB2::Result::Role::todo - The assert is expected to fail

=head1 DESCRIPTION

Apply this role to a Result::Base object if the assert ran but is
expected to fail.

=cut

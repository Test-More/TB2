package Test::Builder2::Formatter::TAP::v13;

use 5.008001;

use Test::Builder2::Mouse;
use Carp;
use Test::Builder2::Types;

extends 'Test::Builder2::Formatter';

has nesting_level =>
  is            => 'rw',
  isa           => 'Test::Builder2::Positive_Int',
  default       => 0
;

has indent_nesting_with =>
  is            => 'rw',
  isa           => 'Str',
  default       => "    "
;

sub default_streamer_class { 'Test::Builder2::Streamer::TAP' }

=head1 NAME

Test::Builder2::Formatter::TAP::v13 - Formatter as TAP version 13

=head1 SYNOPSIS

  use Test::Builder2::Formatter::TAP::v13;

  my $formatter = Test:::Builder2::Formatter::TAP::v13->new;
  $formatter->begin();
  $formatter->result($result);
  $formatter->end($plan);


=head1 DESCRIPTION

Formatter Test::Builder2::Result's as TAP version 13.

=head1 METHODS

As Test::Builder2::Object with the following changes and additions.

=head3 out

=head3 err

These methods are just shorthand for:

  $output->write(out => @args);
  $output->write(err => @args);

=cut


sub _prepend {
    my($self, $msg, $prefix) = @_;

    # Put '# ' at the beginning of each line
    $msg =~ s{^}{$prefix};
    $msg =~ s{\n(?!\z)}{\n$prefix}g;

    return $msg;
}

sub _add_indentation {
    my $self = shift;
    my $output = shift;

    my $level = $self->nesting_level;
    return unless $level;

    my $indent = $self->indent_nesting_with x $level;
    for my $idx (0..$#{$output}) {
        $output->[$idx] = $self->_prepend($output->[$idx], $indent);
    }

    return;
}

sub out {
    my $self = shift;
    $self->_add_indentation(\@_);
    $self->write(out => @_);
}

sub err {
    my $self = shift;
    $self->_add_indentation(\@_);
    $self->write(err => @_);
}

=head3 begin

The %plan can be one and only one of...

  tests => $number_of_tests

  no_plan => 1

  skip_all => $reason

=cut

sub INNER_begin {
    my $self = shift;
    my %args = @_;

    croak "begin() takes only one pair of arguments" if keys %args > 1;

    $self->out("TAP version 13\n");

    if( exists $args{tests} ) {
        $self->out("1..$args{tests}\n");
    }
    elsif( exists $args{skip_all} ) {
        $self->out("1..0 # skip $args{skip_all}");
    }
    elsif( exists $args{no_plan} ) {
        # ...do nothing...
    }
    elsif( keys %args == 1 ) {
        croak "Unknown argument @{[ keys %args ]} to begin()";
    }
    else {
        # ...do nothing...
    }

    return;
}

=head3 result

Takes a C<Test::Builder2::Result> as an argument and displays the
result details.

=cut

sub INNER_result {
    my $self = shift;
    my $result = shift;

    # FIXME: there is a lot more detail in the 
    # result object that I ought to do deal with.

    my $out = "";
    $out .= "not " if !$result->literal_pass;
    $out .= "ok";

    $out .= " ".$result->test_number   if defined $result->test_number;

    my $name = $result->description;
    $self->_escape(\$name);
    $out .= " - $name" if defined $name and length $name;

    my $reason = $result->reason;
    $self->_escape(\$reason);

    my @directives;
    push @directives, "TODO" if $result->is_todo;
    push @directives, "SKIP" if $result->is_skip;

    $out .= " # @{[ join ' ', @directives ]} $reason" if @directives;
    $out .= "\n";

    $self->out($out);

    if(!$result->literal_pass and !$result->is_skip) {
        $self->_comment_diagnostics($result) if $self->show_comment_diagnostics;
        $self->_structured_diagnostics($result) if defined $self->structured_diagnostics_type;
    }

    return;
}

has show_comment_diagnostics => 
   is => 'rw',
   isa => 'Bool',
   default => 1,
;

# Emit old style comment failure diagnostics
sub _comment_diagnostics {
    my($self, $result) = @_;

    my $msg = '  ';

    $msg .= $result->is_todo ? "Failed (TODO) test" : "Failed test";

    # Failing TODO tests are not displayed to the user.
    my $out_method = $result->is_todo ? "out" : "err";

    my($file, $line, $name) = map { $result->$_ } qw(file line name);

    if( defined $name ) {
        $msg .= " '$name'\n ";
    }
    if( defined $file ) {
        $msg .= " at $file";
    }
    if( defined $line ) {
        $msg .= " line $line";
    }

    # Start on a new line if we're being output by Test::Harness.
    # Makes it easier to read
    $self->$out_method("\n") if $ENV{HARNESS_ACTIVE};
    $self->$out_method($self->comment("$msg.\n"));

    return;
}

has structured_diagnostics_type => 
   is => 'rw',
   isa => 'Maybe[Str]', # should really be an enum(JSON/YAML) 
   default => sub{undef},
   trigger => sub{ shift->_require_structured_diagnostics_type },
;
sub BUILD { 
   my $self = shift;
   $self->_require_structured_diagnostics_type;
}

sub _require_structured_diagnostics_type {
   my $self = shift;
   my $type = $self->structured_diagnostics_type;

   # no need to run anything if we are not using struc_diag
   return unless defined $type;

   eval qq{require $type} 
    or do { $self->err( sprintf q{%s failed to resolve as a structured diagnostics type, disabling structured diagnostics.},
                       $type
                      );
            $self->structured_diagnostics_type(undef);
          };
}

sub _structured_diagnostics {
    my($self, $result) = @_;
use Data::Dumper;

    unless ( defined $self->structured_diagnostics_type ) {
       $self->err('structured_diagnostics_type is not defined, _structured_diagnostics was called in error.');
       return ;
    }

    my $SD_method = sprintf q{_structured_diagnostics_%s}, $self->structured_diagnostics_type;
    return $self->err( sprintf q{%s does not have a method %s to impliment %s as a structured diagnostics type.},
                               __PACKAGE__,
                               $SD_method,
                               $self->structured_diagnostics_type
                     );
    my $struct = { %$result }; # for now just unpack the result
die Dumper( { STRUCT => $struct } );
warn 'HELLO';
    $self->out( 'STRUCT DIAG'. $self->$SD_method($struct) );
    return;
}

sub _structured_diagnostics_JSON {
    require JSON;
    my($self, $struct) = @_;
   
    my $JSON = JSON->new->allow_nonref->allow_blessed(1)->convert_blessed(1); 
    #$JSON->allow_blessed(1);
    #$JSON->convert_blessed(1);
    $JSON->encode($struct);
}

sub _structured_diagnostics_YAML {
    require YAML;
    my($self, $struct) = @_;
    YAML::Dump($struct);
}

=head3 comment

  my $comment = $self->comment(@message);

Will turn the given @message into a TAP comment.

    # returns "# Basset houndsgot long ears"
    $self->comment("Basset hounds", "got long ears");

=cut

sub comment {
    my $self = shift;

    return unless @_;

    # Smash args together like print does.
    # Convert undef to 'undef' so its readable.
    my $msg = join '', map { defined($_) ? $_ : 'undef' } @_;

    $msg = $self->_prepend($msg, "# ");

    # Stick a newline on the end if it needs it.
    $msg .= "\n" unless $msg =~ /\n\z/;

    return $msg;
}


sub _escape {
    my $self = shift;
    my $string = shift;

    return if !defined $$string;

    $$string =~ s{\n}{\\n}g;

    return;
}

=head3 end

Similar to C<begin()>, it takes either no or one and only one pair of arguments.

  tests => $number_of_tests

=cut

sub INNER_end {
    my $self = shift;

    my %args = @_;

    croak "end() takes only one pair of arguments" if keys %args > 1;

    if( exists $args{tests} ) {
        $self->out("1..$args{tests}\n");
    }
    elsif( keys %args == 1 ) {
        croak "Unknown argument @{[ keys %args ]} to end()";
    }
    else {
        # ...do nothing...
    }

    return;    
}

1;

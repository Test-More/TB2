#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

my $module = shift or die "Usage: $0 module_name\n";

my $tree = Pod::Include::Tree->new;
$tree->parse_from_module($module);

my $out_file = shift || do {
    local $_ = $tree->{file_name};
    s/\.pm$/.pod/;
    $_;
};

open my $out, '>', $out_file or die "No open > $out_file: $!";
print $out $tree->to_str;
close $out;

exit;



package Pod::Include::Tree;

# Class to parse pod into a tree, where =head1 contains =head2
# contains =head3 contains =head4.

use base qw[Pod::Parser];

sub parse_from_module {
    my ($self, $module) = @_;

    my $path = "$module.pm";
    $path =~ s!::!/!g;

    unless ($INC{$path}) {
        eval "require $module";
        die $@ if $@;
    }

    my $file = $INC{$path};

    $self->{module_name} = $module;
    $self->{file_name}   = $file;

    $self->parse_from_file($file);
}

sub begin_pod {
    my $self = shift;

    # Pretend pod starts with =head0 paragraph.
    my $root = Pod::Include::Node::Head->new(0, '', '');

    # Root of tree.
    $self->{root} = $root;

    # The last seen =headN node, indexed by level N.  Root is indexed
    # at 0, =head1 at 1, =head2 at 2, etc.  This is used to find a
    # parent =headN-1 node.
    $self->{prev_head}[0] = $root;

    # The current =headN node.
    $self->{this_head} = $root;

    # Map section name to =headN node.  This is used to get a specific
    # section of an external module for inclusion.
    $self->{node}{$root->{name}} = $root;

    # Track all section names, both "=headN sec-name" and X<sec-name>.
    # This is used to check for existing duplicates, to filter out
    # duplicate sections from inclusion, and to disambiguate
    # L<name_or_section>.
    $self->{saw_section}{$root->{name}}++;

    # Flag to parse X<> for section name.  This is used to limit
    # parsing of X<> to =headN paragraphs and the paragraph
    # immediately following.
    $self->{active_X} = 0;
}

sub command {
    my ($self, $cmd, $arg, $line_num, $pod_para) = @_;

    # =head1, =head2, =head3, =head4
    if ($cmd =~ /^head([1-4])$/) {
        my $level = $1;

        my $parent_level = $level - 1;
        my $parent = $self->{prev_head}[$parent_level]
            or die "No parent =head$parent_level at " . $pod_para->file_line;

        my $sec = Pod::Include::Name->normalize($arg, $line_num);
        ! $self->{saw_section}{$sec}++
            or die "Duplicate section (=$cmd $sec) at " . $pod_para->file_line;

        # Activate X<> here and leave activated for next paragraph.
        # All other paragraphs (command, verbatim, textblock) should
        # deactivate it.
        $self->{active_X} = 1;

        my $text = $pod_para->raw_text;
        $text = $self->interpolate($text, $line_num);
        
        my $head = Pod::Include::Node::Head->new($level, $sec, $text);

        $self->{prev_head}[$level] = $head;
        $self->{node}{$sec}        = $head;
        $self->{this_head}         = $head;

        $parent->add_node($head);

        return;
    }

    # Deactivate X<> for all other command paragraphs.
    $self->{active_X} = 0;

    # =include, =for include
    if ($cmd eq 'for' && $arg =~ s/^include\s// or $cmd eq 'include') {
        my $inc = Pod::Include::Node::Include->new($arg, $pod_para);
        $self->{this_head}->add_node($inc);
        return;
    }

    # Anything other than =headN and =include is just text.
    my $text = $pod_para->raw_text;

    # For L<> in subclass Pod::Include::Tree::Graft.
    $text = $self->interpolate($text, $line_num);

    $self->{this_head}->add_text($text);
}

sub verbatim {
    my ($self, $text, $line_num, $pod_para) = @_;
    $self->{active_X} = 0;
    $self->{this_head}->add_text($text);
}

sub textblock {
    my ($self, $text, $line_num, $pod_para) = @_;
    $text = $self->interpolate($text, $line_num);
    $self->{active_X} = 0;
    $self->{this_head}->add_text($text);
}

sub interior_sequence {
    my ($self, $cmd, $arg, $pod_seq) = @_;

    # Check X<> for section name, but only if X<> is in =headN
    # paragraph or paragraph immediately following.

    if ($cmd eq 'X' && $self->{active_X}) {
        my $sec = Pod::Include::Name->normalize($arg);
        ! $self->{saw_section}{$sec}++
            or die "Duplicate section (X<$sec>) at " . $pod_seq->file_line;
        push @{$self->{this_head}{names}}, $sec;
    }

    return $pod_seq->raw_text;
}

# Override interpolate(), adding simple check to see if call is
# necessary.
sub interpolate {
    my ($self, $text, $line_num) = @_;
    return $self->has_seq($text)
        ? $self->SUPER::interpolate($text, $line_num)
        : $text;
}

# Don't interpolate unless looking for and found X<>.
sub has_seq {
    my ($self, $text) = @_;
    return $self->{active_X} && $text =~ /X</;
}

# Return tree as string.
sub to_str {
    my $self = shift;
    my $module = $self->{module_name};

    # Cache of parsed module tree.
    my %tree_cache;

    # Every module-section seen, marked as either 'absolute' or
    # 'relative'.  Sections in and sections included into the original
    # module allow 'relative' links; all other sections require
    # 'absolute' links.
    my %link;

    # Sections in and sections already included into the original
    # module.  Subsequent sections are filtered for duplicates before
    # inclusion.
    my %section;

    for my $sec (keys %{$self->{saw_section}}) {
        $link{"$module $sec"} = 'relative';
        $section{$sec}++;
    }

    # Track signature of each =include seen, to avoid including in an
    # endless loop.
    my %signature;

    # Bundle everything into a single variable and pass along to every
    # node as they are stringified.
    my $saw = {
        link       => \%link,
        section    => \%section,
        signature  => \%signature,
        tree_cache => \%tree_cache,
    };

    my $str = $self->{root}->to_str($saw);

    # Included relative links will contain a bit of illegal pod.  The
    # link will remain relative or made absolute, depending on whether
    # the linked-to section was also include.

    $str =~ s{E<--relative-->((\S+).+?)E<--end-->}{
        $link{$1} && $link{$1} eq 'relative' ? '' : $2
    }ge;

    # Included ambiguous links will also contain a bit of illegal pod.
    # The L<ambiguous> is either L<name> or L<section>, and if
    # L<section>, will either remain relative or made absolute.

    $str =~ s{E<--ambiguous-->((\S+)\s+(.+?))E<--end-->}{
        $link{$1} ? ($link{$1} eq 'relative' ? "/$3" : "$2/$3") : $3
    }ge;

    return $str;
}

package Pod::Include::Tree::Graft;

# Subclass of Pod::Include::Tree for parsing included modules.  In
# particular, also parses L<>.

use base qw[Pod::Include::Tree];

sub interior_sequence {
    my ($self, $cmd, $arg, $pod_seq) = @_;

    $cmd eq 'L'
        or return $self->SUPER::interior_sequence($cmd, $arg, $pod_seq);

    my ($text, $name, $section, $ambiguous) = 
        Pod::Include::Util::parse_link($arg);
    my $module = $self->{module_name};
    my $markup;

    # Mark up relative links.  If a link and its corresponding
    # linked-to section are included into another pod document,
    # then the link remains relative.  But if only the link is
    # included, then the link needs to be absolute.

    if (defined $section && ! defined $name) {
        my $sec = Pod::Include::Name->normalize($section);
        $markup = "E<--relative-->$module ${sec}E<--end-->/$section";
    }

    # Mark up ambiguous links.  Once the entire pod document is
    # parsed, a list of sections can be used to clarify links.

    elsif ($ambiguous) {
        $markup = "E<--ambiguous-->$module ${ambiguous}E<--end-->";
    }

    if ($markup) {
        $markup = "$text|$markup" if defined $text;
        return "L$pod_seq->{-ldelim}$markup$pod_seq->{-rdelim}";
    }

    return $pod_seq->raw_text;
}

# Add L<> to sequences to interpolate. 
sub has_seq {
    my ($self, $text) = @_;
    return $text =~ /L</ || $self->SUPER::has_seq($text);
}

package Pod::Include::Node;

# Return all the names of a section.  This one doesn't return
# anything, but is inherited by all nodes, so it can be recursively
# called without checking if a node implements it.
sub get_names {
    return;
}

package Pod::Include::Node::Head;

# Node for =head1, =head2, =head3 and =head4.

use base qw[Pod::Include::Node];

sub new {
    my ($class, $level, $name, $text) = @_;

    bless {
        level    => $level,   # The N level in =headN.
        name     => $name,    # The normalized section name.
        names    => [$name],  # Additional section names, populated by X<>.
        text     => $text,    # The interpolated =headN paragraph.
        children => [],       # Child nodes.
    }, $class;

}

sub add_node {
    my ($self, $node) = @_;
    push @{$self->{children}}, $node;
}

sub add_text {
    my ($self, $text) = @_;

    # Get the last kid.
    my $kids = $self->{children};
    my $kid = @$kids && $kids->[-1];

    # If last kid is not a 'Text' node, then add one that is.
    unless ($kid && $kid->isa('Pod::Include::Node::Text')) {
        $kid = Pod::Include::Node::Text->new;
        $self->add_node($kid);
    }

    $kid->add_text($text);
}

sub to_str {
    my ($self, $saw) = @_;
    my $str = $self->{text};
    $str .= $_->to_str($saw) for @{$self->{children}};
    $str;
}

sub get_names {
    my $self = shift;
    return @{$self->{names}}, map $_->get_names, @{$self->{children}};
}

package Pod::Include::Node::Include;

use base qw[Pod::Include::Node];

sub new {
    my ($class, $arg, $pod_para) = @_;
    my ($file, $line_num) = $pod_para->file_line;

    # Parse include configuration into hash.
    my $self = Pod::Include::Util::parse_include($arg, $file, $line_num);

    # Module to include is required.
    $self->{module}
        or die "No module in =include at $file:$line_num\n";

    # Normalize section to include, if any.
    $_ = $_ ? Pod::Include::Name->normalize($_) : ''
        for $self->{section};

    # Default is no nodes.
    $self->{nodes} ||= '';

    # Create a signature, to avoid including the same =include again.
    $self->{signature} = join ', ', 
                         map "$_: $self->{$_}",
                         qw[module section nodes];

    for ($self->{nodes}) {
        $_ or last;                # No nodes, get entire section.
        my @nodes;
        if ($_ eq '*') {           # Any nodes, get all children of section.
            @nodes = "Pod::Include::Node";
        } else {                   # Get specific nodes.
            for (split /,\s*/) {
                s/^=//;            # Allow "=head" and...
                $_ = ucfirst lc;   # ..."head" and "HEAD" to mean "Head".
                $_ = "Pod::Include::Node::$_";
                push @nodes, $_;
            }
        }
        $_ = \@nodes;
    }

    $self->{pod_para} = $pod_para;

    bless $self, $class;
}

sub to_str {
    my ($self, $saw) = @_;

    # An included module may include another module which may include
    # yet another module and so on.  This forms an =include tree.  To
    # avoid including in an endless loop, need to track the nodes in
    # the path from root down to current node.  Don't care about nodes
    # in other branches.

    # Localize signature key, so this and any =include nodes in this
    # branch are not seen by other branches.

    my %copy = %{$saw->{signature}};
    local $saw->{signature} = \%copy;

    # Check that this =include node hasn't already been included along
    # this path.

    my $sign = $self->{signature};
    if ($copy{$sign}++) {
        my $loc = $self->{pod_para}->file_line;
        die "Section already included ($sign) at $loc\n";
    }

    my $module  = $self->{module};
    my $section = $self->{section};
    my $nodes   = $self->{nodes};

    my $graft = $saw->{tree_cache}{$module};
    unless ($graft) {
        $graft = Pod::Include::Tree::Graft->new;
        $graft->parse_from_module($module);
        $saw->{tree_cache}{$module} = $graft;
    }

    my $node = $graft->{node}{$section};
    unless ($node) {
        my $loc = $self->{pod_para}->file_line;
        die "Section not found ($module/$section) at $loc\n";
    }

    my @kids;
    for my $kid (@{$node->{children}}) {
        # Filter out nodes not specified.
        next if $nodes && ! grep $kid->isa($_), @$nodes;

        # Filter out any sections already included.
        my $names = $_->{names};
        next if $names && grep $saw->{section}{$_}, @$names;

        push @kids, $kid;
    }

    # Names of all the new included sections.
    my @names;

    # String of new included nodes.
    my $str = '';

    # If no specific nodes requested, then include the requested
    # section itself.
    unless ($nodes) {
        push @names, @{$node->{names}};
        $str .= $node->{text};
    }

    # Add names of all sub-sections.
    push @names, map $_->get_names, @kids;

    # Mark links to every section as 'absolute'.
    $saw->{link}{"$module $_"} ||= 'absolute'
        for keys %{$graft->{saw_section}};

    for (@names) {
        # Mark links to every included section as 'relative'.
        $saw->{link}{"$module $_"} = 'relative';

        # Add all included sections.
        $saw->{section}{$_}++;
    }

    $str .= $_->to_str($saw) for @kids;

    if (my $replace = $self->{replace}) {
        my $re = join '|', map quotemeta, keys %$replace;
        $str =~ s/($re)/$replace->{$1}/g;
    }

    return $str;
}

package Pod::Include::Node::Text;

use base qw[Pod::Include::Node];

sub new {
    bless {text => ''}, shift;
}

sub add_text {
    my ($self, $text) = @_;
    $self->{text} .= $text;
}

sub to_str {
    my $self = shift;
    $self->{text};
}

package Pod::Include::Name;

# Class for normalizing section names.

use base qw[Pod::Parser];
use Pod::Escapes qw[e2char];

# Singleton for this class.
my $PIN;

sub normalize {
    my ($class, $name, $line_num) = @_;
    local $_ = $name;
    return '' unless length;

    $PIN ||= Pod::Include::Name->new;

    # Interpolate L<> first, to get the raw link for parse_link().
    if (/L</) {
        $PIN->{interpolate} = 'L';
        $_ = $PIN->interpolate($_, $line_num);
    }

    # Now interpolate everything else.
    if (/[A-Z]</) {
        $PIN->{interpolate} = '';
        $_ = $PIN->interpolate($_, $line_num);
    }

    # Normalize whitespace.
    return join ' ', split;
}

sub interior_sequence { 
    my ($self, $cmd, $arg, $pod_seq) = @_;

    # Replace L<> with text per perlpodspec.
    if ($self->{interpolate} eq 'L') {
        return $pod_seq->raw_text unless $cmd eq 'L';

        my ($text, $name, $section, $ambiguous) = 
            Pod::Include::Util::parse_link($arg);

        return $text                    if defined $text;
        return qq<"$section" in $name>  if defined $section && defined $name;
        return qq<"$section">           if defined $section;
        return $name                    if defined $name;
        return $ambiguous;
    }

    # Replace E<> with character.
    if ($cmd eq 'E') {
        my $char = e2char($arg);
        return defined $char
            ? $char
            : $pod_seq->raw_text;
    }

    # Remove X<> and Z<> entirely.
    if ($cmd eq 'X' || $cmd eq 'Z') {
        return '';
    }

    # Replace B<>, I<>, C<>, etc with contents.
    return $arg;
}

package Pod::Include::Util;

use Pod::ParseLink;

# Parse L<text|name/sec> to return $text, $name, $section and
# $ambiguous (link to either name or section, but not sure which).

sub parse_link {
    my $link = shift;
    my ($text, $inferred, $name, $section, $type) = parselink($link);
    my $ambiguous;

    # Pod::ParseLink follows perlpodspec and only checks if there is a
    # space to disambiguate names and sections.  Do some additional
    # checks here.

    if (defined $name && ! defined $section) {
        if ($name =~ /^perl\w*$/) {
            # L<perlop>
        } elsif ($name =~ /^\w+(?:::\w+)+$/) {
            # L<Module::Name>
        } elsif ($name =~ /^\w+\(\d\w?\)$/) {
            # L<crontab(5)>
        } elsif ($name =~ /^[^\W\d]\w*$/) {
            # L<Ambiguous>
            $ambiguous = $name;
            $name = undef;
        } else {
            # L<$self->method($arg)>
            $section = $name;
            $name = undef;
        }
    }

    return $text, $name, $section, $ambiguous;
}

# Parse include configuration into hash.  Recognized keys are:
#
#   module:   The name of the module to include.
#   section:  The name of the section in that module.
#   nodes:    The nodes in that section to keep.
#   replace:  String replacement hash.  Replace keys with values.
#
# For example:
#
#   =include
#       module:  TB2::EventCoordinator
#       section: Attributes
#       nodes:   =head
#       replace:
#           $ec: $state

sub parse_include {
    my ($text, $file, $line) = @_;

    # Base hash to populate.
    my $attr = {};

    # Push/pop $attr to/from stack for hash of hash. 
    my @stack;

    # Indent level of previous line.
    my $prev_indent = $text =~ /^( *)\S/m ? length $1 : 0;

    # Flag that line must be indented relative to previous line.
    my $must_indent;

    for (split /\n/, $text) {
        $line++;
        /\S/ or next;

        s/^( *)(\S+):\s*// or die "No attr key at $file:$line\n";
        my $key = $2;
        my $indent = length $1;

        # If previous line created a hash ref, must indent this one.
        if ($must_indent) {
            $must_indent = 0;
            $indent > $prev_indent
                or die "Hash not indented at $file:$line\n";
        }

        # Hash is indented, so pop stack when indentation ends.
        $attr = pop @stack if $indent < $prev_indent;

        if (/\S/) {
            # There's a value.  Set it to key.
            s/\s+$//;
            $attr->{$key} = $_;
        } else {
            # There's no value.  Must be a hash ref.
            my $hash = {};
            $attr->{$key} = $hash;

            # Push current hash to stack and replace with new hash.
            push @stack, $attr;
            $attr = $hash;

            # Check next line for indentation.
            $must_indent = 1;
        }

        $prev_indent = $indent;
    }

    # Configuration may end with hash indented, so check if stack is
    # empty.
    @stack ? pop @stack : $attr;
}

__END__

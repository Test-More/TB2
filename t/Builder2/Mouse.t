#!/usr/bin/perl

# Test Mouse will load.
# Don't use any Test::Builder stuff here because it relies on Mouse

use strict;
use warnings;

use Mouse;

print <<'END';
1..1
ok 1 - Mouse loaded
END



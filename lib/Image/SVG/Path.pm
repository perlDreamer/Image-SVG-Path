package Image::SVG::Path;
use warnings;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @SVG_REGEX = qw/
		       $closepath
		       $curveto
		       $smooth_curveto
		       $drawto_command
		       $drawto_commands
		       $elliptical_arc
		       $horizontal_lineto
		       $lineto
		       $moveto
		       $quadratic_bezier_curveto
		       $smooth_quadratic_bezier_curveto
		       $svg_path
		       $vertical_lineto
		   /;

our @FUNCTIONS = qw/extract_path_info reverse_path create_path_string/;
our @EXPORT_OK = (@FUNCTIONS, @SVG_REGEX);
our %EXPORT_TAGS = (all => \@FUNCTIONS, regex => \@SVG_REGEX);
our $VERSION = '0.28';

use Carp;

# These are the fields in the "arc" hash which is returned when an "A"
# command is processed.

my @arc_fields = qw/rx ry x_axis_rotation large_arc_flag sweep_flag x y/;

# Return "relative" or "absolute" depending on whether the command is
# upper or lower case.

sub position_type
{
    my ($curve_type) = @_;
    if (lc $curve_type eq $curve_type) {
        return "relative";
    }
    elsif (uc $curve_type eq $curve_type) {
        return "absolute";
    }
    else {
        croak "I don't know what to do with '$curve_type'";
    }
}

sub add_coords
{
    my ($first_ref, $to_add_ref) = @_;
    $first_ref->[0] += $to_add_ref->[0];
    $first_ref->[1] += $to_add_ref->[1];
}

sub reverse_path
{
    my ($path) = @_;
    my $me = 'reverse_path';
    if (! $path) {
        croak "$me: no input";
    }
    my @values = extract_path_info ($path, {
        no_shortcuts => 1,
        absolute => 1,
    });
    if (! @values) {
        return '';
    }
    my @rvalues;
    my $end_point = $values[0]->{point};
    for my $value (@values[1..$#values]) {
        my $element = {};
        $element->{type} = $value->{type};
#        print "$element->{type}\n";
        if ($value->{type} eq 'cubic-bezier') {
            $element->{control1} = $value->{control2};
            $element->{control2} = $value->{control1};
            $element->{end} = $end_point;
            $end_point = $value->{end};
        }
        else {
            croak "Can't handle path element type '$value->{type}'";
        }
        unshift @rvalues, $element;
    }
    my $moveto = {
        type => 'moveto',
        point => $end_point,
    };
    unshift @rvalues, $moveto;
    my $rpath = create_path_string (\@rvalues);
    return $rpath;
}

sub create_path_string
{
    my ($info_ref) = @_;
    my $path = '';
    for my $element (@$info_ref) {
        my $t = $element->{type};
#        print "$t\n";
        if ($t eq 'moveto') {
            my @p = @{$element->{point}};
            $path .= sprintf ("M%f,%f ", @p);
        }
        elsif ($t eq 'cubic-bezier') {
            my @c1 = @{$element->{control1}};
            my @c2 = @{$element->{control2}};
            my @e = @{$element->{end}};
            $path .= sprintf ("C%f,%f %f,%f %f,%f ", @c1, @c2, @e);
        }
        elsif ($t eq 'closepath') {
            $path .= "Z";
        }
	elsif ($t eq 'vertical-line-to') {
	    $path .= sprintf ("V%f ", $element->{y});
	}
	elsif ($t eq 'horizontal-line-to') {
	    $path .= sprintf ("H%f ", $element->{x});
	}
	elsif ($t eq 'line-to') {
	    $path .= sprintf ("L%f,%f ", @{$element->{point}});
	}
	elsif ($t eq 'arc') {
	    my @f = map {sprintf ("%f", $element->{$_})} @arc_fields;
	    $path .= "A ". join (',', @f) . " ";
	}
	else {
            croak "Don't know how to deal with type '$t'";
        }
    }
    return $path;
}

# Match the e or E in an exponent.

my $e = qr/[eE]/;

# This whitespace regex is from the SVG grammar,
# https://www.w3.org/TR/SVG/paths.html#PathDataBNF.

my $wsp = qr/[\x20\x09\x0D\x0A]/;

# The latter commented-out part of this regex fixes a backtracking
# problem caused by numbers like 123-234 which are supposed to be
# parsed as two numbers "123" and "-234", as if containing a
# comma. The regular expression blows up and cannot handle this
# format. However, adding this final part slows the module down by a
# factor of about 25%, so they are commented out.

my $comma_wsp = qr/$wsp+|$wsp*,$wsp*/;#|(?<=[0-9])(?=-)/;

# The following regular expression splits the path into pieces. Note
# this only splits on '-' or '+' when not preceeded by 'e'.  This
# regular expression is not following the SVG grammar, it is going our
# own way.

my $split_re = qr/
		     (?:
			 $comma_wsp
		     |
			 (?<!$e)(?=-)
		     |
			 (?<!$e)(?:\+)
		     )
		 /x;

# Regular expressions to match numbers

# Digit sequence

my $ds = qr/[0-9]+/;

my $sign = qr/[\+\-]/;

# Fractional constant

my $fc = qr/$ds?\.$ds/;

my $exponent = qr/$e$sign?$ds/x;

# Floating point constant

my $fpc = qr/
		$fc 
		$exponent?
	    |
		$ds
		$exponent
	    /x;


# Non-negative number. $floating_point_constant needs to go before
# $ds, otherwise it matches the shorter $ds every time.

my $nnn = qr/
		$fpc
	    |
		$ds
	    /x;

my $number = qr/$sign?$nnn/;

my $pair = qr/$number$comma_wsp?$number/;

my $pairs = qr/(?:$pair$wsp)*$pair/;

my $numbers = qr/(?:$number$wsp)*$number/;

# Quadratic bezier curve

my $qarg = qr/$pair$comma_wsp?$pair/;

our $quadratic_bezier_curveto = 
qr/
      ([Qq])
      $wsp*
      (
	  (?:$qarg $comma_wsp?)*
	  $qarg
      )
  /x;

our $smooth_quadratic_bezier_curveto =
qr/
      ([Tt])
      $wsp*
      (
	  (?:$pair $comma_wsp?)*
	  $pair
      )
  /x;

# Cubic bezier curve

my $sarg = qr/$pair$comma_wsp?$pair/;

our $smooth_curveto = qr/
			    ([Ss])
			    $wsp*
			    (
				(?:
				    $sarg
				    $comma_wsp
				)*
				$sarg
			    )
			/x;

my $carg = qr/(?:$pair $comma_wsp?){2} $pair/x;

our $curveto = qr/
		     ([Cc]) 
		     $wsp*
		     (
			 (?:$carg $comma_wsp)*
			 $carg
		     )
		 /x;

my $flag = qr/[01]/;

my $eaa = qr/
		$nnn
		$comma_wsp?
		$nnn
		$comma_wsp?
		$number
		$comma_wsp
		$flag
		$comma_wsp?
		$flag
		$comma_wsp?
		$pair
	    /x;

our $elliptical_arc = qr/([Aa]) $wsp* ((?:$eaa $comma_wsp?)* $eaa)/x;

our $vertical_lineto = qr/([Vv]) $wsp* ($numbers)/x;

our $horizontal_lineto = qr/([Hh]) $wsp* ($numbers)/x;

our $lineto = qr/([Ll]) $wsp* ($pairs)/x;

our $closepath = qr/([Zz])/;

our $moveto = qr/
		    ([Mm]) $wsp* ($pairs)
		/x;

our $drawto_command = qr/
			    (
				$closepath
			    |
				$lineto
			    |
				$horizontal_lineto
			    |
				$vertical_lineto
			    |
				$curveto
			    |
				$smooth_curveto
			    |
				$quadratic_bezier_curveto
			    |
				$smooth_quadratic_bezier_curveto
			    |
				$elliptical_arc
			    )
			/x;

our $drawto_commands = qr/
			     (?:$drawto_command $wsp)*
			     $drawto_command
			 /x;
our $mdc_group = qr/
		      $moveto
		      $wsp*
		      $drawto_commands
		  /x;

my $mdc_groups = qr/
		       $mdc_group+
		   /x;

our $moveto_drawto_command_groups = $mdc_groups;

our $svg_path = qr/
		      $wsp*
		      $mdc_groups?
		      $wsp*
		  /x;

# Old regex.

#my $number_re = qr/(?:[\+\-0-9.]|$e)+/i;

# This is where we depart from the SVG grammar and go our own way.

my $numbers_re = qr/(?:$number|$comma_wsp+)*/;

sub extract_path_info
{
    my ($path, $options_ref) = @_;
    # Error/message reporting thing. Not sure why I did this now.
    my $me = 'extract_path_info';
    if (! $path) {
        croak "$me: no input";
    }
    # Create an empty options so that we don't have to
    # keep testing whether the "options" string is defined or not
    # before trying to read a hash value from it.
    if ($options_ref) {
        if (ref $options_ref ne 'HASH') {
            croak "$me: second argument should be a hash reference";
        }
    }
    else {
        $options_ref = {};
    }
    if (! wantarray) {
        croak "$me: extract_path_info returns an array of values";
    }
    my $verbose = $options_ref->{verbose};
    if ($verbose) {
        print "$me: I am trying to split up '$path'.\n";
    }
    my @path_info;
    my $has_moveto = ($path =~ /^$wsp*([Mm])$wsp*($numbers_re)(.*)$/s);
    if (! $has_moveto) {
        croak "No moveto at start of path '$path'";
    }
    my ($moveto_type, $move_to, $curves) = ($1, $2, $3);
    if ($verbose) {
        print "$me: The initial moveto looks like '$moveto_type' '$move_to'.\n";
    }
    # Deal with the initial "move to" command.
    my $position = position_type ($moveto_type);
    my @coords = split $split_re, $move_to;
    if (@coords < 2) {
	croak "$me: Not enough numerical values for the initial M command in '$path'";
    }
    push @path_info, {
        type => 'moveto',
	name => 'moveto',
        position => $position,
        point => [@coords[0, 1]],
        svg_key => $moveto_type,
    };
    # Deal with any implicit line-to's remaining.
    if (@coords > 2) {
	# Check the number of coordinates is valid.
	if (@coords % 2 != 0) {
	    croak "$me: Odd number of values for an implicit L command " .
	    scalar (@coords) . " in '$path'";
	}
	if ($verbose) {
	    print "$me: dealing with extra stuff in ", join (', ', @coords),
	    ".\n";
	}
	# Add the remaining numbers as line-to elements, deleting the
	# first two.
	push @path_info, build_lineto ($position, splice (@coords, 2));
    }
    # Deal with the rest of the path.
    my @curves;
    while ($curves =~ /\G(([cslqtahvzm])$wsp*($numbers_re))/gi) {
	my $original = $1;
	my $command = $2;
	my $values = $3;
	if ($original !~ /$moveto|$drawto_command/x) {
	    warn "Cannot parse '$original' using moveto/drawto_command regex";
	}
        push @curves, [$command, $values, $original];
    }
    for my $curve_data (@curves) {
        my ($curve_type, $curve) = @$curve_data;
        $curve =~ s/^,//;
#	print "$curve\n";
        my @numbers = split $split_re, $curve;
#	print "@numbers\n";
        if ($verbose) {
            print "$me: Extracted numbers: @numbers\n";
        }
        if (uc $curve_type eq 'C') {
            my $expect_numbers = 6;
            if (@numbers % 6 != 0) {
                croak "$me: Wrong number of values for a C curve " .
                    scalar @numbers . " in '$path'";
            }
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers / 6; $i++) {
                my $offset = 6 * $i;
                my @control1 = @numbers[$offset + 0, $offset + 1];
                my @control2 = @numbers[$offset + 2, $offset + 3];
                my @end      = @numbers[$offset + 4, $offset + 5];
                # Put each of these abbreviated things into the list
                # as a separate path.
                push @path_info, {
                    type => 'cubic-bezier',
		    name => 'curveto',
                    position => $position,
                    control1 => \@control1,
                    control2 => \@control2,
                    end => \@end,
                    svg_key => $curve_type,
                };
            }
        }
        elsif (uc $curve_type eq 'S') {
            my $expect_numbers = 4;
            if (@numbers % $expect_numbers != 0) {
                croak "$me: Wrong number of values for an S curve " .
                    scalar @numbers . " in '$path'";
            }
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers / $expect_numbers; $i++) {
                my $offset = $expect_numbers * $i;
                my @control2 = @numbers[$offset + 0, $offset + 1];
                my @end      = @numbers[$offset + 2, $offset + 3];
                push @path_info, {
                    type => 'shortcut-cubic-bezier',
		    name => 'shorthand/smooth curveto',
                    position => $position,
                    control2 => \@control2,
                    end => \@end,
                    svg_key => $curve_type,
                };
            }
        }
        elsif (uc $curve_type eq 'L') {
            my $expect_numbers = 2;
	    # Maintain this check here, even though it's duplicated
	    # inside build_lineto, because it's specific to the lineto
            if (@numbers % $expect_numbers != 0) {
                croak "Odd number of values for an L command " .
                    scalar (@numbers) . " in '$path'";
            }
            my $position = position_type ($curve_type);
	    push @path_info, build_lineto ($position, @numbers);
        }
        elsif (uc $curve_type eq 'Z') {
            if (@numbers > 0) {
                croak "Wrong number of values for a Z command " .
                    scalar @numbers . " in '$path'";
            }
            my $position = position_type ($curve_type);
	    push @path_info, {
		type => 'closepath',
		name => 'closepath',
		position => $position,
		svg_key => $curve_type,
            }
        }
        elsif (uc $curve_type eq 'Q') {
            my $expect_numbers = 4;
            if (@numbers % $expect_numbers != 0) {
                croak "Wrong number of values for a Q command " .
                    scalar @numbers . " in '$path'";
            }
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers / $expect_numbers; $i++) {
                my $o = $expect_numbers * $i;
                push @path_info, {
                    type => 'quadratic-bezier',
		    name => 'quadratic Bézier curveto',
                    position => $position,
                    control => [@numbers[$o, $o + 1]],
                    end => [@numbers[$o + 2, $o + 3]],
                    svg_key => $curve_type,
                }
            }
        }
        elsif (uc $curve_type eq 'T') {
            my $expect_numbers = 2;
            if (@numbers % $expect_numbers != 0) {
                croak "$me: Wrong number of values for an T command " .
                    scalar @numbers . " in '$path'";
            }
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers / $expect_numbers; $i++) {
                my $o = $expect_numbers * $i;
                push @path_info, {
                    type => 'shortcut-quadratic-bezier',
		    name => 'Shorthand/smooth quadratic Bézier curveto',
                    position => $position,
                    end => [@numbers[$o, $o + 1]],
                    svg_key => $curve_type,
                }
            }
        }
        elsif (uc $curve_type eq 'H') {
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers; $i++) {
                push @path_info, {
                    type => 'horizontal-line-to',
		    name => 'horizontal lineto',
                    position => $position,
                    x => $numbers[$i],
                    svg_key => $curve_type,
                };
            }
        }
        elsif (uc $curve_type eq 'V') {
            my $position = position_type ($curve_type);
            for (my $i = 0; $i < @numbers; $i++) {
                push @path_info, {
                    type => 'vertical-line-to',
		    name => 'vertical lineto',
                    position => $position,
                    y => $numbers[$i],
                    svg_key => $curve_type,
                };
            }
        }
        elsif (uc $curve_type eq 'A') {
            my $position = position_type ($curve_type);
            my $expect_numbers = 7;
	    if (@numbers % $expect_numbers != 0) {
		croak "$me: Need 7 parameters for arc";
	    }
            for (my $i = 0; $i < @numbers / $expect_numbers; $i++) {
                my $o = $expect_numbers * $i;
                my %arc;
                $arc{svg_key} = $curve_type;
                $arc{type} = 'arc';
                $arc{name} = 'elliptical arc';
                $arc{position} = $position;
                @arc{@arc_fields} = @numbers[$o .. $o + 6];
                push @path_info, \%arc;
            }
        }
	elsif (uc $curve_type eq 'M') {
            my $expect_numbers = 2;
	    my $position = position_type ($curve_type);
	    if (@numbers < $expect_numbers) {
		croak "$me: Need at least $expect_numbers numbers for move to";
	    }
            if (@numbers % $expect_numbers != 0) {
                croak "$me: Odd number of values for an M command " .
                    scalar (@numbers) . " in '$path'";
            }
	    push @path_info, {
		type => 'moveto',
		name => 'moveto',
		position => $position,
		point => [@numbers[0,1]],
		svg_key => $curve_type,
	    };
	    # M can be followed by implicit line-to commands, so
	    # consume these.
	    if (@numbers > $expect_numbers) {
	    	my @implicit_lineto = splice @numbers, $expect_numbers;
		push @path_info, build_lineto ($position, @implicit_lineto);
	    }
	}
        else {
            croak "I don't know what to do with a curve type '$curve_type'";
        }
    }

    # Now sort it out if the user wants to get rid of the absolute
    # paths etc. 
    
    my $absolute = $options_ref->{absolute};
    my $no_shortcuts = $options_ref->{no_shortcuts};
    if ($absolute) {
        if ($verbose) {
            print "Making all coordinates absolute.\n";
        }
        my @abs_pos = (0, 0);
        my @start_drawing;
        my $previous;
        my $begin_drawing = 1;  ##This will get updated after
        for my $element (@path_info) {
            if ($element->{type} eq 'moveto') {
                if ($element->{position} eq 'relative') {
                    my $ip = $options_ref->{initial_position};
                    if ($ip) {
                        if (ref $ip ne 'ARRAY' ||
                            scalar @$ip != 2) {
                            croak "$me: The initial position supplied doesn't look like a pair of coordinates";
                        }
                        add_coords ($element->{point}, $ip);
                    }
                    else {
                        add_coords ($element->{point}, \@abs_pos);
                    }
                }
                @abs_pos = @{$element->{point}};
            }
            elsif ($element->{type} eq 'line-to') {
                if ($element->{position} eq 'relative') {
                    add_coords ($element->{point}, \@abs_pos);
                }
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                @abs_pos = @{$element->{point}};
            }
            elsif ($element->{type} eq 'horizontal-line-to') {
                if ($element->{position} eq 'relative') {
		    $element->{x} += $abs_pos[0];
                }
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                $abs_pos[0] = $element->{x};
            }
            elsif ($element->{type} eq 'vertical-line-to') {
                if ($element->{position} eq 'relative') {
		    $element->{y} += $abs_pos[1];
                }
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                $abs_pos[1] = $element->{y};
            }
            elsif ($element->{type} eq 'cubic-bezier') {
                if ($element->{position} eq 'relative') {
                    add_coords ($element->{control1}, \@abs_pos);
                    add_coords ($element->{control2}, \@abs_pos);
                    add_coords ($element->{end},      \@abs_pos);
                }
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                @abs_pos = @{$element->{end}};
            }
            elsif ($element->{type} eq 'shortcut-cubic-bezier') {
                if ($element->{position} eq 'relative') {
                    add_coords ($element->{control2}, \@abs_pos);
                    add_coords ($element->{end},      \@abs_pos);
                }
                if ($no_shortcuts) {
                    if (!$previous) {
                        die "No previous element";
                    }
                    if ($previous->{type} ne 'cubic-bezier') {
                        die "Bad previous element type $previous->{type}";
                    }
                    $element->{type} = 'cubic-bezier';
                    $element->{svg_key} = 'C';
                    $element->{control1} = [
                        2 * $abs_pos[0] - $previous->{control2}->[0],
                        2 * $abs_pos[1] - $previous->{control2}->[1],
                    ];
                }
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                @abs_pos = @{$element->{end}};
            }
	    elsif ($element->{type} eq 'arc') {

		# Untested.
#		print "before: @abs_pos\n";

                if ($element->{position} eq 'relative') {
		    $element->{x} += $abs_pos[0];
		    $element->{y} += $abs_pos[1];
		}
                if ($begin_drawing) {
		    if ($verbose) {
			printf "Beginning drawing at [%.4f, %.4f]\n", @abs_pos;
		    }
		    $begin_drawing = 0;
		    @start_drawing = @abs_pos;
                }
                @abs_pos = ($element->{x}, $element->{y});
		#		print "after: @abs_pos\n";
	    }
            elsif ($element->{type} eq 'closepath') {
                # Bookkeeping
                if ($verbose) {
		    printf "Closing drawing shape to [%.4f, %.4f]\n", @start_drawing;
                }
                @abs_pos = @start_drawing;
                $begin_drawing = 1;
            }
            $element->{position} = 'absolute';
	    if (! $element->{svg_key}) {
		die "No SVG key";
	    }
            $element->{svg_key} = uc $element->{svg_key};
            $previous = $element;
        }
    }
    return @path_info;
}

# Given a current position and an array of coordinates, use the
# coordinates to build up line-to elements until the coordinates are
# exhausted. Before entering this, it should have been checked that
# there is an even number of coordinates.

sub build_lineto
{
    my ($position, @coords) = @_;
    my @path_info = ();
    my $n_coords = scalar (@coords);
    if ($n_coords % 2 != 0) {
	# This trap should never be reached, since we should always
	# check before entering this routine. However, we keep it for
	# safety.
	croak "Odd number of coordinates in lineto";
    }
    while (my ($x, $y) = splice @coords, 0, 2) {
	push @path_info, {
	    type => 'line-to',
	    name => 'lineto',
	    position => $position,
	    point => [$x, $y],
	    end => [$x, $y],
	    svg_key => ($position eq 'absolute' ? 'L' : 'l'),
	};
    }
    return @path_info;
}

1;

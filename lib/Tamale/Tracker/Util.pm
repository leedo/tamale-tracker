package Tamale::Tracker::Util;

use List::Util qw/min/;

use base 'Exporter';
our @EXPORT_OK = qw/levenshtein_distance clean_name/;

sub levenshtein_distance {
  my ($a, $b) = @_;

  my @s = split '', $a;
  my @t = split '', $b;
  my $m = scalar @s - 1;
  my $n = scalar @t - 1;
  my @d;

  
  $d[$_][0] = $_ for 0 .. $m;
  $d[0][$_] = $_ for 0 .. $n;

  for my $j (1 .. $n) {
    for my $i (1 .. $m) {
      if ($s[$i] eq $t[$j]) {
        $d[$i][$j] = $d[$i - 1][$j - 1];
      } else {
        $d[$i][$j] = min (
                       $d[$i - 1][$j]     + 1,  # deletion
                       $d[$i][$j - 1]     + 1,  # insertion
                       $d[$i - 1][$j - 1] + 1,  # substitution
                     );
      }
    }
  }

  return $d[$m][$n];
}

sub clean_name {
  my $bar = shift;

  # strip whitespace
  $bar =~ s/^\s+//;
  $bar =~ s/\s+$//;

  # strip of time qualifiers
  $bar =~ s/\b(?:right now|again|now|during|a while ago)\b.*//i;

  # strip off neighborhood info
  $bar =~ s/\b(?:in|at|on)\b.*//i;

  # strip off any stupid extra info
  $bar =~ s/\b(?:and )?(?:(?:he|hes|he's) )?(?:says|loves|heading|headed|heading|for|got|with|http)\b.*//i;

  # strip off any cheerfulness
  $bar =~ s/\b(?:yay|and i(?:'m)?)\b.*//i;

  # strip whitespace again
  $bar =~ s/^\s+//;
  $bar =~ s/\s+$//;

  return $bar;
}


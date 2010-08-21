package Tamale::Tracker;

use Any::Moose;
use Net::Twitter::Lite;
use List::Util qw/min/;
use Path::Class;
use Date::Parse;
use JSON;
use DBI;

has datadir => (
  is => 'ro',
  required => 1,
);

has twitter => (
  is => 'ro',
  lazy => 1,
  default => sub {
    die "need username and password"
      unless $_[0]->username and $_[0]->password;

    Net::Twitter::Lite->new(
      username => $_[0]->username,
      password => $_[0]->password,
    );
  }
);

has username => (is => 'ro');
has password => (is => 'ro');

has userid => (
  is => 'ro',
  default => "tamaletracker",
);

has dbfile => (
  is => 'ro',
  lazy => 1,
  default => sub {
    $_[0]->datadir."/tweets.db",
  }
);

has dbh => (
  is => 'ro',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $create = ! -e $self->dbfile;

    my $dbh = DBI->connect("dbi:SQLite:dbname=".$self->dbfile,"","");

    if ($create) {
      $dbh->do("CREATE TABLE updates (date VARCHAR(32), id INT, body TEXT)");
    }

    return $dbh;
  }
);

has cache => (
  is => 'rw',
  default => sub {{}},
);

has insert_sth => (
  is => 'ro',
  lazy => 1,
  default => sub {
    $_[0]->dbh->prepare("INSERT INTO updates (id, body, date) VALUES (?, ?, ?)");
  }
);

has oldest => (
  is => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $row = $self->dbh->selectrow_arrayref("SELECT id FROM updates ORDER BY id ASC");  
    return ($row ? $row->[0] : ());
  }
);

has newest => (
  is => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $row = $self->dbh->selectrow_arrayref("SELECT id FROM updates ORDER BY id DESC");  
    return ($row ? $row->[0] : ());
  }
);

has request_delay => (
  is => 'ro',
  default => 2,
);

has bars => (
  is => 'ro',
  lazy => 1,
  isa => 'ArrayRef',
  auto_deref => 1,
  default => sub {
    my $file = $_[0]->datadir."/bars.json";
    die "no bars.json file... oh god!\n" unless -e $file;

    from_json file($file)->slurp, {utf8 => 1};
  }
);

sub update_boundaries {
  my ($self, $id) = @_;
  if (!$self->oldest or $id < $self->oldest) {
    $self->oldest($id);
  }
  if (!$self->newest or $id > $self->newest) {
    $self->newest($id);
  }
}

sub max_id {
  my $self = shift;
  $self->oldest ? $self->oldest - 1 : ();
}

sub get_missing_tweets {
  my $self = shift;

  $self->get_newer_tweets;
  $self->get_older_tweets;
}

sub get_newer_tweets {
  my $self = shift;
  print STDERR "looking for older tweets\n";
  while (my @tweets = $self->download_tweets(max_id => $self->max_id)) {
    for my $status (@tweets) {
      $self->add_tweet($status->{id}, $status->{text}, $status->{created_at});
    }
    sleep $self->request_delay;
  }
}

sub get_older_tweets {
  my $self = shift;
  print STDERR "looking for newer tweets\n";
  while (my @tweets = $self->download_tweets(since_id => $self->newest)) {
    for my $status (@tweets) {
      $self->add_tweet($status->{id}, $status->{text}, $status->{created_at});
    }
    sleep $self->request_delay;
  }
}

sub add_tweet {
  my ($self, $id, $text, $created) = @_;
  $self->insert_sth->execute($id, $text, $created);
  $self->update_boundaries($id);
}

sub clean_name {
  my ($self, $bar) = @_;

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

sub levenshtein_distance {
  my ($self, $a, $b) = @_;

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

sub closest_bar {
  my ($self, $guess) = @_;

  return $self->cache->{$guess} if $self->cache->{$guess};

  my $best_dist = 1000;
  my $best_bar;

  for my $bar ($self->bars) {
    my @names = ($bar->{name}, @{$bar->{alias}});
    for my $name (@names) {
      my $dist = $self->levenshtein_distance($guess, $name);
      if ($dist < $best_dist) {
        $best_dist = $dist;
        $best_bar = $bar->{name};
      }
    }
  }

  $self->cache->{$guess} = $best_bar;
  return $best_bar;
}

sub download_tweets {
  my ($self, %filter) = @_;
  $filter{screen_name} = $self->userid;

  # remove filters that are set to undef
  %filter = map {$_ => $filter{$_}} grep {$filter{$_}} keys %filter;

  # 3 retries and then give up
  for (0 .. 3) { 
    my $statuses = eval {$self->twitter->user_timeline(\%filter)};
    if (!$@) {
      return @$statuses;
    }
    warn "retrying: $@\n";
  }

  die "could not connect to twitter\n";
}

sub matching_tweets {
  my $self = shift;

  my $sth = $self->dbh->prepare("SELECT * FROM updates ORDER BY id DESC");
  $sth->execute;

  my @matches;

  while(my $row = $sth->fetchrow_arrayref) {
    if ($row->[2] =~ /\b(?:at|left|into|leaving) ([a-z][^~\.!@;,1-9()\-]+)/i) {
      my $bar = lc $1;

      # skip if it ends with a ? or is begging
      next if $bar =~ /\?/;
      next if $bar =~ /\b(?:wants?|please|por favor)\b/;

      $bar = $self->clean_name($bar);

      if ($bar = $self->closest_bar($bar)) {
        push @matches, {
          location => $bar,
          text     => $row->[2],
          date     => str2time($row->[0]),
          id       => $row->[1],
        };
      }
    }
  }

  return \@matches;
}

1;

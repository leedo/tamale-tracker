package Tamale::Tracker;

use strict;
use warnings;

use Any::Moose;
use Tamale::Tracker::Util qw/levenshtein_distance clean_name/;
use Net::Twitter::Lite;
use Path::Class;
use Date::Parse;
use Storable qw/freeze thaw/;
use DateTime;
use JSON;
use DBI;

my $debug = 0;

sub log_debug {
  return unless $debug;
  print STDERR "$_\n" for @_;
}

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

has debug => (
  is => 'ro',
  default => 0,
);

sub BUILD {
  my $self = shift;
  $debug = 1 if $self->debug;
}

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
      $dbh->do("CREATE TABLE updates (date VARCHAR(32), id INT, body TEXT, is_real_time BOOLEAN)");
    }

    return $dbh;
  }
);

has cache => (
  is => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    my $file = file($self->datadir."/tmp/match-cache");
    if (-e $file) {
      my $cache = eval { thaw scalar $file->slurp };
      return $cache unless $@;
      warn "could not load cache, continuing without it\n";
    }
    return {}
  }
);

sub write_cache {
  my $self = shift;
  my $dir = dir($self->datadir."/tmp");
  $dir->mkpath;
  my $fh = $dir->file("match-cache")->openw;
  print $fh freeze $self->cache;
}

sub DESTROY {
  my $self = shift;
  $self->write_cache if $self->{cache};
}

has insert_sth => (
  is => 'ro',
  lazy => 1,
  default => sub {
    $_[0]->dbh->prepare("INSERT INTO updates (id, body, date, is_real_time) VALUES (?, ?, ?, ?)");
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
  default => 3,
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

sub get_older_tweets {
  my $self = shift;
  log_debug("looking for older tweets");
  while (my @tweets = $self->download_tweets(max_id => $self->max_id)) {
    log_debug(" => got ".scalar @tweets." new tweets");
    for my $status (@tweets) {
      my $orig = $self->find_original_tweet($status);
      if ($orig) {
        log_debug("  => found original tweet for: \"$status->{text}\"");
        $status->{created_at} = $orig->{created_at};
      } else {
        log_debug("  => could not find original tweet for: \"$status->{text}\"");
      }
      $self->add_tweet($status->{id}, $status->{text}, $status->{created_at}, !!$orig);
    }
    sleep $self->request_delay;
  }
}

sub get_newer_tweets {
  my $self = shift;
  log_debug("looking for newer tweets");
  while (my @tweets = $self->download_tweets(since_id => $self->newest)) {
    log_debug(" => got ".scalar @tweets." new tweets");
    for my $status (@tweets) {
      my $orig = $self->find_original_tweet($status);
      if ($orig) {
        log_debug("  => found original tweet for: \"$status->{text}\"");
        $status->{created_at} = $orig->{created_at};
      } else {
        log_debug("  => could not find original tweet for: \"$status->{text}\"");
      }
      $self->add_tweet($status->{id}, $status->{text}, $status->{created_at}, !!$orig);
    }
    sleep $self->request_delay;
  }
}


sub add_tweet {
  my ($self, $id, $text, $created, $is_orig) = @_;
  $self->insert_sth->execute($id, $text, $created, $is_orig);
  $self->update_boundaries($id);
}

sub find_original_tweet {
  my ($self, $retweet) = @_;

  my $max_id = $retweet->{id};
  my $userid = $self->userid;
  my $re = qr/\@$userid/i;
  my ($orig_tweeter) = ($retweet->{text} =~ /~\@(\S+)\b/);

  return () unless $orig_tweeter;

  while (my @tweets = $self->download_tweets(max_id => $max_id, screen_name => $orig_tweeter)) {
    for my $tweet (@tweets) {
      if ($tweet->{text} =~ $re) {
        return $tweet;
      }
      $max_id = $tweet->{id} if $tweet->{id} < $max_id;
    }
    sleep $self->request_delay;
  }

  return ();
}

sub closest_bar {
  my ($self, $guess) = @_;

  return $self->cache->{$guess} if $self->cache->{$guess};

  my $best_dist = 1000;
  my $best_bar;

  for my $bar ($self->bars) {
    my @names = ($bar->{name}, @{$bar->{alias}});
    for my $name (@names) {
      my $dist = levenshtein_distance($guess, $name);
      if ($dist < $best_dist) {
        $best_dist = $dist;
        $best_bar = $bar;
      }
    }
  }

  $self->cache->{$guess} = $best_bar;
  return $best_bar;
}

sub download_tweets {
  my ($self, %filter) = @_;
  $filter{screen_name} = $self->userid
    unless $filter{screen_name};

  # remove filters that are set to undef
  %filter = map {$_ => $filter{$_}}
            grep {$filter{$_}}
            keys %filter;

  # 3 retries and then give up
  for (0 .. 3) { 
    my $statuses = eval {$self->twitter->user_timeline(\%filter)};
    if (!$@) {
      return @$statuses;
    }
    die $@ if $@ =~ /rate limit exceeded/i;
    return () if $@ =~ /not authorized/i;
    warn "retrying: $@\n";
    sleep $self->request_delay;
  }

  die "could not connect to twitter\n";
}

sub matching_tweets {
  my $self = shift;

  my $sth = $self->dbh->prepare("SELECT * FROM updates ORDER BY id DESC");
  $sth->execute;

  my @matches;

  while(my $row = $sth->fetchrow_arrayref) {
    if ($row->[2] =~ /\b(?:at|left|into|leaving|\@) ([a-z][^~\.!@;,1-9()\-]+)/i) {
      my $bar = lc $1;

      # skip if it ends with a ? or is begging
      next if $bar =~ /\?/;
      next if $bar =~ /\b(?:wants?|please|por favor)\b/;

      $bar = clean_name($bar);

      if ($bar = $self->closest_bar($bar)) {

        my $color = "unknown";
        if ($row->[2] =~ /\b(red|blue)\b/i) {
          $color = lc $1;
        }

        push @matches, {
          bar      => $bar,
          color    => $color,
          text     => $row->[2],
          date     => str2time($row->[0]),
          id       => $row->[1],
        };
      }
    }
  }

  return \@matches;
}

sub matching_tweets_by_day {
  my $self = shift;
  my $matches = $self->matching_tweets;

  my %days;
  my $one_day = DateTime::Duration->new(days => 1);

  for my $match (@$matches) {
    my $date = DateTime->from_epoch(epoch => $match->{date});

    # count anything before 5AM as the previous day...
    if ($date->hour < 5) {
      $date -= $one_day;
    }

# disabled for now
#
    # anything after 5AM and before 5PM is useless
#    elsif ($date->hour < 17) {
#      next;
#    }
#

    $date->truncate(to => 'day');
    
    $match->{evening_of} = $date->ymd;
    push @{$days{$date->ymd}}, $match;
  }

  return [map {$days{$_}} sort keys %days];
}

1;

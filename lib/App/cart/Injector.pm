package App::cart::Injector;

use strict;
use warnings;

use DBI;
use Net::Twitter;
use AnyEvent::DateTime::Cron;

use App::cart::Buffer;

sub new {
    my ($class, $conf) = @_;

    my @alltimes  = @{ $conf->{publishtimes} };
    my @todotimes = @{ $conf->{publishtimes} };

    my $self = bless {
        buffer    => App::cart::Buffer->new($conf),
        alltimes  => \@alltimes,
        todotimes => \@todotimes,
        maxrate   => $conf->{maxrate},
        keywords  => $conf->{keywords},
    }, $class;
    
    # Get an authenticated Twitter client
    $self->{nt} = Net::Twitter->new(
        traits => [qw/OAuth API::REST/],
        %{ $conf->{oauth} }
    );

    # Handler to execute on publish times
    my $handler = sub {
        print STDERR "Executing scheduled job!\n";
        # Cancel the current publishing loop
        undef $self->{publisher};
        $self->reeschedule;
    };

    # Configure cron
    $self->{cron} = AnyEvent::DateTime::Cron->new->add(
        map {
            my ($h, $m) = split /:/, $_;
            "$m $h * * *" => $handler;
        } @alltimes
    );

    return $self;
}

sub init {}

sub start {
    my $self = shift;
    $self->{cron}->start->recv;
}

sub reeschedule {
    my ($self) = @_;

    my $count  = $self->{buffer}->count;
    print STDERR "There are $count tweets to publish\n";

    my $tweets = $count / scalar @{ $self->{todotimes} };
    return unless $tweets;
    $tweets = 1 if $tweets < 1;
    $self->{tweets_left} = $tweets;
    print "Will publish $tweets tweets until next publish time\n";

    my ($h, $m) = split(/:/, shift(@{ $self->{todotimes} }));
    my $dtnow = DateTime->today;
    $dtnow->set_hour($h);
    $dtnow->set_minute($m);

    my $dtnext  = DateTime->today;
    unless (scalar @{ $self->{todotimes} }) {
        # no more jobs today, so restoring the "todo" list
        $self->{todotimes} = [ @{ $self->{alltimes} } ];

        # and getting a DateTime object for tomorrow
        $dtnext->add(days => 1);
    }

    my ($nexth, $nextm) = split(/:/, $self->{todotimes}->[0]);
    $dtnext->set_hour($nexth);
    $dtnext->set_minute($nextm);

    my $dur = $dtnext->subtract_datetime($dtnow);
    my $sec = $dur->in_units('minutes') * 60;

    print STDERR "$sec secs until next publish time\n";

    my $maxrate       = $self->{maxrate} * 60;
    my $calc_interval = $sec / $tweets;
    my $interval = $calc_interval > $maxrate ? $calc_interval : $maxrate;

    print STDERR "Publishing with an interval of $interval secs\n";

    $self->{publisher} = AnyEvent->timer(
        after    => 0,
        interval => $interval,
        cb       => sub {
            $self->tweet;
            $self->{tweets_left} = $self->{tweets_left} - 1;
            undef $self->{publisher} unless $self->{tweets_left};
        }
    );
};

sub tweet {
    my ($self) = @_;

    my $tweet = $self->{buffer}->bshift;
    if (defined $tweet and defined $tweet->{data}) {
        my $text = $tweet->{data};

        # Delete our keywords
        my @kw   = @{ $self->{keywords} };
        foreach (@kw) {
            $text =~ s/$_//;
        }
        eval { $self->{nt}->update($text); };
        if ($@) { warn "Couldn't update: $@\n"; }
        else    { print STDERR "Just tweeted: $text\n"; }

    } else {
        # Stop publication
        undef $self->{publisher};
        print STDERR "Publication stopped: no more buffered tweets\n";
    }
}

1;

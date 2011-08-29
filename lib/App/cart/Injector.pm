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
    }, $class;
    
    # Get an authenticated Twitter client
    $self->{nt} = Net::Twitter->new(
        traits => [qw/OAuth API::REST/],
        %{ $conf->{oauth} }
    );

    # Handler to execute on publish times
    my $handler = sub {
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

    my $tweets = $self->{buffer}->count / scalar @{ $self->{todotimes} };

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
    my $min = $dur->in_units('seconds');

    my $calc_interval = $min / $tweets;
    my $interval = $calc_interval > $self->{maxrate}
        ? $calc_interval
        : $self->{maxrate};

    # Store the interval to report statistics
    $self->{current_rate} = $interval;

    $self->{publisher} = AnyEvent->timer(
        after    => 0,
        interval => $interval,
        cb       => sub { $self->tweet; }
    );
};

sub tweet {
    my ($self) = @_;

    my $tweet = $self->{buffer}->bshift;
    if ($tweet) {
        my $text  = $tweet->{data};
        $text =~ s/\#cp//;
        my $user  = $tweet->{user};

        $self->{nt}->update(sprintf("RT %s: %s", $user, $text));
    }
}

1;

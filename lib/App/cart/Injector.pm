package App::cart::Injector;

use strict;
use warnings;

use Try::Tiny;
use Log::Any '$log';

use Net::Twitter;
use AnyEvent::DateTime::Cron;

use App::cart::Buffer;

my %tweet_mode = (
    new_tweet => 'tweet',
    retweet   => 'retweet',
);

sub new {
    my ($class, $conf) = @_;

    Log::Any->set_adapter('+App::cart::Logger', level => $conf->{loglevel});

    my @alltimes  = @{ $conf->{publishtimes} };
    my @todotimes = @{ $conf->{publishtimes} };

    my $self = bless {
        buffer        => App::cart::Buffer->new($conf),
        alltimes      => \@alltimes,
        todotimes     => \@todotimes,
        maxrate       => $conf->{maxrate},
        keywords      => $conf->{keywords},
        delete_kw     => $conf->{delete_keywords},
        tweet_handler => $tweet_mode{$conf->{tweet_mode}},
    }, $class;

    # Get an authenticated Twitter client
    $self->{nt} = Net::Twitter->new(
        traits => [qw/API::RESTv1_1/],
        %{ $conf->{oauth} }
    );

    # Handler to execute on publish times
    my $handler = sub {
        $log->debug('Executing scheduled job!');
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
    $log->debug("There are $count tweets to publish");

    my $tweets = $count / scalar @{ $self->{todotimes} };
    return unless $tweets;
    $tweets = 1 if $tweets < 1;
    $self->{tweets_left} = $tweets;
    $log->debug("Will publish $tweets tweets until next publish time");

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

    $log->debug("$sec secs until next publish time");

    my $maxrate       = $self->{maxrate} * 60;
    my $calc_interval = $sec / $tweets;
    my $interval = $calc_interval > $maxrate ? $calc_interval : $maxrate;

    $log->debug("Publishing with an interval of $interval secs");

    $self->{publisher} = AnyEvent->timer(
        after    => 0,
        interval => $interval,
        cb       => sub {
            my $handler = $self->{tweet_handler};

            my $tweet = $self->{buffer}->bshift;
            if (defined $tweet) {
                $self->$handler($tweet)
            } else {
                # Stop publication
                undef $self->{publisher};
                $log->debug('Publication stopped: no more buffered tweets');
            }

            $self->{tweets_left} = $self->{tweets_left} - 1;
            undef $self->{publisher} unless $self->{tweets_left};
        }
    );
};

sub tweet {
    my ($self, $tweet) = @_;

    return unless $tweet->{data};
    my $text = $tweet->{data};

    # Delete keywords if needed
    if ($self->{delete_kw}) {
        foreach (@{ $self->{keywords} }) {
            $text =~ s/$_//;
        }
    }

    try {
        $self->{nt}->update($text);
        $log->info("Just tweeted: $text");
    } catch {
        $log->error("Couldn't update: $_");
    };

}

sub retweet {
    my ($self, $tweet) = @_;
    return unless $tweet->{id};

    try {
        $self->{nt}->retweet($tweet->{id});
        $log->info("Just retweeted: " . $tweet->{data});
    } catch {
        $log->error("Couldn't retweet: $_");
    };
}

1;

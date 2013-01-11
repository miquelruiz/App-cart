package App::cart::Collector;

use strict;
use warnings;

use Try::Tiny;
use Log::Any '$log';

use Net::Twitter;
use AnyEvent::Twitter::Stream;

use App::cart::Buffer;

sub new {
    my ($class, $conf, $test_conn_cv, $test_tweet_cv) = @_;

    Log::Any->set_adapter('+App::cart::Logger', level => $conf->{loglevel});
    if ($log->is_debug) {
        eval 'use Data::Dumper';
    }

    my $self = bless {
        buffer   => App::cart::Buffer->new($conf),
        keywords => $conf->{keywords},
    }, $class;

    my $filter = $self->filter($conf);
    $self->{follow} = $filter->{follow};

    $self->{stream} = AnyEvent::Twitter::Stream->new(
        consumer_key    => $conf->{oauth}->{consumer_key},
        consumer_secret => $conf->{oauth}->{consumer_secret},
        token           => $conf->{oauth}->{access_token},
        token_secret    => $conf->{oauth}->{access_token_secret},
        on_connect      => sub {
            $log->debug("Stream connected!");
            $test_conn_cv->send if defined $test_conn_cv;
        },
        on_tweet        => sub {
            $self->on_tweet(shift);
            $test_tweet_cv->end if defined $test_tweet_cv;
        },
        on_error        => sub {
            $log->critical("Got error: " . join("|", @_));
            die;
        },
        %$filter,
    );

    return $self;
}

sub init {
    my ($self) = @_;
    $self->{buffer}->init;
}

sub filter {
    my ($self, $conf) = @_;

    # Get user id's to follow from config
    my @ids;
    push @ids, @{$conf->{user_ids}} if ($conf->{user_ids});

    # Resolve the user id's from usernames given in config
    if ($conf->{user_names}) {
        push @ids, grep { defined }
            map { $self->resolve_user_id($_) } @{$conf->{user_names}};
    }

    my $filter = { method => 'filter' };
    $filter->{follow} = join(',', @ids)   if @ids;
    $log->debug("Filter: " . Dumper($filter->{follow}))
        if $log->is_debug;

    return $filter;
}

# Event Handlers
sub on_tweet {
    my ($self, $tweet) = @_;

    $log->debug('got tweet ' . $self->{buffer}->count);
    if (defined $tweet->{text}) {
        my $user = $tweet->{user}->{screen_name};
        my $text = $tweet->{text};
        $log->info("$user: $text");

        if ($self->is_valid($tweet)) {
            $self->{buffer}->bpush($tweet);
            $log->info('Buffered!');
        } else {
            $log->info('Not buffered');
        }
    }
}

sub is_valid {
    my ($self, $tweet) = @_;

    # This is one of our users' tweet. Check if it's a RT
    return 0 if $tweet->{retweeted};

    # Check if this is one of our user's tweet
    my $user = $tweet->{user}->{id};
    return 0 unless $self->{follow} =~ /$user/;

    # Search for at least one of our keywords
    return 1 unless ($self->{keywords});

    my @kw = @{ $self->{keywords} };
    foreach (@kw) {
        if ($tweet->{text} =~ /(?:\s|^)$_(?:\s|$)/) {
            $log->debug("Got a match with $_");
            return 1;
        }
    }

    return 0;
}

sub resolve_user_id {
    my ($self, $name) = @_;

    $log->debug("Resolving user_id for $name");
    my $nt  = Net::Twitter->new( traits => ['API::REST'] );

    my $id = $self->{buffer}->get_user_id($name);
    unless (defined $id) {
        $log->debug("Requesting ID for $name");
        try {
            $id = $nt->show_user({screen_name => $name})->{id};
            $self->{buffer}->save_user_id($name, $id);
        } catch {
            $log->info("'$name' couldn't be resolved: $_");
        };
    } else {
        $log->debug("ID for $name already resolved: $id :)");
    }

    return $id;
}

1;

package App::cart::Collector;

use strict;
use warnings;

use Net::Twitter;
use AnyEvent::Twitter::Stream;

use App::cart::Buffer;

sub new {
    my ($class, $conf) = @_;

    my $self = bless {
        buffer => App::cart::Buffer->new($conf),
    }, $class;

    $self->{stream} = AnyEvent::Twitter::Stream->new(
        consumer_key    => $conf->{oauth}->{consumer_key},
        consumer_secret => $conf->{oauth}->{consumer_secret},
        token           => $conf->{oauth}->{access_token},
        token_secret    => $conf->{oauth}->{access_token_secret},
        on_tweet        => sub { $self->on_tweet(shift); },
        %{ $self->filter($conf) },
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
        my $nt  = Net::Twitter->new( traits => ['API::REST'] );
        push @ids, map {
            $nt->show_user({screen_name => $_})->{id}
        } @{$conf->{user_names}};
    }

    # Get keywords to monitor
    my @track;
    @track = @{ $conf->{keywords} } if $conf->{keywords};

    my $filter = { method => 'filter' };
    $filter->{follow} = join(',', @ids)   if @ids;
    $filter->{track}  = join(',', @track) if @track;

    return $filter;
}

# Event Handlers
sub on_tweet {
    my ($self, $tweet) = @_;

    print STDERR "got tweet " . $self->{buffer}->count . "\n";
    $self->{buffer}->bpush($tweet);
}

1;

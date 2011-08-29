use strict;
use warnings;
package App::cart;

use autodie;

our $VERSION = '0.001';

use AnyEvent;
use YAML::Any;
use Getopt::Long ();

use App::cart::Injector;
use App::cart::Collector;

sub new {
    my $class = shift;

    my $self = bless {
        home     => "$ENV{HOME}/.cart",
        conffile => 'cart.yml',
        pidfile  => 'cart.pid',
    }, $class;

    return $self;
}

sub config {
    my $self = shift;

    Getopt::Long::GetOptions(
        'h|home=s'     => \$self->{home},
        'c|conffile=s' => \$self->{conffile},
        'p|pidfile=s'  => \$self->{pidfile},
    );

    if (!-d $self->{home}) {
        die <<NOHOME;
$self->{home} is not a valid home directory.
Run 'cart --home $self->{home} init' first.
NOHOME
    }

    if (!-f "$self->{home}/$self->{conffile}") {
        die <<NOCONF
Can't read conffile $self->{conffile}.
Run 'cart --home $self->{home} init' first.
NOCONF
    }

    $self->{config}   = YAML::Any::LoadFile("$self->{home}/$self->{conffile}");
    $self->{config}->{home} = $self->{home};

    $self->{injector}  = App::cart::Injector->new($self->{config});
    print "Got injector\n";
    $self->{collector} = App::cart::Collector->new($self->{config});
    print "Got collector\n";
    
}

sub run {
    my ($self) = @_;

    my $command  = shift @ARGV || 'start';
    my $function = "run_$command";
   
    $self->config if ($command ne 'init');

    if ($self->can($function)) {
        $self->$function(@ARGV);
    } else {
        die "Unknown command $command\n";
    }
}

sub run_start {
    my $self = shift;

    print "Starting...\n";
    $self->{injector}->start;
}

sub run_init {
    my $self = shift;
   
    unless (-d $self->{home}) {
        unless (mkdir $self->{home}) {
            die "Can't create home dir at $self->{home}\n";
        }
    }
    
    unless (-f "$self->{home}/$self->{conffile}") {
        
        require Term::ReadLine;
        require OAuth::Lite::Consumer;

        my $consumer_key    = 'AulRZomifEbzRAAqDg9CXg';
        my $consumer_secret = '5BsR6pEwBO31xWLMoi0FFn8o0oWyp4j997FPupqoP4';
        my $c = OAuth::Lite::Consumer->new(
            consumer_key        => $consumer_key,
            consumer_secret     => $consumer_secret,
            site                => 'http://api.twitter.com',
            request_token_path  => '/oauth/request_token',
            access_token_path   => '/oauth/access_token',
            authorize_path      => '/oauth/authorize',
        );

        my $req_token = $c->get_request_token(
            callback_url => 'oob',
        );

        print "You should visit: \n" . $c->url_to_authorize(
            token => $req_token,
        ) . "\n";

        my $term = Term::ReadLine->new('CaRT');
        my $pin  = $term->readline('PIN: ');

        my $access = $c->get_access_token(
            token    => $req_token,
            verifier => $pin,
        );

        my $access_token        = $access->token;
        my $access_token_secret = $access->secret;

        open CONFFILE, '>', "$self->{home}/$self->{conffile}";
        print CONFFILE <<CONF;
#--
oauth:
    consumer_key        : $consumer_key
    consumer_secret     : $consumer_secret
    access_token        : $access_token
    access_token_secret : $access_token_secret

database:
    dbfile: cart.db

users:
    - twitterapi

maxrate: 10

publishtimes:
    - '09:30'
    - '11:30'
    - '13:30'
    - '15:00'
    - '18:00'
    - '21:00'

CONF
        close CONFFILE;
    }

    $self->config;

    $self->{injector}->init;
    $self->{collector}->init;
}

1;

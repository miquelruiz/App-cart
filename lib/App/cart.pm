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

use Log::Any '$log';

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
        'l|loglevel=s' => \$self->{loglevel},
    ) or die "Error parsing options\n";

    my $command = $ARGV[0];

    if (!-d $self->{home} and $command ne 'init') {
        die <<NOHOME;
$self->{home} is not a valid home directory.
Run 'cart --home $self->{home} init' first.
NOHOME
    }

    if (!-f "$self->{home}/$self->{conffile}" and $command ne 'init') {
        die <<NOCONF
Can't read conffile $self->{conffile}.
Run 'cart --home $self->{home} init' first.
NOCONF
    }

    Log::Any->set_adapter('+App::cart::Logger', level => $self->{loglevel});

    $self->{config}   = YAML::Any::LoadFile("$self->{home}/$self->{conffile}");
    $self->{config}->{home}     = $self->{home};
    $self->{config}->{loglevel} = $self->{loglevel};

    if ($log->is_debug) {
        require Data::Dumper;
        $log->debug(Data::Dumper::Dumper($self));
    }
}

sub run {
    my ($self) = @_;

    $self->config;

    my $command  = shift @ARGV || 'start';
    my $function = "run_$command";

    if ($self->can($function)) {
        $self->$function(@ARGV);
    } else {
        die "Unknown command $command\n";
    }
}

sub run_start {
    my $self = shift;

    $log->info('Setting up injector');
    $self->{injector}  = App::cart::Injector->new($self->{config});

    $log->info('Setting up collector') if $log->is_alert;
    $self->{collector} = App::cart::Collector->new($self->{config});

    $log->info('Started');
    $self->{injector}->start;
}

sub run_init {
    my $self = shift;

    unless (-d $self->{home}) {
        unless (mkdir $self->{home}) {
            die "Can't create home dir at $self->{home}\n";
        }
    }

    $self->init_env() unless (-f "$self->{home}/$self->{conffile}");

    $self->config;

    $self->{injector}->init;
    $self->{collector}->init;
}

sub init_env {
    my $self = shift;

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

1;

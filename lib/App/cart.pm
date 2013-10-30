package App::cart;
# ABSTRACT: CAPSiDE ReTweeter

use strict;
use warnings;
use autodie;

use YAML::Any;
use Getopt::Long ();

use App::cart::Injector;
use App::cart::Collector;

use Log::Any '$log';

sub new {
    my ($class, %opts) = @_;

    # clean undefined options, which otherwise will clobber the defaults
    %opts = map { $_ => $opts{$_} } grep { defined $opts{$_} } keys %opts;

    my $self = bless {
        home     => "$ENV{HOME}/.cart",
        conffile => 'cart.yml',
        pidfile  => 'cart.pid',
        command  => 'start',
        %opts
    }, $class;

    return $self;
}

sub config {
    my $self = shift;
    my $command = $self->{command};

    if (    !-d $self->{home}
        and (not defined $command or $command ne 'init')) {
        die <<NOHOME;
$self->{home} is not a valid home directory.
Run 'cart --home $self->{home} init' first.
NOHOME
    }

    if (    !-f "$self->{home}/$self->{conffile}"
        and (not defined $command or $command ne 'init')) {
        die <<NOCONF
Can't read conffile $self->{conffile}.
Run 'cart --home $self->{home} init' first.
NOCONF
    }

    Log::Any->set_adapter('+App::cart::Logger', level => $self->{loglevel});

    if ($command ne 'init') {
        $self->{config}   = YAML::Any::LoadFile(
            "$self->{home}/$self->{conffile}"
        );
    }
    $self->{config}->{home}     = $self->{home};
    $self->{config}->{loglevel} = $self->{loglevel};

    if ($log->is_debug) {
        eval { use Data::Dumper; };
        $log->debug(Dumper($self));
    }
}

sub run {
    my $self = shift;

    $self->config;

    my $command  = $self->{command};
    my $function = "run_$command";

    if ($self->can($function)) {
        $log->debug("Calling $function");
        $self->$function(@_);
    } else {
        die "Unknown command $command\n";
    }
}

sub run_start {
    my $self = shift;

    $log->info('Setting up injector');
    $self->{injector}  = App::cart::Injector->new($self->{config});

    $log->info('Setting up collector');
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
        site                => 'https://api.twitter.com',
        request_token_path  => '/oauth/request_token',
        access_token_path   => '/oauth/access_token',
        authorize_path      => '/oauth/authorize',
    );

    my $req_token = $c->get_request_token(
        callback_url => 'oob',
    );
    $log->debug("Got request token");

    my $access_token        = $ENV{CART_ACCESS_TOKEN} || '';
    my $access_token_secret = $ENV{CART_ACCESS_TOKEN_SECRET} || '';


    if (not defined $ENV{CART_TEST_INIT}) {
        print "You should visit the following URL: \n" . $c->url_to_authorize(
            token => $req_token,
        ) . "\nAnd write here the PIN you'll find there\n";

        my $term = Term::ReadLine->new('CaRT');
        my $pin  = $term->readline('PIN: ');

        my $access = $c->get_access_token(
            token    => $req_token,
            verifier => $pin,
        );
        $access_token        = $access->token;
        $access_token_secret = $access->secret;
    }

    $log->debug(
        "Got credentials!\n\tAccess: $access_token\n" .
        "\tSecret: $access_token_secret"
    );

    my $user = $ENV{CART_TEST_USERNAME} || 'twitterapi';

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

user_names:
    - $user

maxrate: 10

publishtimes:
    - '09:30'
    - '11:30'
    - '13:30'
    - '15:00'
    - '18:00'
    - '21:00'

delete_keywords: 0
keywords:
    - twitter

tweet_mode: new_tweet

CONF
    close CONFFILE;
    $log->debug("Dumped conf file to '$self->{home}/$self->{conffile}'");
}

1;

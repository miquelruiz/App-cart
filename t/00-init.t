
use strict;
use warnings;

use FindBin;
use lib ( "$FindBin::Bin", "$FindBin::Bin/../lib" );

use App::cart::TestUtils;

use Test::More tests => 7;
use Test::Exception;

BEGIN { use_ok( 'App::cart' ); }

my $dir  = "test-home";
my @opts = ('-l', $ENV{CART_TEST_LOGLEVEL} || 'none', '-h', $dir);

chdir $FindBin::Bin;

# Can't run if home doesn't exist
my $app = App::cart->new(@opts);
throws_ok { $app->run } qr/not a valid home directory/, "Not valid home";




# Create home, but there won't be a config file
mkdir $dir;
$app = App::cart->new(@opts);
throws_ok { $app->run } qr/Can't read conffile/, "No config file";
rmdir $dir;




# Initialize home
$app = App::cart->new(@opts, 'init');
lives_ok { $app->run } "Init didn't die";
ok( -d $dir, "Home created" );
ok( -s "$dir/cart.yml", "Conffile not empty" );

SKIP: {
    skip 'NO $ENV{CART_ACCESS_TOKEN} and $ENV{CART_ACCESS_TOKEN_SECRET}', 1
        unless (    defined $ENV{CART_ACCESS_TOKEN}
                and defined $ENV{CART_ACCESS_TOKEN_SECRET} );

    require YAML::Any;

    my $user = $ENV{CART_TEST_USERNAME} || 'twitterapi';
    my $expected_content = <<EOF;
#--
oauth:
    consumer_key        : AulRZomifEbzRAAqDg9CXg
    consumer_secret     : 5BsR6pEwBO31xWLMoi0FFn8o0oWyp4j997FPupqoP4
    access_token        : $ENV{CART_ACCESS_TOKEN}
    access_token_secret : $ENV{CART_ACCESS_TOKEN_SECRET}

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

EOF

    my $expected_conf = YAML::Any::Load($expected_content);
    my $got_conf      = read_config();
    delete $got_conf->{loglevel};
    delete $got_conf->{home};
    is_deeply($got_conf, $expected_conf, "Confs are equivalent");
}

system(qw/rm -Rf/, $dir);


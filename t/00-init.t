
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More;
use Test::Exception;

BEGIN { use_ok( 'App::cart' ); }

$ENV{TEST_CART_INIT} = 1;
my $dir  = "test-home";
my @opts = ('-l', $ENV{TEST_CART_LOGLEVEL} || 'none', '-h', $dir);

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

system(qw/rm -Rf/, $dir);
done_testing();

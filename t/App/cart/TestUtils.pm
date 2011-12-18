package App::cart::TestUtils;

use strict;
use warnings;

use YAML::Any;
use App::cart;

use base 'Exporter';
our @EXPORT = qw/
    write_config
    read_config
    config_dir
    cleanup_config
    make_tweet
/;

sub config_dir {
    return 'test-home';
}

sub write_config {
    $ENV{CART_TEST_INIT} = 1;
    my $app = App::cart->new('-h', config_dir, '-l', 'none', 'init');
    $app->run;
}

sub read_config {
    my $conf = YAML::Any::LoadFile(config_dir . '/cart.yml');
    $conf->{home} = config_dir;
    $conf->{loglevel} = $ENV{CART_TEST_LOGLEVEL} || 'none';

    return $conf;
}

sub cleanup_config {
    system(qw/rm -Rf/, config_dir);
}

sub make_tweet {
    return {
        id   => scalar rand(999),
        text => shift,
        user => { screen_name => 'test' },
    };
}

1;

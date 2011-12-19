
use strict;
use warnings;
use utf8;

use FindBin '$Bin';
use lib ("$Bin", "$Bin/../lib");

use AnyEvent;
use Time::HiRes 'time';
use App::cart::TestUtils;

use Test::More tests => 3;
use Test::Exception;

BEGIN { use_ok 'App::cart::Collector' };

binmode *STDOUT, ':encoding(UTF-8)';

SKIP: {
    skip 'NO $ENV{CART_ACCESS_TOKEN} and $ENV{CART_ACCESS_TOKEN_SECRET}', 1
        unless (    defined $ENV{CART_ACCESS_TOKEN}
                and defined $ENV{CART_ACCESS_TOKEN_SECRET} );

    write_config();
    my $conf = read_config();

    # instantiate a collector
    my ($conn, $got_tweet) = (AnyEvent->condvar, AnyEvent->condvar);
    my $coll = App::cart::Collector->new($conf, $conn, $got_tweet);

    # Wait until the stream is connected
    $conn->recv;

    # instantiate a twitter client so we can tweet something
    my $nt   = Net::Twitter->new(
        traits => [qw/OAuth API::REST/],
        %{ $conf->{oauth} },
    );
    my $text = time . ' ' . rand(1000);
    $nt->update($text);

    # Wait a little for it
    $got_tweet->recv;

    # instantiate a buffer so we can check if the collector catched it
    my $buffer = App::cart::Buffer->new($conf);
    is($buffer->count, 1, "There's a tweet");
    is($buffer->bshift->{data}, $text, "It is ours");

    cleanup_config();
}


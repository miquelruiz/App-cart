
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
    skip 'NO $ENV{CART_ACCESS_TOKEN} and $ENV{CART_ACCESS_TOKEN_SECRET}', 2
        unless (    defined $ENV{CART_ACCESS_TOKEN}
                and defined $ENV{CART_ACCESS_TOKEN_SECRET} );

    write_config();
    my $conf = read_config();
    $conf->{keywords} = [ '#keyword' ];

    # instantiate a collector
    my ($conn, $got_tweet) = (AnyEvent->condvar, AnyEvent->condvar);
    my $coll = App::cart::Collector->new($conf, $conn, $got_tweet);

    # Wait until the stream is connected
    $conn->recv;

    # instantiate a twitter client so we can tweet something
    my $nt   = Net::Twitter->new(
        traits => [qw/API::RESTv1_1/],
        ssl    => 1,
        %{ $conf->{oauth} },
    );

    my $text;
    for ('#nokeyword', '#keywordcontained', '#keyword') {
        $got_tweet->begin;
        $text = time . ' ' . rand(1000) . ' ' . $_;
        $nt->update($text);
    }

    # Wait for the tweets
    $got_tweet->recv;

    # instantiate a buffer so we can check if the collector catched it
    my $buffer = App::cart::Buffer->new($conf);
    is($buffer->count, 1, "There's only one tweet");
    is($buffer->bshift->{data}, $text, "It is ours");

    cleanup_config();
}



use strict;
use warnings;
use utf8;

use FindBin '$Bin';
use lib ("$Bin", "$Bin/../lib");

use App::cart::TestUtils;

use Test::More tests => 11;
use Test::Exception;

BEGIN { use_ok 'App::cart::Buffer' };

binmode *STDOUT, ':encoding(UTF-8)';

write_config();
my $conf = read_config();
my $buffer = App::cart::Buffer->new($conf);


my $retrieved;
lives_ok { $retrieved = $buffer->bshift } "Empty shift";


my $data1 = 'áéíóúñç';
lives_ok { $buffer->bpush(make_tweet($data1)) } "Data pushed";
is( $buffer->count, 1, "Got 1 entry");

my $data2 = make_tweet('ÁÉÍÓÚÑÇ');
lives_ok { $buffer->bpush($data2) } "Data pushed";
is( $buffer->count, 2, "Got 2 entries");

$retrieved = $buffer->bshift->{data};
is($retrieved, $data1, "Retrieved data equals to first pushed");
ok(utf8::is_utf8($retrieved), "Retrieved data is_utf8 :)");
is($buffer->count, 1, "1 Entry left after shift");

$retrieved = $buffer->bshift->{id};
is($retrieved, $data2->{id}, "Retrieved data id is second pushed");
is($buffer->count, 0, "Buffer is empty");

cleanup_config();


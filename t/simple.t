#!perl
use strict;
use warnings;
no warnings 'once';
use Test::More tests => 7;
use Test::Exception;
use_ok('Net::OpenDHT');

my $dht = Net::OpenDHT->new();
$dht->application("simple.t");

my $key   = 'simple.t: key' . int( rand(100_000) );
my $value = 'value' . rand(100_000);
$dht->put( $key, $value, 20 );
is( $dht->fetch($key), $value );

my $value2 = "value" x 100;
$dht->put( $key, $value2, 20 );
is( $dht->fetch($key), $value );
is_deeply( [ $dht->fetch($key) ], [ $value, $value2 ] );

my $key2 = 'simple.t: key' . int( rand(100_000) );
foreach my $i ( 1 .. 10 ) {
    $dht->put( $key2, $i, 60 );
}
$Net::OpenDHT::VALUES = 5;    # test the placemark
is_deeply( [ $dht->fetch($key2) ], [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ] );

my $key3 = 'simple.t: key' . int( rand(100_000) );
$dht->put( $key3, "foo", 60 * 10 );
is_deeply( [ $dht->fetch($key3) ], ["foo"] );
$dht->server("not.a.real.host");
throws_ok { [ $dht->fetch($key3) ], ["foo"] } qr/Error making request/;

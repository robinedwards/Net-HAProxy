use strict;
use warnings;
use Test::More tests => 1;
use Net::HAProxy;
use Data::Dumper;

my $socket = '/var/run/haproxy-services.sock';

my $haproxy = Net::HAProxy->new(
    socket => $socket
);

isa_ok $haproxy, 'Net::HAProxy';

#$haproxy->stats();
my $res =  $haproxy->stats;

for my $row (grep { $_->{pxname} =~ /robin/} @$res) {
    diag $row->{svname}, "|", $row->{pxname}, "|", $row->{sid}, "|", $row->{pid};
    diag Dumper $row;
}
#diag Dumper $haproxy->info();
#$diag Dumper $haproxy->errors();
#$diag Dumper $haproxy->sessions;


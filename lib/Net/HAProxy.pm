package Net::HAProxy;
use Moose;
use Moose::Util::TypeConstraints;
use Fcntl 'S_ISSOCK';
use IO::Socket::UNIX;
use IO::Scalar;
use Text::CSV;
use Data::Dumper;
use namespace::autoclean;

subtype 'ReadWritableSocket',
    as 'Str',
    where {
        -w $_ && -r $_ && S_ISSOCK((stat($_))[2]) # check mode
    },
    message { "'$_' is not a read/writable socket." };

has socket => (is => 'ro', isa => 'ReadWritableSocket', required => 1);
has timeout => (is => 'ro', isa => 'Int', default => 1);

sub _send_command {
    my ($self, $cmd) = @_;

    my $sock = IO::Socket::UNIX->new(
            Peer => $self->socket,
            Type => SOCK_STREAM,
            Timeout => $self->timeout
        );

    $sock->write("$cmd\n");
    local $/ = undef;
    my $data = (<$sock>);
    $sock->close;

    chomp $data;
    return IO::Scalar->new(\$data);
}

=head2 stats

Arguments: (proxy_id, type, server_id)
    - proxy id, -1 for everything (default)
    - type of dumpable objects: 1 for frontends, 2 for backends, 4 for servers,
        -1 for everything (default).

    these values can be ORed, for example:
          1 + 2     = 3   -> frontend + backend.
          1 + 2 + 4 = 7   -> frontend + backend + server.

    - server_id, -1 to dump everything from the selected proxy.

Returns: arrayref of hashes

=cut

sub stats {
    my ($self, %args) = @_;

    my $iid = $args{proxy_id} || '-1';
    my $type = $args{type} || '-1';
    my $sid = $args{server_id} || '-1';

    # http://haproxy.1wt.eu/download/1.3/doc/configuration.txt
    # see section 9
    my $resp = $self->_send_command("show stat $iid $type $sid");

    my $fields = $resp->getline;
    $fields =~ s/^\# //;

    my $csv = Text::CSV->new;
    $csv->parse($fields);
    $csv->column_names(grep { length } $csv->fields);

    my $res = $csv->getline_hr_all($resp); pop @$res;
    return $res;
}


=head2 info

returns a hash

=cut

sub info {
    my ($self) = @_;
    my $resp = $self->_send_command("show info");

    my $info = {};

    while (<$resp>) {
        chomp $_;
        next unless length $_;
        my ($key, $value) = split /:\s+/, $_;
        $info->{$key} = $value;
    }

    return $info;
}

=head2 enable_server

Arguments: proxy name, server name

=cut

sub enable_server {
    my ($self, $pxname, $svname) = @_;
    my $resp = $self->_send_command("enable server $pxname/$svname");
    my $d = <$resp>;
    return $d;
}

=head2 disable_server

Arguments: proxy name, server name

=cut

sub disable_server {
    my ($self, $pxname, $svname) = @_;
    my $resp = $self->_send_command("disable server $pxname/$svname");
}

# TODO: errors and sessions need handling properly.

sub errors {
    my ($self) = @_;
    my $resp = $self->_send_command("show errors");
    my $errors = <$resp>;
    chomp $errors;
    return $errors
}

sub sessions {
    my ($self) = @_;
    my $resp = $self->_send_command("show sess");
    my $sessions = <$resp>;
    chomp $sessions;
    return $sessions
}

__PACKAGE__->meta->make_immutable;
1;

package Net::HAProxy;
use Moose;
use Moose::Util::TypeConstraints;
use IO::Socket::UNIX;
use IO::Scalar;
use Text::CSV;
use namespace::autoclean;

subtype 'ReadWritableSocket',
    as 'Str',
    where { -w $_ && -r $_ && -S $_ },
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

    return $data;
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
    my $data = $self->_send_command("show stat $iid $type $sid");

    my $sh = IO::Scalar->new(\$data);

    my $fields = $sh->getline;
    $fields =~ s/^\# //;

    my $csv = Text::CSV->new;
    $csv->parse($fields);
    $csv->column_names(grep { length } $csv->fields);

    my $res = $csv->getline_hr_all($sh); pop @$res;
    return $res;
}


=head2 info

returns a hash

=cut

sub info {
    my ($self) = @_;
    my $data = $self->_send_command("show info");

    my $info = {};

    for my $line (split /\n/, $data) {
        chomp $line;
        next unless length $line;
        my ($key, $value) = split /:\s+/, $line;
        $info->{$key} = $value;
    }

    return $info;
}

=head2 set_weight

Arguments: proxy name, server name, integer (0-100)

Dies on invalid proxy / server name / weighting

=cut


sub set_weight {
    my ($self, $pxname, $svname, $weight) = @_;

    die "Invalid weight must be between  0 and 100"
        unless $weight > 0 and $weight <= 100;

    my $response = $self->_send_command("enable server $pxname/$svname $weight\%");
    chomp $response;
    die $response if length $response;
    return 1;
}


=head2 enable_server

Arguments: proxy name, server name

Dies on invalid proxy / server name.

=cut

sub enable_server {
    my ($self, $pxname, $svname) = @_;
    my $response = $self->_send_command("enable server $pxname/$svname");
    chomp $response;
    die $response if length $response;
    return 1;
}

=head2 disable_server

Arguments: proxy name, server name

Dies on invalid proxy / server name.

=cut

sub disable_server {
    my ($self, $pxname, $svname) = @_;
    my $response = $self->_send_command("disable server $pxname/$svname");
    chomp $response;
    die $response if length $response;
    return 1;
}

# TODO: errors and sessions need handling properly.

=head2 errors

list errors (TODO response not parsed)

=cut

sub errors {
    my ($self) = @_;
    return $self->_send_command("show errors");
}

=head2 sessions

show sessions (TODO response not parsed)

=cut

sub sessions {
    my ($self) = @_;
    return  $self->_send_command("show sess");
}

__PACKAGE__->meta->make_immutable;

1;

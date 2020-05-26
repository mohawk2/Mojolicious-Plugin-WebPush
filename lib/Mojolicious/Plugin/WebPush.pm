package Mojolicious::Plugin::WebPush;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON qw(decode_json);
use Crypt::PK::ECC;
use MIME::Base64 qw(encode_base64url decode_base64url);
use Crypt::JWT qw(encode_jwt decode_jwt);

our $VERSION = '0.01';

my @MANDATORY_CONF = qw(
  subs_session2user_p
  save_endpoint
  subs_create_p
  subs_read_p
  subs_delete_p
);
my @AUTH_CONF = qw(claim_sub ecc_private_key);

sub _decode {
  my ($bytes) = @_;
  my $body = eval { decode_json($bytes) };
  # conceal error info like versions from attackers
  return (0, "Malformed request") if $@;
  (1, $body);
}

sub _error {
  my ($c, $error) = @_;
  $c->render(status => 500, json => { errors => [ { message => $error } ] });
}

sub _make_route_handler {
  my ($subs_session2user_p, $subs_create_p) = @_;
  sub {
    my ($c) = @_;
    my ($decode_ok, $body) = _decode($c->req->body);
    return _error($c, $body) if !$decode_ok;
    eval { validate_subs_info($body) };
    return _error($c, $@) if $@;
    return $subs_session2user_p->($c->session)->then(
      sub { $subs_create_p->($_[0], $body) },
    )->then(
      sub { $c->render(json => { data => { success => \1 } }) },
      sub { _error($c, @_) },
    );
  };
}

sub _make_auth_helper {
  my ($app, $conf) = @_;
  my $exp_offset = $conf->{claim_exp_offset} || 86400;
  my $key = Crypt::PK::ECC->new($conf->{ecc_private_key});
  my $aud = $app->webpush->aud;
  my $claims_start = { aud => $aud, sub => $conf->{claim_sub} };
  my $pkey = encode_base64url $key->export_key_raw('public');
  $app->helper('webpush.public_key' => sub { $pkey });
  sub {
    my ($c) = @_;
    my $claims = { exp => time + $exp_offset, %$claims_start };
    my $token = encode_jwt key => $key, alg => 'ES256', payload => $claims;
    "vapid t=$token,k=$pkey";
  };
}

sub _aud_helper {
  $_[0]->ua->server->url->path(Mojo::Path->new->trailing_slash(0)).'';
}

sub _verify_helper {
  my ($app, $auth_header_value) = @_;
  (my $schema, $auth_header_value) = split ' ', $auth_header_value;
  return if $schema ne 'vapid';
  my %k2v = map split('=', $_), split ',', $auth_header_value;
  eval {
    my $key = Crypt::PK::ECC->new;
    $key->import_key_raw(decode_base64url($k2v{k}), 'P-256');
    decode_jwt token => $k2v{t}, key => $key, alg => 'ES256', verify_exp => 0;
  };
}

sub register {
  my ($self, $app, $conf) = @_;
  my @config_errors = grep !exists $conf->{$_}, @MANDATORY_CONF;
  die "Missing config keys @config_errors\n" if @config_errors;
  $app->helper('webpush.create_p' => sub {
    eval { validate_subs_info($_[2]) };
    return Mojo::Promise->reject($@) if $@;
    $conf->{subs_create_p}->(@_[1,2]);
  });
  $app->helper('webpush.read_p' => sub { $conf->{subs_read_p}->($_[1]) });
  $app->helper('webpush.delete_p' => sub { $conf->{subs_delete_p}->($_[1]) });
  $app->helper('webpush.aud' => \&_aud_helper);
  $app->helper('webpush.authorization' => (grep !$conf->{$_}, @AUTH_CONF)
    ? sub { die "Must provide @AUTH_CONF\n" }
    : _make_auth_helper($app, $conf)
  );
  $app->helper('webpush.verify_token' => \&_verify_helper);
  my $r = $app->routes;
  $r->post($conf->{save_endpoint} => _make_route_handler(
    @$conf{qw(subs_session2user_p subs_create_p)},
  ), 'webpush.save');
  $self;
}

sub validate_subs_info {
  my ($info) = @_;
  die "Expected object\n" if ref $info ne 'HASH';
  my @errors = map "no $_", grep !exists $info->{$_}, qw(keys endpoint);
  push @errors, map "no $_", grep !exists $info->{keys}{$_}, qw(auth p256dh);
  die "Errors found in subscription info: " . join(", ", @errors) . "\n"
    if @errors;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::WebPush - plugin to aid real-time web push

=head1 SYNOPSIS

  # Mojolicious::Lite
  my $webpush = plugin 'WebPush' => {
    save_endpoint => '/api/savesubs',
    subs_session2user_p => \&subs_session2user_p,
    subs_create_p => \&subs_create_p,
    subs_read_p => \&subs_read_p,
    subs_delete_p => \&subs_delete_p,
    ecc_private_key => 'vapid_private_key.pem',
    claim_sub => "mailto:admin@example.com",
  };

  sub subs_session2user_p {
    my ($session) = @_;
    return Mojo::Promise->reject("Session not logged in") if !$session->{user_id};
    Mojo::Promise->resolve($session->{user_id});
  }

  sub subs_create_p {
    my ($session, $subs_info) = @_;
    app->db->save_subs_p($session->{user_id}, $subs_info);
  }

  sub subs_read_p {
    my ($user_id) = @_;
    app->db->lookup_subs_p($user_id);
  }

  sub subs_delete_p {
    my ($user_id) = @_;
    app->db->delete_subs_p($user_id);
  }

=head1 DESCRIPTION

L<Mojolicious::Plugin::WebPush> is a L<Mojolicious> plugin.

=head1 METHODS

L<Mojolicious::Plugin::WebPush> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  my $p = $plugin->register(Mojolicious->new, \%conf);

Register plugin in L<Mojolicious> application, returning the plugin
object. Takes a hash-ref as configuration, see L</OPTIONS> for keys.

=head1 OPTIONS

=head2 save_endpoint

Required. The route to be added to the app for the service worker to
register users for push notification. The handler for that will call
the L</subs_create_p>. If success is indicated, it will return JSON:

  { "data": { "success": true } }

If failure:

  { "errors": [ { "message": "The exception reason" } ] }

This will be handled by the provided service worker. In case it is
required by the app itself, the added route is named C<webpush.save>.

=head2 subs_session2user_p

Required. The code to be called to look up the user currently identified
by this session, which returns a promise of the user ID. Must reject
if no user logged in and that matters. It will be passed parameters:

=over

=item *

The L<Mojolicious::Controller/session> object, to correctly identify
the user.

=back

=head2 subs_create_p

Required. The code to be called to store users registered for push
notifications, which must return a promise of a true value if the
operation succeeds, or reject with a reason. It will be passed parameters:

=over

=item *

The ID to correctly identify the user.

=item *

The C<subscription_info> hash-ref, needed to push actual messages.

=back

=head2 subs_read_p

Required. The code to be called to look up a user registered for push
notifications. It will be passed parameters:

=over

=item *

The opaque information your app uses to identify the user.

=back

Returns a promise of the C<subscription_info> hash-ref. Must reject if
not found.

=head2 subs_delete_p

Required. The code to be called to delete up a user registered for push
notifications. It will be passed parameters:

=over

=item *

The opaque information your app uses to identify the user.

=back

Returns a promise of the deletion result. Must reject if not found.

=head2 ecc_private_key

A value to be passed to L<Crypt::PK::ECC/new>: a simple scalar is a
filename, a scalar-ref is the actual key. If not provided,
L</webpush.authorization> will (obviously) not be able to function.

=head2 claim_sub

A value to be used as the C<sub> claim by the L</webpush.authorization>,
which needs it. Must be either an HTTPS or C<mailto:> URL.

=head2 claim_exp_offset

A value to be added to current time, in seconds, in the C<exp> claim
for L</webpush.authorization>. Defaults to 86400 (24 hours). The maximum
valid value in RFC 8292 is 86400.

=head1 HELPERS

=head2 webpush.create_p

  $c->webpush->create_p($user_id, $subs_info)->then(sub {
    $c->render(json => { data => { success => \1 } });
  });

=head2 webpush.read_p

  $c->webpush->read_p($user_id)->then(sub {
    $c->render(text => 'Info: ' . to_json(shift));
  });

=head2 webpush.delete_p

  $c->webpush->delete_p($user_id)->then(sub {
    $c->render(json => { data => { success => \1 } });
  });

=head2 webpush.authorization

  my $header_value = $c->webpush->authorization;

Won't function without L</claim_sub> and L</ecc_private_key>. Returns
a suitable C<Authorization> header value to send to a push service.
Valid for a period defined by L</claim_exp_offset>. Not currently cached,
but could become so to avoid unnecessary computation.

=head2 webpush.aud

  my $aud = $c->webpush->aud;

Gives the app's value it will use for the C<aud> JWT claim, useful mostly
for testing.

=head2 webpush.public_key

  my $pkey = $c->webpush->public_key;

Gives the app's public VAPID key, calculated from the private key.

=head2 webpush.verify_token

  my $bool = $c->webpush->verify_token($authorization_header_value);

Cryptographically verifies a JSON Web Token (JWT), such as generated
by L</webpush.authorization>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

L<Mojolicious::Command::webpush> - command-line control of web-push.

RFC 8292 - Voluntary Application Server Identification (for web push).

L<https://developers.google.com/web/fundamentals/push-notifications>

=head1 ACKNOWLEDGEMENTS

Part of this code is ported from
L<https://github.com/web-push-libs/pywebpush>.

=cut

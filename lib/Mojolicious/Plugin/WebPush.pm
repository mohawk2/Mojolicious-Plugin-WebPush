package Mojolicious::Plugin::WebPush;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON qw(decode_json to_json);

our $VERSION = '0.01';

my @MANDATORY_CONF = qw(
  subs_session2user_p
  save_endpoint
  subs_create_p
  subs_read_p
  subs_delete_p
);

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
  my $r = $app->routes;
  $r->post($conf->{save_endpoint} => _make_route_handler(
    @$conf{qw(subs_session2user_p subs_create_p)},
  ));
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

This will be handled by the provided service worker.

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

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

L<Mojolicious::Command::webpush> - command-line control of web-push.

L<https://developers.google.com/web/fundamentals/push-notifications>

=head1 ACKNOWLEDGEMENTS

Part of this code is ported from
L<https://github.com/web-push-libs/pywebpush>.

=cut

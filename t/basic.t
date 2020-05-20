use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use Mojo::Promise;

my $ENDPOINT = '/api/savesubs';
my $webpush = plugin 'WebPush' => {
  save_endpoint => $ENDPOINT,
  subs_session2user_p => \&subs_session2user_p,
  subs_create_p => \&subs_create_p,
  subs_read_p => \&subs_read_p,
  subs_delete_p => \&subs_delete_p,
};

sub subs_session2user_p {
  return Mojo::Promise->reject("Session not logged in") if !$_[0]{user_id};
  Mojo::Promise->resolve($_[0]{user_id});
}

my %userdb;
sub subs_create_p {
  my ($user_id, $subs_info) = @_;
  $userdb{$user_id} = $subs_info;
  Mojo::Promise->resolve(1);
}

sub subs_read_p {
  my ($user_id) = @_;
  return Mojo::Promise->reject("Not found: '$user_id'") if !$userdb{$user_id};
  Mojo::Promise->resolve($userdb{$user_id});
}

sub subs_delete_p {
  my ($user_id) = @_;
  return Mojo::Promise->reject("Not found: '$user_id'") if !$userdb{$user_id};
  Mojo::Promise->resolve(delete $userdb{$user_id});
}

post '/login/:user_id' => sub {
  my $c = shift;
  $c->session(user_id => $c->stash('user_id'));
  $c->render(text => 'Hello ' . $c->stash('user_id'));
};

my $t = Test::Mojo->new;
subtest 'login' => sub {
  $t->post_ok('/login/bob')->status_is(200)->content_is('Hello bob');
};

my @SUBS = (
  [ { keys => {} }, qr/no endpoint/ ],
  [ { endpoint => '/push/bob/v2' }, qr/no keys/ ],
  [ { endpoint => '/push/bob/v2', keys => { p256dh => '' } }, qr/no auth/ ],
  [ { endpoint => '/push/bob/v2', keys => { auth => '' } }, qr/no p256dh/ ],
  [ { endpoint => '/push/bob/v2', keys => { auth => '', p256dh => '' } }, qr/^$/ ],
);
subtest 'validate' => sub {
  for (@SUBS) {
    eval { Mojolicious::Plugin::WebPush::validate_subs_info($_->[0]) };
    like $@, $_->[1];
  }
};

my $bob_data = { endpoint => '/push/bob/v2', keys => { auth => '', p256dh => '' } };
subtest 'save' => sub {
  $t->post_ok($ENDPOINT, json => {})
    ->status_is(500)->json_like('/errors/0/message', qr/no endpoint/)
    ->or(sub { diag explain $t->tx->res->body })
    ;
  $t->post_ok($ENDPOINT, json => $bob_data)
    ->status_is(200)->json_is({ data => { success => 1 } })
    ->or(sub { diag explain $t->tx->res->body })
    ;
  is_deeply $userdb{bob}, $bob_data;
};

subtest 'webpush.create_p' => sub {
  my $info;
  app->webpush->create_p('bill', $bob_data)->then(sub { $info = shift })->wait;
  isnt $info, undef;
  is_deeply $userdb{bill}, $bob_data;
  delete $userdb{bill};
};

subtest 'webpush.read_p' => sub {
  my $info;
  app->webpush->read_p('bob')->then(sub { $info = shift })->wait;
  is_deeply $info, $bob_data;
  my $temp = delete $userdb{bob};
  my $rej;
  app->webpush->read_p('bob')->then(undef, sub { $rej = shift })->wait;
  isnt $rej, undef;
  $userdb{bob} = $temp;
};

subtest 'webpush.delete_p' => sub {
  my $info;
  app->webpush->delete_p('bob')->then(sub { $info = shift })->wait;
  isnt $info, undef;
};

done_testing();

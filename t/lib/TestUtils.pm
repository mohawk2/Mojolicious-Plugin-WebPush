package TestUtils;

use Mojo::Promise;
use Exporter 'import';

our @EXPORT_OK = qw(webpush_config $ENDPOINT %userdb);

our $ENDPOINT = '/api/savesubs';
our %userdb;

sub webpush_config {
  +{
    save_endpoint => $ENDPOINT,
    subs_session2user_p => \&subs_session2user_p,
    subs_create_p => \&subs_create_p,
    subs_read_p => \&subs_read_p,
    subs_delete_p => \&subs_delete_p,
  };
}

sub subs_session2user_p {
  return Mojo::Promise->reject("Session not logged in") if !$_[0]{user_id};
  Mojo::Promise->resolve($_[0]{user_id});
}

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

1;

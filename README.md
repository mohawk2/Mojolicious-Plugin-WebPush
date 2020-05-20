# NAME

Mojolicious::Plugin::WebPush - plugin to aid real-time web push

# SYNOPSIS

    # Mojolicious::Lite
    my $webpush = plugin 'WebPush' => {
      save_endpoint => '/api/savesubs',
      subs_session2user_p => \&subs_session2user_p,
      subs_create_p => \&subs_create_p,
      subs_read_p => \&subs_read_p,
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

# DESCRIPTION

[Mojolicious::Plugin::WebPush](https://metacpan.org/pod/Mojolicious::Plugin::WebPush) is a [Mojolicious](https://metacpan.org/pod/Mojolicious) plugin.

# METHODS

[Mojolicious::Plugin::WebPush](https://metacpan.org/pod/Mojolicious::Plugin::WebPush) inherits all methods from
[Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious::Plugin) and implements the following new ones.

## register

    my $p = $plugin->register(Mojolicious->new, \%conf);

Register plugin in [Mojolicious](https://metacpan.org/pod/Mojolicious) application, returning the plugin
object. Takes a hash-ref as configuration, see ["OPTIONS"](#options) for keys.

# OPTIONS

## save\_endpoint

Required. The route to be added to the app for the service worker to
register users for push notification. The handler for that will call
the ["subs\_create\_p"](#subs_create_p). If success is indicated, it will return JSON:

    { "data": { "success": true } }

If failure:

    { "errors": [ { "message": "The exception reason" } ] }

This will be handled by the provided service worker.

## subs\_session2user\_p

Required. The code to be called to look up the user currently identified
by this session, which returns a promise of the user ID. Must reject
if no user logged in and that matters. It will be passed parameters:

- The ["session" in Mojolicious::Controller](https://metacpan.org/pod/Mojolicious::Controller#session) object, to correctly identify
the user.

## subs\_create\_p

Required. The code to be called to store users registered for push
notifications, which must return a promise of a true value if the
operation succeeds, or reject with a reason. It will be passed parameters:

- The ID to correctly identify the user.
- The `subscription_info` hash-ref, needed to push actual messages.

## subs\_read\_p

Required. The code to be called to look up a user registered for push
notifications. It will be passed parameters:

- The opaque information your app uses to identify the user.

Returns a promise of the `subscription_info` hash-ref. Must reject if
not found.

# HELPERS

## webpush.create\_p

    $c->webpush->create_p($user_id, $subs_info)->then(sub {
      $c->render(json => { data => { success => \1 } });
    });

## webpush.read\_p

    $c->webpush->read_p($user_id)->then(sub {
      $c->render(text => 'Info: ' . to_json(shift));
    });

# SEE ALSO

[Mojolicious](https://metacpan.org/pod/Mojolicious), [Mojolicious::Guides](https://metacpan.org/pod/Mojolicious::Guides), [https://mojolicious.org](https://mojolicious.org).

[https://developers.google.com/web/fundamentals/push-notifications](https://developers.google.com/web/fundamentals/push-notifications)

# ACKNOWLEDGEMENTS

Part of this code is ported from
[https://github.com/web-push-libs/pywebpush](https://github.com/web-push-libs/pywebpush).
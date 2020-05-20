package Mojolicious::Command::webpush;
use Mojo::Base 'Mojolicious::Command';
use Mojo::JSON qw(encode_json decode_json);

my %COMMAND2JSON = (
  create => [ 1 ],
);

has description => q{Manage your app's web-push};
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, $cmd, @args) = @_;
  $args[$_] = decode_json($args[$_]) for @{ $COMMAND2JSON{$cmd} || [] };
  $cmd .= "_p";
  $self->app->webpush->$cmd(@args)->then(
    sub { print encode_json(@_), "\n" },
    sub { print STDERR @_, "\n" },
  )->wait;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::webpush - Manage your app's web-push

=head1 SYNOPSIS

  Usage: APPLICATION webpush COMMAND [OPTIONS]

    ./myapp.pl webpush create <USERID> <JSON>
    ./myapp.pl webpush read <USERID>
    ./myapp.pl webpush delete <USERID>

  Options:
    -h, --help          Show this summary of available options
        --home <path>   Path to home directory of your application, defaults to
                        the value of MOJO_HOME or auto-detection
    -m, --mode <name>   Operating mode for your application, defaults to the
                        value of MOJO_MODE/PLACK_ENV or "development"

=head1 DESCRIPTION

L<Mojolicious::Command::webpush> manages your application's web-push
information. It gives a command-line interface to the helpers in
L<Mojolicious::Plugin::WebPush/HELPERS>.

=head1 ATTRIBUTES

L<Mojolicious::Command::webpush> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head1 METHODS

L<Mojolicious::Command::webpush> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head1 SEE ALSO

L<Mojolicious::Plugin::WebPush>

=cut

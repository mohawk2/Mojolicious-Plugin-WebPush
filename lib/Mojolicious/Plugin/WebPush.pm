package Mojolicious::Plugin::WebPush;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.01';

sub register {
  my ($self, $app) = @_;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::WebPush - Mojolicious Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('WebPush');

  # Mojolicious::Lite
  plugin 'WebPush';

=head1 DESCRIPTION

L<Mojolicious::Plugin::WebPush> is a L<Mojolicious> plugin.

=head1 METHODS

L<Mojolicious::Plugin::WebPush> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut

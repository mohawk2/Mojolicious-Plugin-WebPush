use Mojolicious::Lite;
use Test::More;
use Test::Mojo;
use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;
use TestUtils qw(webpush_config);
use MIME::Base64 qw(encode_base64url decode_base64url);
use Crypt::PRNG qw(random_bytes_b64u);
use Crypt::RFC8188 qw(ece_decrypt_aes128gcm);

plugin 'WebPush' => webpush_config();

# modified port of github.com/web-push-libs/pywebpush tests

sub gen_key { Crypt::PK::ECC->new->generate_key('prime256v1') }

my $SUBSCRIBER_PRIVATE_KEY = Crypt::PK::ECC->new(\<<'EOF');
-----BEGIN EC PRIVATE KEY-----
MIIBUQIBAQQg9X7ive4ad4jxHp26ih5txYyI+SJBEXA/CwssNwI3GlGggeMwgeAC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MEQEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwRBBGsX0fLhLEJH+Lzm5WOkQPJ3A32BLesz
oPShOUXYmMKWT+NC4v4af5uO5+tKfA+eFivOM1drMV7Oy7ZAaDe/UfUCIQD/////
AAAAAP//////////vOb6racXnoTzucrC/GMlUQIBAaFEA0IABDcPP9pxv+0Mgh0D
lOD0jl034EJq+7QhAnIrMn/7k6FbOp0Emj0iCgQXceqrogRye6rwl5GbkkMQLmcW
HUSdzAY=
-----END EC PRIVATE KEY-----
EOF
my $SUBS_INFO = gen_subscription_info($SUBSCRIBER_PRIVATE_KEY);

sub gen_subscription_info {
  my ($recv_key, $endpoint) = @_;
  $recv_key ||= gen_key();
  $endpoint ||= "https://example.com/";
  +{
    endpoint => $endpoint,
    keys => {
      auth => random_bytes_b64u(16),
      p256dh => encode_base64url($recv_key->export_key_raw('public')),
    },
  };
}

subtest 'encrypt RFC8188' => sub {
  my $data = "Mary had a little lamb, with some nice mint jelly";
  my @keys = map decode_base64url($_),
    @{$SUBS_INFO->{keys}}{qw(p256dh auth)};
  my $ciphertext = app->webpush->encrypt($data, @keys);
  # Convert these b64 strings into their raw, binary form.
  my $decoded = ece_decrypt_aes128gcm(
    $ciphertext,
    undef,
    $SUBSCRIBER_PRIVATE_KEY,
    undef,
    $keys[1],
  );
  is $decoded, $data;
};

done_testing;

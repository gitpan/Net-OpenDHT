use Module::Build;
use strict;

my $build = Module::Build->new(
  create_makefile_pl => 'traditional',
  license            => 'perl',
  module_name        => 'Net::OpenDHT',
  requires           => {
    'Test::More'                     => '0',
    'Class::Accessor::Chained::Fast' => '0',
    'Test::Exception'                => '0',
    'LWP::UserAgent'                 => '0',
    'MIME::Base64'                   => '0',
    'XML::LibXML'                    => '0',
  },
);
$build->create_build_script;

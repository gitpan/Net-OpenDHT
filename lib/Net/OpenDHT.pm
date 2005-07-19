package Net::OpenDHT;
use strict;
use warnings;
use HTTP::Request;
use List::Util qw(shuffle);
use App::Cache;
use LWP::UserAgent;
use MIME::Base64;
use Time::HiRes qw(time);
use XML::LibXML;
use base 'Class::Accessor::Chained::Fast';
__PACKAGE__->mk_accessors(qw(ttl application server));
our $VERSION = '0.31';
our $VALUES = 100;

my $ua = LWP::UserAgent->new();

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  unless ($self->server) {
    my $cache = App::Cache->new({ ttl => 24*60*60 });
    my $server = $cache->get_code("server", sub { $self->_find_server() });
    $self->server($server);
  }
  return $self;
}

sub _find_server {
  my $self = shift;
  my $url = 'http://appmanager.berkeley.intel-research.net/plcontrol/apps.php?appid=1001&GROUP=ANY&BUILD=ANY&CSTATUS=STATUS-3&RSTATUS=STATUS-3&GO=GO';
  my $request = HTTP::Request->new(GET => $url);
  my $response = $ua->request($request);
  die "Error fetching $url" unless $response->is_success;
  my $html = $response->content;
  my @hosts;
  while ($html =~ m{<TR><TD><FONT SIZE=2>(.+?)</FONT></TD>}g) {
    push @hosts, $1;
  }
  @hosts = (shuffle @hosts)[0..15];
  my($fastest_time, $fastest_host) = (999, "");
  foreach my $host (@hosts) {
    $request = HTTP::Request->new(GET => "http://$host:5851");
    my $response = $ua->request($request);
    my $start = time;
    $response = $ua->request($request);
    next unless $response->is_success;
    my $time = time - $start;
    if ($time < $fastest_time) {
      $fastest_time = $time;
      $fastest_host = $host;
    }
  }
  return $fastest_host;
}

sub _make_request {
 my($self, $xml) = @_;

  my $server = $self->server || die "No server";
  my $request = HTTP::Request->new(POST => "http://$server:5851/");
  $request->header(Content_Type => 'text/xml');
  $request->protocol('HTTP/1.0');
  $request->content($xml);
  $request->content_length(length($xml));

  my $response = $ua->request($request);
  die $response->status_line unless $response->is_success;
  return $response;
} 

sub fetch {
  my($self, $key) = @_;
  die "Key '$key' is longer than 20 bytes" if length($key) > 20;

  return $self->_fetch($key, $VALUES, undef);
}

sub _fetch {
  my($self, $key, $values, $placemark) = @_;

  my $xml = $self->_fetch_xml($key, $values, $placemark);
  my $response = $self->_make_request($xml);

  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($response->content);

  my @nodes = $doc->findnodes("/methodResponse/params/param/value/array/data/value/array/data/*/base64");
  my @values = map { decode_base64($_->textContent) } @nodes;

  $placemark = $doc->findvalue("/methodResponse/params/param/value/array/data/value[2]/base64");
  if ($placemark) {
    chomp $placemark;
    push @values, $self->_fetch($key, $values, $placemark);
  }
  
  if (wantarray) {
    return @values;
  } else {
    return $values[0];
  }
}

sub put {
  my($self, $key, $value, $ttl) = @_;

  die "Key '$key' is longer than 20 bytes" if length($key) > 20;
  die "Value '$value' is longer than 1024 bytes" if length($value) > 1024;

  my $xml = $self->_put_xml($key, $value, $ttl);
  my $response = $self->_make_request($xml);
  
  my $parser = XML::LibXML->new();
  my $doc = $parser->parse_string($response->content);
  my $status = $doc->findvalue("/methodResponse/params/param/value/int");

  die "Unknown status $status" unless $status eq '0';
	return;
}

sub _put_xml {  
  my($self, $key, $value, $ttl) = @_;

  $key = encode_base64($key); chomp $key;
  $value = encode_base64($value); chomp $value;

	my $doc = XML::LibXML::Document->new("1.0", "utf8");
	my $method_call = $doc->createElement("methodCall");

	$method_call->appendTextChild(methodName => "put");
	my $params = $doc->createElement("params");

 	my $key_param = $doc->createElement("param");
  my $key_value = $doc->createElement("value");
  $key_value->appendTextChild("base64" => $key);
  $key_param->addChild($key_value);
 	$method_call->addChild($key_param);

 	my $value_param = $doc->createElement("param");
  my $value_value = $doc->createElement("value");
  $value_value->appendTextChild("base64" => $value);
  $value_param->addChild($value_value);
  $method_call->addChild($value_param);

 	my $ttl_param = $doc->createElement("param");
  my $ttl_value = $doc->createElement("value");
  $ttl_value->appendTextChild("int" => $ttl);
  $ttl_param->addChild($ttl_value);
  $method_call->addChild($ttl_param);

 	my $app_param = $doc->createElement("param");
 	$app_param->appendTextChild("value" => $self->application);
	$method_call->addChild($app_param);

  $method_call->addChild($params);
  $doc->setDocumentElement($method_call);
	return $doc->toString(1);
}

sub _fetch_xml {  
  my($self, $key, $values, $placemark) = @_;

  $key = encode_base64($key); chomp $key;
  $values ||= 1;
  $placemark ||= "";
  
	my $doc = XML::LibXML::Document->new("1.0", "utf8");
	my $method_call = $doc->createElement("methodCall");

	$method_call->appendTextChild(methodName => "get");
	my $params = $doc->createElement("params");

 	my $key_param = $doc->createElement("param");
  my $key_value = $doc->createElement("value");
  $key_value->appendTextChild("base64" => $key);
  $key_param->addChild($key_value);
 	$method_call->addChild($key_param);

 	my $ttl_param = $doc->createElement("param");
  my $ttl_value = $doc->createElement("value");
  $ttl_value->appendTextChild("int" => $values);
  $ttl_param->addChild($ttl_value);
  $method_call->addChild($ttl_param);

 	my $value_param = $doc->createElement("param");
  my $value_value = $doc->createElement("value");
  $value_value->appendTextChild("base64" => $placemark);
  $value_param->addChild($value_value);
  $method_call->addChild($value_param);

 	my $app_param = $doc->createElement("param");
 	$app_param->appendTextChild("value" => $self->application);
	$method_call->addChild($app_param);

  $method_call->addChild($params);
  $doc->setDocumentElement($method_call);
	return $doc->toString(1);
}

1;

__END__

=head1 NAME

Net::OpenDHT - Access the Open Distributed Hash Table (Open DHT)

=head1 SYNOPSIS

  my $dht = Net::OpenDHT->new();
  $dht->application("My Application");
  $dht->server($server); # see below

  $dht->put($key, $value, $ttl);
  my $value  = $dht->fetch($key);
  my @values = $dht->fetch($key);

=head1 DESCRIPTION

The Net::OpenDHT module provides a simple interface to the Open DHT
service. Open DHT is a publicly accessible distributed hash table (DHT)
service. In contrast to the usual DHT model, clients of Open DHT do not
need to run a DHT node in order to use the service. Instead, they can
issue put and get operations to any DHT node, which processes the
operations on their behalf. No credentials or accounts are required to
use the service, and the available storage is fairly shared across all
active clients.

This service model of DHT usage greatly simplifies deploying client
applications. By using Open DHT as a highly-available naming and storage
service, clients can ignore the complexities of deploying and
maintaining a DHT and instead concentrate on developing more
sophisticated distributed applications.

What this essentially gives you as a Perl author is robust storage for a
small amount of data. This can be used as a distributed cache or data
store.

Read the following for full semantics about the Open DHT:

  http://opendht.org/users-guide.html

=head1 METHODS

=head2 new

The constructor:

  my $dht = Net::OpenDHT->new();

=head2 application

The application method sets the name of the application. You should set
this as a courtesy to the Open DHT developers:

  $dht->application("My Application");

=head2 fetch

The get method fetches data from the Open DHT. Note that multiple values
can be set for a key:

  my $value  = $dht->fetch($key);
  my @values = $dht->fetch($key);

=head2 put

The put method puts data into the Open DHT. The key has a maximum length
of 20 bytes, the value a maximum length of 1024 bytes. You must also
pass in a time to live in seconds:

  $dht->put($key, $value, $ttl);

=head2 server

The module automatically finds a topologically-close gateway to the DHT.
It will initially start up slowly as it tries to discover a fast gateway
but this information will be cached for a day. You may override this and
provide your own gateway with this method:

  $dht->server($server);

=head1 AUTHOR

Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2005, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.

#!/usr/bin/env perl


use utf8;
use autodie 2.29;
use 5.010001;
use strict;
use warnings;
use warnings qw(FATAL utf8);

use Carp qw[ carp croak ];

use Pandoc::Elements 0.33;
use Pandoc::Walker 0.27 qw[ action transform  ];

sub _msg {
    my $msg = shift;
    $msg = sprintf $msg, @_ if @_;
    $msg =~ s/\n\z//;
    return $msg;
}

sub _error { die _msg( @_ ), "\n"; }

BEGIN {
    no warnings 'prototype';
    use subs qw[ encode_base64 ];
    my @candidates = qw( MIME::Base64 MIME::Base64::Perl );
    for my $module ( @candidates ) {
        eval "require $module; 1;" // next;
        my $sub = $module->can( 'encode_base64' ) // next;
        *encode_base64 = $sub;
        last;
    }
    unless ( defined &encode_base64 ) {
        _error "You must install one of the modules %s or %s", @candidates;
    }
}

use URI;
use URI::Fetch;

my $out_format = shift @ARGV;
my $json = <>;
my $doc = pandoc_json($json);

my $open_errors = $doc->metavalue('data-uri-open-errors')
// $ENV{PANDOC_DATA_URI_OPEN_ERRORS};

## FILE EXTENSION => CONTENT TYPE
#
# This is used to match file extensions of local files
#
# Add file extension => content_type pairs as needed -- lowercase keys!
my %ext2type = (
    jpg  => 'image/jpeg',
    jpeg => 'image/jpeg',
    png  => 'image/png',
    gif  => 'image/gif',
);

my $custom_ext = $doc->metavalue( 'data-uri-ext2content-type' ) // +{};

'HASH' eq ref $custom_ext or die "Expected metadata /data-uri-ext2content-type to be mapping";

%ext2type = %$custom_ext if keys %$custom_ext;

my $custom_types = $doc->metavalue( 'data-uri-remote-content-types' ) // +[values %ext2type];

'ARRAY' eq ref $custom_types or $custom_types = [$custom_types];

## CONTENT TYPES
#
# Match content types which will be encoded.
# This is used to match content types of remote files
#
# Add regexes or strings for literal match as needed.
my $is_encode_type = list2regex( @$custom_types );

my $is_encode_ext = list2regex( 
    keys( %ext2type ),
);
$is_encode_ext = qr/\.($is_encode_ext)\z/;

$is_encode_type = qr!^($is_encode_type)$!;

my $action = action Image => \&filter_action;

$doc->transform( $action );

print $doc->to_json;

sub filter_action {
    my ( $elem ) = @_;
    my $url = $elem->url;
    $url =~ $is_encode_ext or return $elem;
    $elem->url( img2uri( $url ) );
    return $elem;
}

sub list2regex {
    my $pat = join '|',
      sort { length( $b ) <=> length( $a ) }
      map { ; ref( $_ ) ? $_ : quotemeta( $_ ) } @_;
    return qr!$pat!;
}

sub img2uri {
    my ( $url ) = @_;
    my $uri = URI->new( $url );
    my ( $type, $data );
    if ( defined( my $scheme = $uri->scheme ) ) {
        return $url if 'data' eq $scheme;
        # return $url unless lc( $url ) =~ $is_encode_ext;
        my $res = URI::Fetch->fetch( $uri ) or die URI::Fetch->errstr;
        if ( $res->is_success ) {
            $type = $res->content_type;
            $type =~ $is_encode_type or return $url;
            $data = $res->content;
        }
        elsif ( $res->uri eq $uri ) {
            _error "Couldn't fetch image: $uri";
        }
        else {
            _error "Couldn't fetch image: %s (was %s)", $res->uri, $uri;
        }
    }
    elsif ( lc( $url ) =~ $is_encode_ext ) {
        if ( $type = $ext2type{$1} ) {
            local $@;
            my $fh = eval { open my $fh, '<', $url; $fh; } // do {
                my $e = $@;
                $open_errors
                  ? die( $e // "Couldn't open $url" )
                  : do { warn $e if $e; return $url };
            };
            binmode $fh;
            local $/;    # slurp mode
            $data = <$fh>;
            close $fh;
        }
    }
    else {
        return $url;
    }
    $type =~ s/%/%25/g;
    $type =~ s/,/%2C/g;
    $type .= ';base64';
    my $encoded = encode_base64( $data, "" );
    $encoded =~ s/%/%25/g;
    return ( "data:$type,$encoded" );
}

__END__

=encoding UTF-8

=for DOCUMENTATION

=head1 pandoc-img2uri.pl - Convert local and remote images into data URIs

This L<< Pandoc|http://pandoc.org >> filter is useful when you want to
embed images inside your html-based output document but not use Pandoc's
C<< --standalone >> mode.

=head2 Installation

This Pandoc filter is written in Perl and needs perl 5.10.1 and a number
of easily installed third-party modules in addition to Pandoc itself.

See my general instructions for L<< installing Pandoc filters and
Perl-based filters in particular|https://git.io/vbYZa >>, and
"Prerequisites" below for the modules needed for this filter in
particular.

=head2 Usage

For the common case where your source document contains image elements
referencing local or remote files with a file extension from the set
C<< .jpeg .jpg .png .gif >> you don't need to do anything at all except
running this filter when producing HTML-based formats with Pandoc:

    pandoc -F pandoc-img2uri.pl -o my-doc.html my-doc.md

=head2 Configuration

The filter already knows how to map the above extensions to content
types. In the event that you know what you are doing and want to
configure which file extensions and content types trigger conversion to
data URI you can set the metadata fields
C<< data-uri-ext2content-type >> andE<0x2f>or
C<< data-uri-remote-content-types >> as described below.

RelativeE<0x2f>local URLs are checked against a mapping from file
extensions to content types to decide whether to replace them with a
data URI. If the (lowercased) extension matches the filter opens the
file locally in binary mode and base64 encodes its content. To use a
custom mapping from file extensions to content types set the metadata
field C<< data-uri-ext2content-type >> to a mapping with file extensions
-- without a leading dot and in lowercase -- as keys and the
corresponding content types as values. The default is equivalent to

    ---
    data-uri-ext2content-type:
      jpg  : image/jpeg
      jpeg : image/jpeg
      png  : image/png
      gif  : image/gif
    ---

Note that if you provide a custom mapping none of the defaults are kept!

Currently the filter fetches all (absolute) image URLs which have a
known scheme and compares the content type in the response against a
list of content types to decide whether to replace them with a data URI.
To use a custom mapping from file extensions to content types set the
metadata field C<< data-uri-remote-content-types >> to a list with
content types as values. the default is the values from the file
extension to content type mapping described above, but again the default
is ignored if you provide your own list.

If a local file cannot be opened you get a warning (B<< not >> an
error!) and the URL is left as is, unless you have set the metadata
field C<< data-uri-open-errors >> or the environment variable
C<< PANDOC_DATA_URI_OPEN_ERRORS >> to a non-empty, non-zero value, in
which case you I<< will >> get an error. This is useful because it lets
you get warnings instead of errors while working on your document and
turn on errors for the final rendering. If you want to always get errors
you can edit the code where it says
C<< $ENV{PANDOC_DATA_URI_OPEN_ERRORS} >> and set the value of the
C<< $open_errors >> variable to C<< 1 >>.

=head2 Prerequisites

=over

=item *

Pandoc

L<< http:E<0x2f>E<0x2f>pandoc.org|http://pandoc.org/ >>

L<< https:E<0x2f>E<0x2f>github.comE<0x2f>jgmE<0x2f>pandocE<0x2f>releases|https://github.com/jgm/pandoc/releases >>

=item *

perl 5.010001 (see "Installation" above!)

Perl (CPAN) modules:

    autodie
    Pandoc::Elements
    URI
    URI::Fetch
    MIME::Base64

=back

=head2 Copyright and License

This software is copyright (c) 2018 by Benct Philip Jonsson.

This is free software; you can redistribute it andE<0x2f>or modify it
under the same terms as the Perl 5 programming language system itself.
See
L<< http:E<0x2f>E<0x2f>dev.perl.orgE<0x2f>licensesE<0x2f>|http://dev.perl.org/licenses/ >>.

=cut

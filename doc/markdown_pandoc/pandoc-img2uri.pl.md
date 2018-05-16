---
title: 'pandoc-img2uri.pl'
abstract: Convert local and remote images into data URIs
author: 'Benct Philip Jonsson <https://github.com/bpj>'
style: BPJ
---

# pandoc-img2uri.pl - Convert local and remote images into data URIs

This [Pandoc](http://pandoc.org) filter is useful when you want to embed
images inside your html-based output document but not use Pandoc's
`--standalone` mode.

## Installation

This Pandoc filter is written in Perl and needs perl 5.10.1 and a
number of easily installed third-party modules in addition to
Pandoc itself.

See my general instructions for [installing Pandoc filters and
Perl-based filters in particular](https://git.io/vbYZa), and
"Prerequisites" below for the modules needed for this filter in
particular.

## Usage

For the common case where your source document contains image
elements referencing local or remote files with a file extension
from the set `.jpeg .jpg .png .gif` you don't need to do anything
at all except running this filter when producing HTML-based
formats with Pandoc:

    pandoc -F pandoc-img2uri.pl -o my-doc.html my-doc.md

## Configuration

The filter already knows how to map the above extensions to
content types. In the event that you know what you are doing and
want to configure which file extensions and content types trigger
conversion to data URI you can set the metadata fields
`data-uri-ext2content-type` and/or
`data-uri-remote-content-types` as described below.

Relative/local URLs are checked against a mapping from file
extensions to content types to decide whether to replace them
with a data URI. If the (lowercased) extension matches the filter
opens the file locally in binary mode and base64 encodes its
content. To use a custom mapping from file extensions to content
types set the metadata field `data-uri-ext2content-type` to a
mapping with file extensions -- without a leading dot and in
lowercase -- as keys and the corresponding content types as
values. The default is equivalent to

    ---
    data-uri-ext2content-type:
      jpg  : image/jpeg
      jpeg : image/jpeg
      png  : image/png
      gif  : image/gif
    ---

Note that if you provide a custom mapping none of the defaults
are kept!

Currently the filter fetches all (absolute) image URLs which have
a known scheme and compares the content type in the response
against a list of content types to decide whether to replace them
with a data URI. To use a custom mapping from file extensions to
content types set the metadata field
`data-uri-remote-content-types` to a list with content types as
values. the default is the values from the file extension to
content type mapping described above, but again the default is
ignored if you provide your own list.

If a local file cannot be opened you get a warning (**not** an
error!) and the URL is left as is, unless you have set the
metadata field `data-uri-open-errors` or the environment variable
`PANDOC_DATA_URI_OPEN_ERRORS` to a non-empty, non-zero value, in
which case you *will* get an error. This is useful because it
lets you get warnings instead of errors while working on your
document and turn on errors for the final rendering. If you want
to always get errors you can edit the code where it says
`$ENV{PANDOC_DATA_URI_OPEN_ERRORS}` and set the value of the
`$open_errors` variable to `1`.

## Prerequisites

-   Pandoc

    [http://pandoc.org](http://pandoc.org/)

    <https://github.com/jgm/pandoc/releases>

-   perl 5.010001 (see "Installation" above!)

    Perl (CPAN) modules:

        autodie
        Pandoc::Elements
        URI
        URI::Fetch
        MIME::Base64

## Copyright and License

This software is copyright (c) 2018 by Benct Philip Jonsson.

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system
itself. See <http://dev.perl.org/licenses/>.

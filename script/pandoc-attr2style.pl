#!/usr/bin/env perl

use utf8;
use autodie 2.29;
use 5.010001;
use strict;
use warnings;
use warnings qw(FATAL utf8);

use Carp qw[ carp croak ];

use Pandoc::Elements 0.33;
use Pandoc::Walker 0.27 qw[ action transform ];
use String::Interpolate::Shell qw[ strinterp ];
use Scalar::Util qw[ blessed ];

use Try::Tiny;
use Path::Tiny qw[ path cwd ];
use YAML::Any qw[ LoadFile ];
use Hash::Merge qw[ _merge_hashes ];
use Pandoc;

# # use Path::Tiny 0.096 qw[ path cwd tempfile tempdir rootdir ];
# use Data::Printer alias => 'ddp', caller_info => 1;

sub _msg {
    my $msg = shift;
    $msg = sprintf $msg, @_ if @_;
    $msg =~ s/\n\z//;
    return $msg;
}

sub _error { die _msg( @_ ), "\n"; }

sub _to_href ($$;%) {
    my ( $value, $default, %opt ) = @_;
    defined( $value ) or $value = {};
    'HASH' eq ref( $value )
      or $value
      = +{ ( $opt{to_key} ? $value : $default ) => ( $opt{to_key} ? $default : $value ) };
    if ( exists $opt{clone} ) {
        return $value unless $opt{clone};
    }
    return +{%$value};
}

sub _to_aref ($;%) {
    my ( $value, %opt ) = @_;
    defined( $value )        or $value = [];
    'ARRAY' eq ref( $value ) or $value = [$value];
    if ( exists $opt{clone} ) {
        return $value unless $opt{clone};
    }
    return [@$value];
}

my $out_format = shift @ARGV;
my $json       = <>;
my $doc        = pandoc_json( $json );
my $meta       = $doc->meta;

my $config = $meta->value( 'attr2style' ) // +{};
'HASH' eq ref $config or _error "Expected metadata field 'attr2style' to be mapping";

STYLE_FILES: {
    my $a2s_dir = cwd->child( "attr2style" );
    my $data_dir = path( pandoc->data_dir, "attr2style" );
    
    my @dirs =  (cwd, $a2s_dir, $data_dir);
    # ddp @dirs;
    @dirs = grep { $_->is_dir } @dirs;
    # ddp @dirs;
    
    my $yaml_files = $meta->value( 'attr2style_files' );
    
    unless ( $yaml_files ) {
        my ( $file_file ) = grep { $_->exists } map {
            ;
            $_->child( "attr2style-files.yaml" ), $_->child( "attr2style_files.yaml" )
        } cwd, $a2s_dir;
        if ( $file_file ) {
            $file_file->is_file or _error "Not a file: $file_file";
            $yaml_files = try { LoadFile( "$file_file" ) }
            catch { _error "Error loading YAML file '$file_file':\n$_" };
            'ARRAY' eq uc ref $yaml_files
              or _error "Expected YAML file to contain a list: $file_file";
        }
        else {
            my ( $default )
              = grep { $_->exists } map { ; $_->child( "attr2style.yaml" ) } @dirs;
            if ( $default ) {
                $default->is_file or _error "Not a file: $default";
                $yaml_files = $default;
            }
        }
    }
    $yaml_files = _to_aref $yaml_files;
    
    if ( @$yaml_files ) {
        for my $fn ( @$yaml_files ) {
            $fn // next;
            my $file = path( $fn );
            my @paths
              = $file->is_absolute
              ? $file
              : ( $file, map { ; $_->child( $file ) } @dirs );
            ( $file ) = grep { $_->is_file } @paths;
            $file or _error "File not found or not a file: $fn";
            my $hash = try { LoadFile( "$file" ) }
            catch { _error "Error loading YAML file '$file':\n$_" };
            'HASH' eq uc ref $hash
                or _error "Expected YAML file to contain a mapping at the top level: $file";
            $file = $hash;
        }
        my $listify_and_merge = sub { 
            my @items = grep { defined $_ } map {; @{_to_aref $_} } @_; 
            return @items ? \@items : undef; 
        };
        my $behavior = {
            'SCALAR' => {
                'SCALAR' => $listify_and_merge,    #
                'ARRAY'  => $listify_and_merge,    #
                'HASH'   => $listify_and_merge,    #
            },
            'ARRAY' => {
                'SCALAR' => $listify_and_merge,    #
                'ARRAY'  => $listify_and_merge,    #
                'HASH'   => $listify_and_merge,    #
            },
            'HASH' => {
                'SCALAR' => $listify_and_merge,             #
                'ARRAY'  => $listify_and_merge,             #
                'HASH'   => sub { _merge_hashes( @_ ) },    #
            },
        };
        Hash::Merge::specify_behavior($behavior, 'ATTR2STYLE');
        my $hash_merge = Hash::Merge->new('ATTR2STYLE');
        my $merged = shift @$yaml_files;
        for my $hash ( @$yaml_files, $config  ) {
            $merged = $hash_merge->merge($merged, $hash );
        }
        $config = $merged;
    }
}
    
# keys in the strinterp config and the _to_href values for each
my %strinterp_hash = (
    opts => +{ default => 'undef_value', to_key => 0 },
    vars => +{ default => 1,             to_key => 1 },
);
my %strinterp;

sub update_strinterp {
    my %arg = @_;
    $arg{config_prefix}    //= '$strinterp_';
    $arg{strinterp_prefix} //= 'strinterp_';
    $arg{config_prefix}    ||= "";
    $arg{strinterp_prefix} ||= "";
  KEY:
    for my $key ( keys %strinterp_hash ) {
      VAL:
        for
          my $strinterp ( $arg{strinterp}{ $arg{strinterp_prefix} . $key } //= +{} )
        {    # get alias
            next KEY unless ref $strinterp;
            if ( $arg{env} ) {
                $strinterp = $meta->value( "attr2style_strinterp_$key" )
                  // $ENV{"\UPANDOC_CLASS2STYLE_STRINTERP_$key"} // +{};
            }
            for my $config ( $arg{config}->{ $arg{config_prefix} . $key } //= +{} ) {
                for my $data ( $strinterp, $config ) {
                    my $hash = $strinterp_hash{$key};
                    next if blessed $data;
                    $data = _to_href $data, $hash->{default}, to_key => $hash->{to_key};
                    $data = Hash::MultiValue->new( %$data );
                }
                $config->each( sub { $strinterp->add( @_ ) } );
            }
        }
    }
}

update_strinterp(
    strinterp        => \%strinterp,
    strinterp_prefix => 0,
    config           => $config,
    env              => 1
);

$out_format = $meta->value( 'attr2style_as_format' )
  // $ENV{PANDOC_ATTR2STYLE_AS_FORMAT} // $out_format;
$config = $config->{$out_format};

unless ( $config ) {
    print $json;
    exit 0;
}

unless ( 'HASH' eq ref $config ) {
    $config = +{ class => $config };
}

my $raw_format = $config->{'$raw_format'} // $out_format;

my $to_latex = 'latex' eq $out_format;
my $to_docx  = 'docx' eq $out_format;
my $to_html  = 'html' eq $raw_format;

my $block_suffix = $meta->value( 'attr2style_block_suffix' )
  // $config->{'$block_suffix'} // $ENV{PANDOC_BLOCK_SUFFIX} // "";

update_strinterp(
    strinterp        => \%strinterp,
    strinterp_prefix => 0,
    config           => $config,
    env              => 0
);

my(%style_def, %header_include, @header_includes);

STYLE_DEFS: {
    my $additive = $meta->value('attr2style_additive') // $ENV{PANDOC_ATTR2STYLE_ADDITIVE} // 0;
    my %seen;
    my $keys = [ map { ; 'strinterp_' . $_ } keys %strinterp_hash ];
    for my $include_key ( qw[ $header-includes $header_includes ] ) {
        if ( my $includes = delete $config->{$include_key} ) {
            $includes = _to_aref $includes;
            for my $include ( @$includes ) {
                push @header_includes, MetaBlocks [RawBlock $raw_format => $include];
            }
        }
    }
    my $definitions = $config->{'$styles'} // $config;
    'HASH' eq ref $definitions
      or _error "Expected \$styles to be mapping in attr2style metadata";
    while ( my ( $attr, $configs ) = each %$definitions ) {
        $configs = _to_aref $configs;
        for my $defs ( @$configs ) {
            $defs = _to_href $defs, undef, to_key => 1 unless 'Hash::MultiValue' eq (blessed($defs) // "");
            while ( my ( $val, $def ) = each %$defs ) {
                #  if ( $seen{$attr}{$val}++ ) {
                #      _error qq{Duplicate entry for $attr="$val" in attr2style};
                # }
                $def //= $val;
                if ( 'HASH' eq ref $def ) {
                    $def->{'custom-style'} //= $def->{custom_style} if $to_docx;
                    update_strinterp(
                        env           => 0,
                        strinterp     => $def,
                        config        => \%strinterp,
                        config_prefix => 0,
                        keys          => $keys
                    );
                    delete $def->{__includes__};
                    for my $include_key ( qw[ header-includes header_includes ] ) {
                        if ( my $includes = delete $def->{$include_key} ) {
                            my $blocks = $def->{__includes__} //= [];
                            $includes = _to_aref $includes;
                            for my $include ( @$includes ) {
                                 push @$blocks, MetaBlocks [RawBlock $raw_format => $include];
                            }
                        }
                    }
                    if ( my $includes = $def->{__includes__} ) {
                        $header_include{$includes} = $includes;
                    }
                }
                if ( $additive ) {
                    $style_def{$attr}{$val} //= [];
                }
                else {
                    $style_def{$attr}{$val} = [];
                }
                push @{ $style_def{$attr}{$val} }, $def;
            }
        }
    }
}

unless ( keys %style_def ) {
    print $json;
    exit 0;
}

my $action
  = action $to_docx
  ? ( 'Span|Div' => \&attr2docx )
  : ( 'Span|Div|Code|CodeBlock|Link' => \&attr2style );

# my $action = action \%actions;

# Allow applying the action recursively
$doc->transform( $action, $action );

if ( @header_includes ) {
    my $hi = $meta->{'header-includes'} //= MetaList [];
    unless ( eval { 'MetaList' eq $hi->name } ) {
        $hi = MetaList [ $hi ]; # Hope it works!
    }
    my $includes = $hi->content;
    push @$includes, @header_includes;
}

print $doc->to_json;

sub _strinterp {
    my $result = strinterp( @_ );
    $result =~ s!\\(\\)(?=[{}])|\\([{}])!$+!g;
    return $result;
}

sub fix_attributes {
    my ( $attrs, $style ) = @_;
    if ( $style->{clear_attr} // $style->{clear_attrs} ) {
        $attrs->clear;
    }
    elsif ( $style->{rem_attr} ) {
        for my $name ( @{ _to_aref $style->{rem_attr}, clone => 0 } ) {
            $name
              = _strinterp( $name, $style->{strinterp_vars},
                $style->{strinterp_opts} )
              if $name =~ /\$/;
            $attrs->remove( $name ) if $name;
        }
    }
    if ( my $new_attr = $style->{attr} ) {
        $new_attr = _to_href $new_attr, $new_attr, clone => 0;
        for my $name ( sort keys %$new_attr ) {
            my $val = $new_attr->{$name} =~ /\$/
              ? _strinterp(
                $new_attr->{$name},
                $style->{strinterp_vars},
                $style->{strinterp_opts}
              )
              : $new_attr->{$name};
            $attrs->set( $name => $val );
        }
    }
}

sub get_strinterp {
    my($key, $style) = @_;
    return blessed( $style->{"strinterp_$key"} )
    ? $style->{"strinterp_$key"}->clone
    : $strinterp{$key}->clone;
}

sub set_props {
    my($kv, $prop) = @_;
    if ( exists $kv->{class} ) {
        $prop->{_classes} = join q{ }, $kv->get_all('class');
        my @classes = $prop->{_classes} =~ m{\S+}g;
        $kv->set(class => @classes);
    }
  PROP:
    while ( my ( $p, $v ) = each %$prop ) {
      ## set the prop in $kv only if it's true,
        #  since strinterp tests definedness.
        $v || next PROP;
        $kv->set( $p, $v );
    }
}

sub attr2docx {
    my ( $elem, $action ) = @_;
    transform $elem->content, $action, $action;
    my %prop;
    my $type     = $prop{_name}     = $elem->name;
    my $is_block = $prop{_is_block} = $elem->is_block;
    my $kv       = $elem->keyvals;
    my $attrs    = $kv->clone;
    set_props( $kv, \%prop );
    # if ( exists $kv->{class} ) {
    #     $prop{_classes} = join q{ }, $kv->get_all('class');
    #     my @classes = $prop{_classes} =~ m{\S+}g;
    #     $kv->set(class => @classes);
    # }
  # PROP:
    # while ( my ( $p, $v ) = each %prop ) {
    #   ## set the prop in $kv only if it's true,
    #     #  since strinterp tests definedness.
    #     $v || next PROP;
    #     $kv->set( $p, $v );
    # }
    my $styles = get_styles( $elem, $kv, $is_block ) // return $elem;
  ## We do everything below to ensure the last non-false custom-style wins
    my @custom_styles = grep { defined $_ } $attrs->{'custom-style'};
  STYLE:
    for my $style ( @$styles ) {
        local $style->{strinterp_opts} = get_strinterp( opts => $style );
        local $style->{strinterp_vars} = get_strinterp( vars => $style );
        $kv->each( sub { $style->{strinterp_vars}->add( @_ ) } );
        fix_attributes( $attrs, $style );
        if ( defined $style->{'custom-style'} ) {
            push @custom_styles, $style->{'custom-style'} =~ /\$/
              ? _strinterp(
                $style->{'custom-style'},
                $style->{strinterp_vars},
                $style->{strinterp_opts}
              )
              : $style->{'custom-style'};
        }
    }
    $attrs->remove( 'custom-style' );
    if ( @custom_styles ) {
        push @custom_styles, ucfirst $block_suffix if $is_block;
        my $cs = join "", map {; $_ =~ s/[\W_]+(\pL?)/\u$1/g; ucfirst $_; } @custom_styles;
        $attrs->set( 'custom-style' => $cs );
    }
    $elem->keyvals( $attrs );
    return $elem;
}

sub attr2style {
    state $mk_raw = [ \&RawInline, \&RawBlock ];    # As per !!$is_block
    state $join_raw_for = [ "", "\n", ];            # As per !!$is_block
    my ( $elem, $action ) = @_;
    my %prop;
    my $type    = $prop{_name}    = $elem->name;
    my $is_code = $prop{_is_code} = $type =~ /Code/;
    transform $elem->content, $action, $action unless $is_code;
    my $is_block = $prop{_is_block} = $elem->is_block;
    my $kv       = $elem->keyvals;
    my $attrs    = $kv->clone;
    set_props( $kv, \%prop );
  # PROP:
  #   while ( my ( $p, $v ) = each %prop ) {
  #       $v || next PROP;
  #       $kv->set( $p, $v );
  #   }
    my $styles = get_styles( $elem, $kv, $is_block ) // return $elem;
    my %arounds = ( before => ( \my @before ), after => ( \my @after ), );
    my $raw;
    my $join_raw;
    my $rets      = [$elem];
    my $have_elem = 1;
  STYLE:
    for my $style ( @$styles ) {
        # Apply custom header-includes, but only once!
        if ( my $includes = delete $header_include{$style->{__includes__} // ""} ) {
            push @header_includes, @$includes;
        }
        local $style->{strinterp_opts} = get_strinterp( opts => $style );
        local $style->{strinterp_vars} = get_strinterp( vars => $style );
        $kv->each( sub { $style->{strinterp_vars}->add( @_ ) } );
        if ( $style->{raw} ) {
            $raw ||= $style->{raw} =~ /\$/
              ? _strinterp(
                $style->{raw},
                $style->{strinterp_vars},
                $style->{strinterp_opts}
              )
              : $style->{raw};
            $join_raw //= $style->{join_raw} // $join_raw_for->[$is_block];
        }
        for my $around ( qw[ before after ] ) {
            my $code = $style->{$around} // next;
            if ( $code =~ m{ \$ }x ) {
                $code = _strinterp(
                    $code,
                    $style->{strinterp_vars},
                    $style->{strinterp_opts}
                );
            }
            push @{ $arounds{$around} }, $code;
        }
        if ( !$is_code && $have_elem && $style->{strip} ) {
            my $strip = $style->{strip} =~ /\$/
              ? _strinterp(
                $style->{strip},
                $style->{strinterp_vars},
                $style->{strinterp_opts}
              )
              : $style->{strip};
            if ( $strip ) {
                $rets      = $elem->content;
                $have_elem = 0;
            }
        }
        next STYLE if $raw or !$have_elem;
        fix_attributes( $attrs, $style );
    }
    @after = reverse @after;
    # ddp %arounds;
    if ( $raw ) {
        my $code = join $join_raw, @before, $elem->string, @after;
        return $mk_raw->[$is_block]->( $raw_format => $code );
    }
  ## else
    $elem->keyvals( $attrs ) if $have_elem;
    for my $around ( qw[ before after ] ) {
        @{ $arounds{$around} } or next;    # skip if no items
        my $code = join $join_raw_for->[$is_block], @{ $arounds{$around} };
        @{ $arounds{$around} } = $mk_raw->[$is_block]->( $raw_format => $code );
    }
    return [ @before, @$rets, @after ];
}

sub get_styles {
    no warnings qw[ uninitialized numeric ];
    state $str2href = +{
        latex => [
            sub {                          # !$is_block
                return $_[0] if $_[0] =~ /\PL|^$/;
                return +{ before => "\\$_[0]\{", after => '}' };
            },
            sub {                          # !!$is_block
                return $_[0] if $_[0] =~ /\PL|^$/;
                return +{
                    before => "\\begin{$_[0]$block_suffix}",
                    after  => "\\end{$_[0]$block_suffix}"
                };
            },
        ],
        html => [
            sub {                          # !$is_block
                return $_[0] if $_[0] =~ /[^-.\w]|^$/;
                return +{ before => qq(<span class="$_[0]">), after => '</span>' };
            },
            sub {                          # !!$is_block
                return $_[0] if $_[0] =~ /[^-.\w]|^$/;
                return +{ before => qq(<div class="$_[0]">), after => '</div>' };
            }
        ],
        docx => [
            sub { return ref( $_[0] ) ? $_[0] : +{ 'custom-style' => $_[0] } },
            sub {
                return
                  ref( $_[0] )
                  ? $_[0]
                  : +{ 'custom-style' => $_[0] . $block_suffix };
            },
        ],
    };
    state $mk_after = +{
        latex => [
            #<<<
            sub { $_[1] =~ /\{$/ ? '}' : undef },                            
            # !$is_block
            sub { $_[1] =~ /\\begin\{/ ? "\\end{$_[0]$block_suffix}" : undef },
            # !!$is_block
            #>>>
        ],
    };
    my ( $elem, $kv, $is_block ) = @_;
    my ( @styles, %seen );
    $kv->each(
        sub {
            my ( $attr, $val ) = @_;
            my @defs = grep { defined $_ and !$seen{$_}++ } 
              $style_def{$attr}{$val}, 
              $style_def{$attr}{'*'},
              $style_def{'*'}{$val},
              $style_def{'$attr'}{$attr};
            @defs or return;
           #d# return if 
            push @styles, map {; [ $attr, $val, $_ ] } @defs;
        }
    );
    return unless @styles;
    my @rets;
    for my $style ( @styles ) {
        my ( $attr, $val, $defs ) = @$style;
        for my $def ( @$defs ) {
            if ( my $code = $str2href->{$raw_format}[$is_block]
                // $str2href->{$raw_format}[$is_block] )
            {
                $def = $code->( $def );
            }
          ## Work around bug where block scalar becomes array
            if ( 'HASH' eq ref $def ) {
              AROUND:
                for my $around ( @{$def}{qw[ before after ]} ) {
                    next AROUND unless 'ARRAY' eq ref $around;
                    $around = join "", @$around;
                }
            }
            my $ret = _to_href $def, $to_docx ? 'custom-style' : 'before';
            if ( my $code = $mk_after->{$out_format}[$is_block]
                // $mk_after->{$raw_format}[$is_block] )
            {
                $ret->{after} //= $code->( $val, $ret->{before} );
            }
          ##if ( defined $ret->{strinterp_opts} ) {
            # $ret->{strinterp_opts} = _to_href $ret->{strinterp_opts}, 'undef_value';
            # }
            if ( defined $ret->{attr} ) {
                my $attr = $ret->{attr};
                unless ( ref $attr ) {
                    $attr .= $block_suffix if $is_block;
                }
                $ret->{attr} = _to_href $attr, $to_docx ? 'custom-style' : 'class';
            }
            push @rets, $ret;
        }
    }
    return \@rets;
}

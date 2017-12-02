# Installing

-   [Make pandoc find (any) filters][]
-   [Installing perl and Perl modules][]
    -   [Installing modules][]
    -   [Installing perl][]

  [Installing]: #installing
  [Make pandoc find (any) filters]: #make-pandoc-find-any-filters
  [Installing perl and Perl modules]: #installing-perl-and-perl-modules
  [Installing modules]: #installing-modules
  [Installing perl]: #installing-perl

## Make pandoc find (any) filters

This is only a brief guide on making Pandoc filters available from
anywhere on your system by running a command of the form

    pandoc -F pandoc-filter.pl ...

(I will assume for these examples that the filename of the filter script
is `pandoc-filter.pl`. It can of course be written in any language/have
any filename extension which Pandoc recognises.)

To quote the [Pandoc manual][]:

  [Pandoc manual]: https://github.com/jgm/pandoc/blob/ecfb5a08381dcfd3eb1c586ceb6cbc3aea96a7d5/MANUAL.txt#L475

> In order of preference, pandoc will look for filters in
>
> 1.  a specified full or relative path (executable or non-executable)
>
> 2.  `$DATADIR/filters` (executable or non-executable) where `$DATADIR`
>     is the user data directory (see `--data-dir`, above).
>
> 3.  `$PATH` (executable only)
>
For those who are new to the command line 2. is probably the easiest
option — it certainly is on Windows. What follows is a short guide to
how to set it up and how it works.

The wording of the manual may make it seem like there exists an
environment variable `DATADIR`; this is not the case, unfortunately (or
fortunately, since *if* it existed it should be called something like
`PANDOC_DATADIR`!) The first thing you must do is thus to find out where
your Pandoc data directory (aka folder) is, or should be if it doesn’t
already exist. According to the [Pandoc manual][1]:

  [1]: https://github.com/jgm/pandoc/blob/ecfb5a08381dcfd3eb1c586ceb6cbc3aea96a7d5/MANUAL.txt#L347

> This is, in UNIX:
>
>     $HOME/.pandoc
>
> in Windows XP:
>
>     C:\Documents And Settings\USERNAME\Application Data\pandoc
>
> and in Windows Vista or later:
>
>     C:\Users\USERNAME\AppData\Roaming\pandoc

Note that “UNIX” here includes Linux and MacOS.

`USERNAME` does *not* mean that you should type <!-- Caps Lock USERNAME -->
<kbd>CapsLock</kbd><kbd>U</kbd><kbd>S</kbd><kbd>E</kbd><kbd>R</kbd><kbd>N</kbd><kbd>A</kbd><kbd>M</kbd><kbd>E</kbd>,
but that you should substitute the name of your user account for it.

To find out where Pandoc expects to find your data directory run the
following command:

    pandoc --version

This will make pandoc print a message which includes a line containing a
path similar to those in the quote from the manual. On my current
(Linux) system this line is:

    Default user data directory: /home/benct/.pandoc

This means that my `filters` directory should be
`/home/benct/.pandoc/filters`, or more generally a subdirectory of the
Default user data directory called `filters`.

This is, on Unix or Linux:

    /home/USERNAME/.pandoc/filters

on Mac:

    /Users/USERNAME/.pandoc/filters

on Windows XP:

    C:\Documents And Settings\USERNAME\Application Data\pandoc\filters

and on Windows Vista or later:

    C:\Users\USERNAME\AppData\Roaming\pandoc\filters

To create this folder on Linux or Mac run this command:

    mkdir -p ~/.pandoc/filters

on Windows XP:

    md C:\Documents And Settings\USERNAME\Application Data\pandoc\filters

and on Windows Vista or later:

    md C:\Users\USERNAME\AppData\Roaming\pandoc\filters

(Note: I haven’t used Windows regularly in the last decade, and my
memory does not serve. The commands above are based on what I’ve been
able to find with Google.)

Now and in the future you can put any new pandoc filters in the folder
you just created and they should Just Work. However note that pandoc
isn’t (yet) smart enough to also look in subdirectories of this
directory, so if your filter is located at for example
`DATADIR/filters/SUBDIR/pandoc-filter.pl` you will have to specify a
path relative to `DATADIR/filters`:

    pandoc -F SUBDIR/pandoc-filter.pl ...

This is not too much of a hassle if you keep the names of your
subdirectories short and can remember where each filter lives. That is
why this repository eventually will contain all my filters. You can then
`cd` to `DATADIR/filters` and run this command:

    git clone https://github.com/bpj/bpj-pandoc-scripts.git bpj

and then use any of my filters with

    pandoc -F bpj/pandoc-filter.pl ...

## Installing perl and Perl modules

### Installing modules

If you already have perl (on Windows: Strawberry Perl) installed run
these commands on the command line to install all [CPAN][] dependencies
of any of the programs in this repository:

  [CPAN]: http://www.cpan.org/misc/cpan-faq.html#What_is_CPAN

    cpan App::cpanminus
    cpanm Perl::PrereqScanner
    scan-perl-prereqs script-name.pl | cpanm

In the last line you need to replace `script-name.pl` with the name of
the program, possibly including the path to the program, either relative
to the directory (folder) you are in, or an absolute path. You may also
need to run with `sudo` (on Linux or Mac) or as administrator (on
Windows).

### Installing perl

The programs in this repository require [perl][] (minimum version usually
5.10.1 aka `5.010001`) and the Perl modules listed under *PREREQUISITES*
or *PREREQUISITES → CPAN* in the documentation of each program to
function. If you haven’t used Perl before information on how to
get/install perl and/or Perl modules can be found at the URLS below,
which lead to the official information on these topics.

  [perl]: https://www.perl.org/about.html "Official info on Perl"

Don’t worry! If your operating system is Linux or Mac you probably
already have a new enough version of perl installed. If you don’t or if
your operating system is Windows it is easy to install a recent version,
and once you have perl installed installing modules is very easy. Just
follow the instructions linked to below.

Getting perl: <https://www.perl.org/get.html>

(For Windows I recommend Strawberry Perl as module installation is
easier there.)

Installing Perl modules: <http://www.cpan.org/modules/INSTALL.html>

(Note: According to convention the spelling “perl” with a small *p*
refers to the interpreter program (since `perl` is the command to run it
from the command line), while the spelling “Perl” with a capital *P*
refers to the language, or the language and the interpreter taken
together. The spelling ~~PERL~~ is not used in the Perl community; thus
it generally betrays ignorance.)

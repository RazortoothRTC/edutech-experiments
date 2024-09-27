# Overview

This is a 2010 thought experiment created on behalf of Marvell Semiconductor.  The initial concept goal was to create a chat application that can be used in a web html5 based classroom environment.  The goal was to make this accessible from a low cost sub $150 server.

The first version was designed using Perl (5?) of all things.  Not sure the reason why, but possibly there was some sample code that performed 85% of what was needed in this application.

The timing of this development was right around the time Node.js was in an early stage, and Perl was abandoned, monk clothes hung on the shelf in favor of Node.js.

It is being revisited as an interesting concept in Perl, for simplicity sake, the perl implementation was quite easy to create, however, maybe a bit harder to understand.  Also, the code was never to my knowledge checked in anywhere.  That is a bit of a problem.  I hate to lose historical code.  Because this software was never intended for a release, it is demoware and will be open sourced.

It looks like Tatsumaki is no longer maintained but should still be installable.

## Architecture

This uses a Plack based framework.  TODO: Add some details

## Software

- https://metacpan.org/pod/Tatsumaki
- Perl 5
- cpanm
- install tatsumaki into root.  Note, this did not install on a mac with apple silicon, so stick with a linux (arch or ubuntu)

## Development

TODO: locate missing code and content

- /templates
- /static
- /contentrepo

## Running

- launch: perl app.psgi
- from a service, use plackup (TODO: document how)
- from a browser: http://localhost:5000/class/foo (where foo is any ascii string) to join a classroom

#!/usr/bin/perl

use strict;
use warnings;
use Tatsumaki;
use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::HTTPClient;
use Time::HiRes;

#
# Epoch EDU
#
package ChatPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

use Tatsumaki::MessageQueue;

sub get {
     my($self, $channel) = @_;
     my $mq = Tatsumaki::MessageQueue->instance($channel);
     my $client_id = $self->request->param('client_id')
         or Tatsumaki::Error::HTTP->throw(500, "'client_id' needed");
     $client_id = rand(1) if $client_id eq 'dummy'; # for benchmarking 
stuff
     $mq->poll_once($client_id, sub { $self->on_new_event(@_) });
}

sub on_new_event {
     my($self, @events) = @_;
     $self->write(\@events);
     $self->finish;
}

package ChatMultipartPollHandler;
use base qw(Tatsumaki::Handler);
__PACKAGE__->asynchronous(1);

sub get {
     my($self, $channel) = @_;

     my $client_id = $self->request->param('client_id') || rand(1);

     $self->multipart_xhr_push(1);

     my $mq = Tatsumaki::MessageQueue->instance($channel);
     $mq->poll($client_id, sub {
         my @events = @_;
         for my $event (@events) {
             $self->stream_write($event);
         }
     });
}

package ChatPostHandler;
use base qw(Tatsumaki::Handler);
use HTML::Entities;
use Encode;

sub post {
     my($self, $channel) = @_;

        # XXX This section can be refactored into a single subroutine, but 
instead of reading off the request, pass in
        # data as args
     my $v = $self->request->params;
     my $html = $self->format_message($v->{text});
     my $mq = Tatsumaki::MessageQueue->instance($channel);
     $mq->publish({
         type => "message", html => $html, ident => $v->{ident},
         avatar => $v->{avatar}, name => $v->{name},
         address => $self->request->address,
         time => scalar Time::HiRes::gettimeofday,
     });
     $self->write({ success => 1 });
}

sub format_message {
     my($self, $text) = @_;
     $text =~ s{ (https?://\S+) | ([&<>"']+) }
               { $1 ? do { my $url = HTML::Entities::encode($1); qq(<a 
target="_blank" href="$url">$url</a>) } :
                 $2 ? HTML::Entities::encode($2) : '' }egx;
     $text;
}

package ChatRoomHandler;
use base qw(Tatsumaki::Handler);

sub get {
     my($self, $channel) = @_;
     $self->render('epoch-student.html');
}

package EndSessionHandler;
use base qw(Tatsumaki::Handler);
use Digest::MD5 qw(md5_hex);

__PACKAGE__->asynchronous(1);

sub get {
        my($self, $channel) = @_;
        my $client_id = $self->request->param("ident");

        my $mq = Tatsumaki::MessageQueue->instance($channel);

        # We need to loop and do this for all clients, not just
        my $client = $mq->clients->{$client_id};
        my @events = $mq->backlog_events;
     $mq->flush_events($client_id, @events) if @events;
     # if (@{ $client->{buffer}}) {
        #       $mq->flush_events($client_id, @{ $client->{buffer} });
        # }
        # $self->write({ success => 1 });

        # send up an empty message with a hash sign to send directives
        my $html = ChatPostHandler->format_message("");
        $mq = Tatsumaki::MessageQueue->instance($channel);
        my $avatar = '';
     $mq->publish({
         type => "message", html => $html, ident => $client_id,
         avatar => $avatar, name => '#killsession',
         address => $self->request->address,
         time => scalar Time::HiRes::gettimeofday,
     });

        $self->finish;
}

package StartSessionHandler;
use base qw(Tatsumaki::Handler);
use Digest::MD5 qw(md5_hex);

__PACKAGE__->asynchronous(1);

sub get {
        my($self, $channel) = @_;
        my $ident = $self->request->param("ident");
        my $serverhost = $self->request->headers->header('Host');
        my $client = Tatsumaki::HTTPClient->new;
        # Get the list of crdb entries
        $client->get("http://" . $serverhost . "/crdb?output=json", sub 
{ $self->on_response(@_, $channel, $ident) });
}

sub on_response {
     my($self, $res, $channel, $ident) = @_;
     if ($res->is_error) {
         Tatsumaki::Error::HTTP->throw(500, $res->status_line);
     }

     my $json = JSON::decode_json($res->content);


     $self->write("Fetched " . $json->{totalResults} . " Classroom 
Contents.\n");
        $self->write("channel = " . $channel . "\n");
        my $contents = $json->{contents};
        my @contentslist = split(',', $contents);


        for my $content (@contentslist) {
                # XXX This section can be refactored into a single subroutine
                my @name = split('@',$ident);
                my $html = ChatPostHandler->format_message($content);
                my $mq = Tatsumaki::MessageQueue->instance($channel);
                my $avatar = 'http://www.gravatar.com/avatar/' . md5_hex($ident);
            $mq->publish({
                type => "message", html => $html, ident => $ident,
                avatar => $avatar, name => $name[0],
                address => $self->request->address,
                time => scalar Time::HiRes::gettimeofday,
            });
        }
        $self->finish;
}

package ClassRoomHandler;
use base qw(Tatsumaki::Handler);

sub get {
     my($self, $channel) = @_;
     $self->render('epoch-teacher.html');
}

package ContentRepoDBHandler;
use base qw(Tatsumaki::Handler);
use JSON;
use Plack::App::Directory;
use Plack::Request;
use Plack::Util;
use URI::Escape;
# use Plack::App::File;

#
# JSON Format
#
# {"ContentSet":
#       "totalResultsAvailable":"<INT>",
#       "totalResultsReturned":"<INT>",
#       "Content":[
#       {"Title":"<STRING>",
#        "Url":"<STRING>",
#        "Tags":"<CSV>",
#        "MimeType":"<STRING>",
#        "SourceURI":"<STRING">,
#        "License":"<STRING>",
#       }
#       ]
# "}
#
sub get {
        my $self = shift;
        my $pathinfo = $self->request->path_info;
        my $serverhost = $self->request->headers->header('Host');
        my @crserverhost = split(':',$serverhost);
        my $output = $self->request->param("output");
        my @contentlist = ();
        my $contentliststr = '';

        if ($output eq 'json') {
                $self->response->content_type('application/json');
        } else {
                $self->response->content_type('text/plain');
        }
        opendir(DIR, "./contentrepo");

        while (my $file = readdir(DIR)) {
                # Use a regular expression to ignore files beginning with a period
                next if ($file =~ m/^\./);
                push(@contentlist, 'http://' . $crserverhost[0] .":5001" . "/" . 
uri_escape("$file"));
                # $self->write($pathinfo . "/" . uri_escape("$file") . "\n");
        }
        closedir(DIR);

        foreach my $index (1 .. $#contentlist) {
                my $sep = ',';
                if ($index eq @contentlist - 1) {
                        $sep = '';
                }
                $contentliststr = $contentliststr . $contentlist[$index] . $sep;
        }
        my $contentresults = {
                totalResults => @contentlist . "",
                contents => $contentliststr,
        };

        my $json_out = to_json($contentresults);


        $self->write($json_out . "\n");
        $self->finish;
}

package main;
use File::Basename;

my $chat_re = '[\w\.\-]+';
my $app = Tatsumaki::Application->new([
     "/class/($chat_re)/poll" => 'ChatPollHandler',
     "/class/($chat_re)/mxhrpoll" => 'ChatMultipartPollHandler',
     "/class/($chat_re)/post" => 'ChatPostHandler',
     "/class/($chat_re)" => 'ChatRoomHandler',
     "/classmoderator/($chat_re)" => 'ClassRoomHandler',
        "/startsession/($chat_re)" => 'StartSessionHandler',
        "/endsession/($chat_re)" => 'EndSessionHandler',
        "/crdb" => 'ContentRepoDBHandler',
]);

$app->template_path(dirname(__FILE__) . "/templates");
$app->static_path(dirname(__FILE__) . "/static");

#
# Epoch Content Repo Server
#

use HTTP::Server::PSGI;
use Plack::App::Directory;

my $server = HTTP::Server::PSGI->new(
        host => "127.0.0.1",
        port => 5001,
        timeout => 120,
);
my $app2 = Plack::App::Directory->new({ root => "./contentrepo" })->to_app;


if (__FILE__ eq $0) {
     require Tatsumaki::Server;
     Tatsumaki::Server->new(port => 5000)->run($app);
        $server->run($app2); # Hmm, need to figure out how to do this....
} else {
     return $app;
}



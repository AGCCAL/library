#!/usr/bin/perl -w
use strict;
use warnings;

use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Email::MIME;
use Try::Tiny;

use Garden;

my $garden = Garden->new;
my $dbh = $garden->database;
my $caml = $garden->caml;

my $sth = $dbh->prepare("select r.user_id, r.token, u.real_name, u.email from recovery r, user u where u.user_id = r.user_id and r.state = 0 order by r.expiry;");
$sth->execute;

my @successful_user_ids;

while (my $row = $sth->fetch)
{
  my ($user_id, $token, $real_name, $to) = @{$row};
#  print "$user_id ($real_name, $to) -> $token\n";
  
  my $recovery;
  $recovery->{token} = $token;
  $recovery->{real_name} = $real_name;
  
  my $html = $caml->render_file('recovery_email_html', $recovery);
  my $plain = $caml->render_file('recovery_email_plain', $recovery);
  
  my @parts = (Email::MIME->create(attributes => {content_type => "text/plain", encoding => "quoted-printable", charset => "UTF-8"}, body_str => $plain),
               Email::MIME->create(attributes => {content_type => "text/html", encoding => "quoted-printable", charset => "UTF-8"}, body_str => $html));
  
  my $email = Email::MIME->create(header_str => [From => "admin\@assessmentgarden.org",
                                                 To => $to,
                                                 Cc => 'joan.bassett@haskayne.ucalgary.ca',
                                                 Subject=> "Assessment Garden password reset"],
                                  parts => [@parts]);
  
  $email->content_type_set("multipart/alternative");
  
  try
  {
    sendmail($email);
    push (@successful_user_ids, $user_id);
  }
  
}

my $sql = "update recovery set state = 1 where user_id in (" . join (",",@successful_user_ids) . ");";

$sth = $dbh->prepare($sql)->execute;

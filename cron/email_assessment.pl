#!/usr/bin/perl -w
use strict;
use warnings;

use IO::All;
use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Try::Tiny;

use Garden;
use Garden::Assessment;

my $garden = Garden->new;
my $dbh = $garden->database;
my $caml = $garden->caml;

my $sth = $dbh->prepare("select i.instance_id, i.assessment_id, i.completion_date, a.name, u.real_name, u.email from emailable_assessment e, user u, assessment_instance i, assessment a where i.user_id = u.user_id and e.instance_id = i.instance_id and i.assessment_id = a.assessment_id limit 1;");
$sth->execute;

my @successful_instance_ids;

while (my $row = $sth->fetch)
{
  my ($instance_id, $assessment_id, $completion_date, $assessment_name, $real_name, $to) = @{$row};
  my $assessment = Garden::Assessment->new('decode-content'=>0);
  my $summary = $assessment->generate_summary($instance_id, $assessment_id);
  my $stuff;

  $stuff->{real_name} = $real_name;
  $stuff->{assessment_name} = $assessment_name;
  $stuff->{summary} = $summary;
  $stuff->{completion_date} = $completion_date;
  $stuff->{instance_id} = $instance_id;
  $stuff->{link} = "https://www.assessmentgarden.org/pdf?instance_id=$instance_id";
  
  
  my $html = $caml->render_file('assessment_summary_email_html', $stuff);
  utf8::encode($html);
  open HTML,">/tmp/$instance_id.html" or die "couldn't open HTML: $!";
  print HTML $html;
  close HTML;
  system("xvfb-run wkhtmltopdf --page-size Letter -T 0 -L 0 -R 0 -B 0 -q /tmp/$instance_id.html /tmp/$instance_id.pdf");

  my $text = $caml->render_file('assessment_summary_email_text', $stuff);

  my $email = Email::Simple->create(body => $text);
  $email->header_set("From", 'admin@assessmentgarden.org');
  $email->header_set("To", $to);
  $email->header_set("Subject", $assessment_name);

  try
  {
    sendmail($email);

    my $dsth = $dbh->prepare("delete from emailable_assessment where instance_id = ?;");
    $dsth->bind_param(1,$instance_id);
    $dsth->execute;
  }
}


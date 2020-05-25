package MemberView;
use base 'CGI::Application';
use strict;
use warnings;
use DBI;
use DBD::mysql;
use Template::Provider::Encoding;
use Template::Stash::ForceUTF8;
use Template;

sub setup {
  my $self = shift;

  $self->query->charset('UTF-8');
  $self->start_mode('view');
  $self->mode_param('rm');
  $self->run_modes(
    'view' => 'do_view',
    'insert_input' => 'do_input',
    'finish' => 'do_finish'
  );
}

sub do_view {
  my $self = shift;
  my $user = 'test';
  my $passwd = 'test2001';
  my $db = DBI->connect('DBI:mysql:ATMARKIT:localhost', $user, $passwd);
  my $sth = $db->prepare("SELECT * FROM list ORDER BY id ASC");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute() || die($DBI::errstr);
  my @ref;  # これをテンプレートに渡す
  my $r;
  while ($r = $sth->fetchrow_hashref()) {
    push(@ref, $r);
  }

  my $template = Template->new(
    LOAD_TEMPLATES => [ Template::Provider::Encoding->new ],
    STASH => Template::Stash::ForceUTF8->new,
  );
  my $output;

  $template->process(
    'list.html',
    { people => \@ref },
    \$output,
  ) || die $template->error();

  $sth->finish;
  $db->disconnect;

  return $output;
}

sub do_input {
  my $self = shift;
  my $template = Template->new(
    LOAD_TEMPLATES => [ Template::Provider::Encoding->new ],
    STASH => Template::Stash::ForceUTF8->new,
  );
  my $output;
  $template->process(
    'insert_input.html',
    {},
    \$output,
  ) || die $template->error();

  return $output;
}

sub do_finish {
  my $self = shift;
  my $user = 'test';
  my $passwd = 'test2001';

  my $db = DBI->connect('DBI:mysql:ATMARKIT:localhost', $user, $passwd);
  my $cnt = $db->prepare("SELECT * FROM list ORDER BY id ASC")->execute() || die($DBI::errstr)->rows;
  my $nextId = $cnt + 1;
  my $formName = $self->query->param('userName');
  my $formMemo = $self->query->param('memo');
  my $sth = $db->prepare("INSERT INTO list (id, name, memo) VALUES('$nextId', '$formName', '$formMemo')");
  $sth->execute() || die($DBI::errstr);

  my $template = Template->new(
    LOAD_TEMPLATES => [ Template::Provider::Encoding->new ],
    STASH => Template::Stash::ForceUTF8->new,
  );
  my $output;
  $template->process(
    'complete.html',
    {},
    \$output,
  ) || die $template->error();

  # $sth->finish;
  $db->disconnect;

  return $output;
}

1;  # Perlの全てのモジュールの末尾にはこれが必要

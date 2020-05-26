package MemberView;
use base 'CGI::Application';
use strict;
use warnings;
use DBI;
use DBD::mysql;
use Template::Provider::Encoding;
use Template::Stash::ForceUTF8;
use Template;
my ($user, $passwd, $db, $template, $output);

sub setup {
  my $self = shift;
  $user = 'test';
  $passwd = 'test2001';
  $db = DBI->connect('DBI:mysql:ATMARKIT:localhost', $user, $passwd);

  $template = Template->new(
    LOAD_TEMPLATES => [ Template::Provider::Encoding->new ],
    STASH => Template::Stash::ForceUTF8->new,
  );

  $self->query->charset('UTF-8');
  $self->error_mode('error');
  $self->start_mode('view');
  $self->mode_param('rm');
  $self->run_modes(
    'view' => 'do_view',
    'form_input' => 'do_input',
    'input_complete' => 'do_regist',
    'update_item' => 'do_upinput',
    'update_complete' => 'do_update',
    'delete_item' => 'do_delete'
  );
}

sub error {
  my($self, $err) = @_;

  return $err;
}

sub teardown {
  $db->disconnect;
}

sub do_view {
  my $self = shift;
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

  $template->process(
    'list.html',
    { people => \@ref },
    \$output,
  ) || die $template->error();

  return $output;
}

sub do_input {
  my $self = shift;
  $template->process(
    'insert_input.html',
    {},
    \$output,
  ) || print $template->error();

  return $output;
}

sub do_regist {
  my $self = shift;
  my $formName = $self->query->param('userName');
  my $formMemo = $self->query->param('memo');
  my $sth = $db->prepare("INSERT INTO list (name, memo) VALUES('$formName', '$formMemo')");
  $sth->execute() || die($DBI::errstr);

  $template->process(
    'complete.html',
    {},
    \$output,
  ) || print $template->error();

  return $output;
}

sub do_upinput {
  my $self = shift;
  my $updId = $self->query->param('id');
  my $sth = $db->prepare("SELECT * FROM list where id = '$updId'");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute() || die($DBI::errstr);
  my $r = $sth->fetchrow_hashref();

  $template->process(
    'insert_input.html',
    { item => $r },
    \$output,
  ) || print $template->error();

  return $output;
}

sub do_update {
  my $self = shift;
  my $updId = $self->query->param('id');
  my $upName = $self->query->param('userName');
  my $upMemo = $self->query->param('memo');
  $db->do("UPDATE list SET name = '$upName', memo = '$upMemo' WHERE id = '$updId'");

  $template->process(
    'complete.html',
    {},
    \$output,
  ) || print $template->error();

  return $output;
}

sub do_delete {
  my $self = shift;
  my $delId = $self->query->param('id');
  $db->do("DELETE FROM list WHERE id = '$delId'");
  return do_view();
}

1;  # Perlの全てのモジュールの末尾にはこれが必要

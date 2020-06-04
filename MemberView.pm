package MemberView;
use base 'CGI::Application';
use CGI::Application::Plugin::Forward;
use CGI;
use CGI::Cookie;
# use CGI::Carp qw(fatalsToBrowser); #デバック用(開発時以外はコメントアウト)
use strict;
use warnings;
use DBI;
use DBD::mysql;
use Template::Provider::Encoding;
use Template::Stash::ForceUTF8;
use Template;

### 初期化
sub cgiapp_init {
  my $self = shift;
  my $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'test', 'test2001');
  $dbh->{AutoCommit} = 0;
  $dbh->{RaiseError} = 1;
  $self->query->charset('UTF-8');

  $self->param( # アプリケーション変数の設定
    'user' => 'test',
    'passwd' => 'test2001',
    'dbh' => $dbh,
    'template' => Template->new(
      LOAD_TEMPLATES => [ Template::Provider::Encoding->new ],
      STASH => Template::Stash::ForceUTF8->new,
    ),
  );
}

# モード設定
sub setup {
  my $self = shift;

  $self->error_mode('error');
  $self->start_mode('view');
  $self->mode_param('rm');
  $self->run_modes(
    # 'login_input' => 'do_input_login', #ログイン画面表示
    # 'login' => 'do_login', #ログイン実行
    # 'regist_input' => 'do_input_regist', #新規会員登録画面表示
    # 'regist' => 'do_regist', #新規会員登録実行
    'view' => 'do_view', #ユーザーデータ一覧表示
    'form_input' => 'do_input', #ユーザー追加画面表示
    'input_complete' => 'do_create', #ユーザー追加実行
    'update_item' => 'do_upinput', #ユーザー編集画面表示
    'update_complete' => 'do_update', #ユーザー編集実行
    'delete_item' => 'do_delete' #ユーザー削除実行
  );
}

# エラー処理
sub error {
  my($self, $err) = shift;

  return $err;
}

# アプリケーション実行後のクリーンアップ
sub teardown {
  my $self = shift;
  my $dbh = $self->param('dbh');

  $dbh->disconnect;
}

# # ログイン入力画面
# sub do_input_login {
#   my $self = shift;
#   my $template = $self->param('template');
#   my $output;
#
#   $template->process(
#     'login.html',
#     {},
#     \$output,
#   ) || print $template->error();
#
#   return $output;
#
#   $template->process(
#     'login.html',
#     {},
#     \$output,
#   ) || print $template->error();
#
#   return $output;
#
#   my $cookie1 = CGI::Cookie->new(-name=>'LOGINID',-value=>123456,-expires =>'+10s');
#   $cookie1->bake;
#   my %cookies = CGI::Cookie->fetch;
#   my $cookieId = $cookies{'LOGINID'}->value;
#
#   if($cookieId == 123456) {
#     return do_view();
#   } else {
#     $template->process(
#       'login.html',
#       {},
#       \$output,
#     ) || print $template->error();
#
#     return $output;
#   }
# }
#
# # 新規会員登録入力画面
# sub do_input_regist {
#   my $self = shift;
#   my $template = $self->param('template');
#   my $output;
#
#   $template->process(
#     'regist.html',
#     {},
#     \$output,
#   ) || print $template->error();
#   return $output;
# }
#
# # ログイン実行
# sub do_login {
#   my $self = shift;
#   my $dbh = $self->param('dbh');
#
#   my $formEmail = $self->query->param('email');
#   my $formPass = $self->query->param('password');
#
#   my $sth = $dbh->prepare("SELECT * FROM authuser where email = '$formEmail'");
#   $sth->execute() || die($DBI::errstr);
#   my $r = $sth->fetchrow_hashref();
#
#   if($r) {
#     # クッキー発行
#     # my $cookie1 = CGI::Cookie->new(-name=>'LOGINID',-value=>123456,-expires =>'+10s');
#     # $cookie1->bake;
#
#     my $passData = $r->{password};
#     my $salt = substr($passData, 0, 2);
#
#
#     if(crypt($formPass, $salt) eq $passData) {
#       # my $c = CGI::Cookie->new(-name=>$formEmail,-value=>$formPass);
#       return $self->forward('view');
#     } else {
#       return '入力したパスワードは間違っています。';
#     }
#   } else {
#     return "入力したメールアドレスは間違っています。";
#   }
# }
#
# # 新規会員登録実行
# sub do_regist {
#   my $self = shift;
#   my $dbh = $self->param('dbh');
#   my $template = $self->param('template');
#   my $output;
#
#   my $formEmail = $self->query->param('email');
#   my $formPass = $self->query->param('password');
#   my $salt = "xy";
#
#   my $passCrypt = crypt($formPass, $salt);
#
#   my $sth = $dbh->prepare("INSERT INTO authuser (email, password) VALUES('$formEmail', '$passCrypt')");
#   $sth->execute() || die($DBI::errstr);
#
#   $template->process(
#     'complete.html',
#     {},
#     \$output,
#   ) || print $template->error();
#
#   return $output;
# }

# 名簿一覧画面表示
sub do_view {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;

  my $sth = $dbh->prepare("SELECT * FROM list ORDER BY id ASC");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute() || die($DBI::errstr);
  my @ref;  # これをテンプレートに渡す
  my $r;
  while ($r = $sth->fetchrow_hashref()) {
    push(@ref, $r);
  }

  $template->process(
    'list.html',
    { people => \@ref },
    \$output,
  ) || return $template->error();

  return $output;
}

# 新規登録入力画面用意
sub do_input {
  my $self = shift;
  my $template = $self->param('template');
  my $output;

  $template->process(
    'insert_input.html',
    {},
    \$output,
  ) || print $template->error();

  return $output;
}

# 新規登録実行 → 完了画面
sub do_create {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;

  eval {
    my $formName = $self->query->param('userName');
    my $formMemo = $self->query->param('memo');
    my $sth = $dbh->prepare("INSERT INTO list (name, memo) VALUES('$formName', '$formMemo')"); #id項目はMySQLのAUTO_INCREMENTを使用
    $sth->execute() || die ($DBI::errstr);
    $dbh->commit;
  };
  if($@) {
    $dbh->rollback();
  }

  $template->process(
    'complete.html',
    {},
    \$output,
  ) || return $template->error();

  return $output;

}

# 更新用入力画面用意
sub do_upinput {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;

  my $updId = $self->query->param('id');
  my $sth = $dbh->prepare("SELECT * FROM list where id = '$updId'");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute() || die($DBI::errstr);
  my $r = $sth->fetchrow_hashref();

  $template->process(
    'insert_input.html',
    { item => $r },
    \$output,
  ) || print $template->error();

  return $output;
}

# 更新実行 → 完了画面
sub do_update {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;

  eval {
    my $updId = $self->query->param('id');
    my $upName = $self->query->param('userName');
    my $upMemo = $self->query->param('memo');
    $dbh->do("UPDATE list SET name = '$upName', memo = '$upMemo' WHERE id = '$updId'");
    $dbh->commit;
  };
  if($@) {
    $dbh->rollback();
  }


  $template->process(
    'complete.html',
    {},
    \$output,
  ) || print $template->error();

  return $output;
}

# 削除実行
sub do_delete {
  my $self = shift;
  my $dbh = $self->param('dbh');
  eval {
    my $delId = $self->query->param('id');
    $dbh->do("DELETE FROM list WHERE id = '$delId'");
    $dbh->commit;
  };
  if($@) {
    $dbh->rollback();
  }
  return $self->forward('view');
}

1;  # Perlの全てのモジュールの末尾にはこれが必要

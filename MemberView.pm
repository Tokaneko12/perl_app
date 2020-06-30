package MemberView;
use base 'CGI::Application';
use CGI::Application::Plugin::Forward;
use CGI::Application::Plugin::Redirect;
use CGI;
use CGI::Session;
use strict;
use warnings;
use Encode;
use DBI;
use DBD::mysql;
use Template::Provider::Encoding;
use Template::Stash::ForceUTF8;
use Template;
use Data::FormValidator;
use Data::FormValidator::Constraints qw(:closures);
use Data::Page;
use Digest::MD5 qw(md5_hex);
use File::Basename 'fileparse';

### 初期化
sub cgiapp_init {
  my $self = shift;
  my $cgiNew = CGI->new;
  my $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'sessionUser', 'Ogq0cVuO');
  $dbh->{AutoCommit} = 0;
  $dbh->{RaiseError} = 1;
  $self->query->charset('UTF-8');

  $self->param( # アプリケーション変数の設定
    'cgiNew' => $cgiNew,
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
  $self->start_mode('login_input');
  $self->mode_param('rm');
  $self->run_modes(
    'login_input' => 'do_input_login', #ログイン画面表示
    'login' => 'do_login', #ログイン実行
    'logout' => 'do_logout', #ログアウト実行
    'regist_input' => 'do_input_regist', #新規会員登録画面表示
    'regist' => 'do_regist', #新規会員登録実行
    'view' => 'do_view', #ユーザーデータ一覧表示
    'search' => 'do_search', #ユーザー検索実行
    'form_input' => 'do_input', #ユーザー追加画面表示
    'input_complete' => 'do_create', #ユーザー追加実行
    'update_item' => 'do_upinput', #ユーザー編集画面表示
    'update_complete' => 'do_update', #ユーザー編集実行
    'delete_item' => 'do_delete', #ユーザー削除実行
    'redirect_login' => 'redirect_login', #セッション切れ時のリダイレクト処理
    'open_file' => 'do_openfile', #ファイル内容の表示
    'delete_file' => 'do_deletefile', #ファイルの削除
  );
}

# エラー処理
sub error {
  my($self, $err) = @_;

  return $err;
}

# プレランモード設定
sub cgiapp_prerun {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $q = $self->param('cgiNew');
  my $sid = $q->cookie('sessionID');
  my $current_runmode = $self->get_current_runmode();
  my $isInvalidSession = 0;

  my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
  my $fmt0 = "%04d/%02d/%02d %02d:%02d:%02d";
  my $day0 = sprintf($fmt0, $year+1900,$mon+1,$mday,$hour+9,$min,$sec);

  my $filnam = "acclogf.cgi";
  open(FP,">>$filnam");
  print FP "$day0,$current_runmode\n";
  close(FP);

  if($current_runmode !~/^(login_input|login|logout|regist_input|regist|error)$/) {
    if(!$sid) {
      #エラー処理
      $isInvalidSession = 1;
    } else {
      my $session = CGI::Session->new("driver:MySQL", $sid, {Handle=>$dbh}); #mysqlの「sessions」テーブル

      if($sid != $session->id) {
        $session->delete();
        $session->flush();
        $isInvalidSession = 1;
      }
    }

    if($isInvalidSession) {
      return $self->prerun_mode('redirect_login');
    }
  }

  $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'test', 'test2001');
  $dbh->{AutoCommit} = 0;
  $dbh->{RaiseError} = 1;

  $self->param( # アプリケーション変数の設定
    'dbh' => $dbh,
  );
}

# アプリケーション実行後のクリーンアップ
sub teardown {
  my $self = shift;
  my $dbh = $self->param('dbh');

  $dbh->disconnect;
}

#
sub redirect_login {
  my $self = shift;
  return $self->redirect('memberview.cgi?rm=login_input', '302');
}

# ログイン入力画面
sub do_input_login {
  my $self = shift;
  my $template = $self->param('template');
  my $output;

  $template->process(
    'login.html',
    {},
    \$output,
  ) || return $template->error();

  return $output;
}

# 新規会員登録入力画面
sub do_input_regist {
  my $self = shift;
  my $template = $self->param('template');
  my $output;

  $template->process(
    'regist.html',
    {},
    \$output,
  ) || return $template->error();
  return $output;
}

# ログイン実行
sub do_login {
  my $self = shift;
  my $template = $self->param('template');
  my $output;
  my $dbh = $self->param('dbh');

  my $formEmail = $self->query->param('email');
  my $formPass = $self->query->param('password');

  my $sth = $dbh->prepare("SELECT * FROM authuser where email = ?");
  $sth->execute($formEmail) || die($DBI::errstr);
  my $r = $sth->fetchrow_hashref();
  my $passData = $r->{password};
  my $salt = substr($passData, 0, 2);

  # 入力エラー発生時
  if(!$r || (crypt($formPass, $salt) ne $passData)) {
    $template->process(
      'login.html',
      {
        formEmail => $formEmail,
        errMsg => "※メールアドレスもしくはパスワードが間違っています。"
      },
      \$output,
    ) || return $template->error();

    return $output;
  }

  $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'test', 'test2001');
  $dbh->{AutoCommit} = 0;
  $dbh->{RaiseError} = 1;

  $self->param( # アプリケーション変数の設定
    'dbh' => $dbh,
  );

  my $q = $self->param('cgiNew');
  my $session = CGI::Session->new("driver:MySQL", undef, {Handle=>$dbh});
  $session->expire('+24h');
  my $CGISESSID = $session->id();

  my $cookie = $q->cookie(
    -name    => 'sessionID',
    -value   => $CGISESSID,
    -expires => '+24h',
  );

  $self->header_add(-cookie => $cookie); # クッキー設定

  return $self->redirect('memberview.cgi?rm=view', '302');
}

# ログアウト実行
sub do_logout {
  my $self = shift;
  my $q = $self->param('cgiNew');
  my $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'sessionUser', 'Ogq0cVuO');

  my $cookie = $q->cookie(
    -name    => 'sessionID',
    -value   => '',
    -expires => '-1d',
  );
  $self->header_add(-cookie => $cookie); # クッキー設定

  return $self->redirect('memberview.cgi', '302');
}

# 新規会員登録実行
sub do_regist {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $formEmail = $self->query->param('email');
  my $formPass = $self->query->param('password');
  my $output;

  my $profile = {
    required => [qw(password), qw(email)],

    constraint_methods => {
      password=>qr/^[A-Za-z0-9]{12,32}$/,
      email => qr/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$/,
    },

    msgs => {
      prefix => 'err_',
      missing => '※この項目は入力必須です。',
      invalid => '※正しい形式で入力してください。',
      format => '<p class="error">%s</p>',
    }
  };

  my $results = Data::FormValidator->check($self->query, $profile);

  # 入力エラー発生時
  if ($results->has_invalid or $results->has_missing) {
    $template->process(
      'regist.html',
      {
        results => $results,
      },
      \$output,
    ) || return $template->error();

    return $output;
  }

  # emailデータの存在チェック
  my $sth = $dbh->prepare("SELECT * FROM authuser WHERE email = ?");
  $sth->execute($formEmail);
  my $data = $sth->fetchrow_hashref;

  # 重複emailデータがある場合入力画面でエラー表示
  if($data) {
    $template->process(
      'regist.html',
      {
        email_double => 1,
      },
      \$output,
    ) || return $template->error();

    return $output;
  }

  eval {
    my $salt = "xy";
    my $passCrypt = crypt($formPass, $salt);
    $dbh->do("INSERT INTO authuser (email, password) VALUES('$formEmail', '$passCrypt')");
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

# 名簿一覧画面表示
sub do_view {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $q = $self->param('cgiNew');
  my $pageId = $q->param('id') ? $q->param('id') : 1;
  my $page = Data::Page->new();
  my $output;

  my $sth = $dbh->prepare("SELECT * FROM list ORDER BY id ASC");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute() || die($DBI::errstr);
  my @ref;  # これをテンプレートに渡す
  my $r;
  while ($r = $sth->fetchrow_hashref()) {
    push(@ref, $r);
  }
  my $itemLength = @ref;
  $page->total_entries($itemLength);
  $page->entries_per_page(10);
  $page->current_page($pageId);
  my @visibleItems =  $page->splice(\@ref);

  $template->process(
    'list.html',
    {
      people => \@visibleItems,
      page => $page,
    },
    \$output,
  ) || return $template->error();

  return $output;
}

# ユーザー検索実行
sub do_search {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;
  my $id = $self->query->param('pageId') ? $self->query->param('pageId') : 1;
  my $search = $self->query->param('search');

  # MySQLの各カラムにngram設定済み(ダブルグラム)
  my $sth = $dbh->prepare("SELECT * FROM list where id=? OR match(name,memo,filename) against(? IN BOOLEAN MODE) ORDER BY id ASC");  # ソートなしだと順不動になるのでORDER BY は必須
  $sth->execute($search, $search) || die($DBI::errstr);
  my @ref;  # これをテンプレートに渡す
  my $r;
  while ($r = $sth->fetchrow_hashref()) {
    push(@ref, $r);
  }
  $template->process(
    'list.html',
    {
      people => \@ref,
      toplink => 1,
    },
    \$output,
  ) || return $template->error();
  return $output;
}

# ファイル内容の表示
sub do_openfile {
  my $self = shift;
  my $filename = $self->query->param('filename');

  # 読み込みファイル名のmd5ダイジェストを生成
  my $regex_suffix = qr/\.[^\.]+$/;
  my $filefrontname = (fileparse $filename, $regex_suffix)[0];
  my $mdfilename = md5_hex($filefrontname);
  my $targetdir = './' . substr($mdfilename, 0, 2);

  # 読み込みファイル名(ディレクトリ + md5ダイジェスト + 拡張子)
  my $openfilename = $targetdir . '/' . $mdfilename . (fileparse $filename, $regex_suffix)[2];

  # ファイルの表示処理
  return $self->redirect($openfilename, '302');
}

# ファイルの削除
sub do_deletefile {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $filename = $self->query->param('filename');

  eval {
    my $itemId = $self->query->param('itemId');
    $dbh->do("UPDATE list SET filename = '' where id = $itemId");
    $dbh->commit;
  };
  if($@) {
    $dbh->rollback();
  }

  # 削除ファイル名のmd5ダイジェストを生成
  my $regex_suffix = qr/\.[^\.]+$/;
  my $filefrontname = (fileparse $filename, $regex_suffix)[0];
  my $delfilename = md5_hex($filefrontname);
  my $deldir = './' . substr($delfilename, 0, 2);

  # 削除処理
  unlink $deldir . '/' . $delfilename . (fileparse $filename, $regex_suffix)[2];

  # ファイルの表示処理
  return $self->redirect('./memberview.cgi?rm=view', '302');
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
  ) || return $template->error();

  return $output;
}

# 新規登録実行 → 完了画面
sub do_create {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $formName = $self->query->param('userName');
  my $formMemo = $self->query->param('memo');
  my $output;
  my $filename = $self->query->param('upload_file');
  my ($bytesread, $buffer, $bufferfile);

  # 入力チェック
  my $profile = {
    optional => [qw(memo)],

    required => [qw(userName)],

    constraint_methods => {
      userName => FV_max_length(50),
      memo => FV_max_length(200)
    },

    msgs => {
      prefix => 'err_',
      missing => '※この項目は入力必須です。',
      invalid => '※入力の制限文字数を超えています。',
      format => '<p class="error">%s</p>',
    }
  };

  my $results = Data::FormValidator->check($self->query, $profile);

  # 入力エラー発生時
  if ($results->has_invalid or $results->has_missing) {
    $template->process(
      'insert_input.html',
      {
        results => $results,
      },
      \$output,
    ) || return $template->error();

    return $output;
  }

  if($filename) {
    # ファイルをバイナリデータに変換
    while(read($filename, $buffer, 1024)) {
      $bufferfile .= $buffer;
    }
    # 作成ファイル名のmd5ダイジェストを生成
    my $regex_suffix = qr/\.[^\.]+$/;
    my $filefrontname = (fileparse $filename, $regex_suffix)[0];
    my $mdfilename = md5_hex($filefrontname);
    my $targetdir = './' . substr($mdfilename, 0, 2);
    # 保存先ディレクトリがなければ新規作成
    if (!-d $targetdir) {
      mkdir $targetdir;
    }
    # 保存ファイル名(ディレクトリ + md5ダイジェスト + 拡張子)
    my $openfilename = $targetdir . '/' . $mdfilename . (fileparse $filename, $regex_suffix)[2];
    # ファイルの保存処理
    open(OUT, "> $openfilename") or return("ファイルの保存に失敗しました。");
    binmode(OUT); #改行を行わない保存
    print OUT $bufferfile;
    close OUT;
  }

  eval {
    my $sth = $dbh->prepare("INSERT INTO list (name, memo, filename) VALUES(?, ?, ?)"); #id項目はMySQLのAUTO_INCREMENTを使用
    $sth->execute($formName, $formMemo, $filename) || die ($DBI::errstr);
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

  my $updId = $self->query->param('itemId');
  my $sth = $dbh->prepare("SELECT * FROM list where id = ?");
  $sth->execute($updId) || die($DBI::errstr);
  my $r = $sth->fetchrow_hashref();

  $template->process(
    'insert_input.html',
    { item => $r },
    \$output,
  ) || return $template->error();

  return $output;
}

# 更新実行 → 完了画面
sub do_update {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $updId = $self->query->param('id');
  my $upName = $self->query->param('userName');
  my $upMemo = $self->query->param('memo');
  my $output;
  my $filename = $self->query->param('upload_file');
  my $curfilename = $self->query->param('current_filename');
  my ($bytesread, $buffer, $bufferfile);

  # 入力チェック
  my $profile = {
    optional => [qw(memo), qw(id)],

    required => [qw(userName)],

    constraint_methods => {
      userName => FV_max_length(50),
      memo => FV_max_length(200)
    },

    msgs => {
      prefix => 'err_',
      missing => '※この項目は入力必須です。',
      invalid => '※入力の制限文字数を超えています。',
      format => '<p class="error">%s</p>',
    }
  };

  my $results = Data::FormValidator->check($self->query, $profile);

  # 入力エラー発生時
  if ($results->has_invalid or $results->has_missing) {
    my $dbh = $self->param('dbh');

    my $sth = $dbh->prepare("SELECT * FROM list where id = '$updId'");  # ソートなしだと順不動になるのでORDER BY は必須
    $sth->execute() || die($DBI::errstr);
    my $r = $sth->fetchrow_hashref();

    $template->process(
      'insert_input.html',
      {
        item => $r,
        results => $results,
      },
      \$output,
    ) || return $template->error();

    return $output;
  }

  if($filename) {
    # 既存ファイルの削除処理
    my $del_suffix = qr/\.[^\.]+$/;
    my $current_filename = (fileparse $filename, $del_suffix)[0];
    my $delfilename = md5_hex($current_filename);
    my $deldir = './' . substr($delfilename, 0, 2);

    unlink $deldir . '/' . $delfilename;
    # 作成ファイルをバイナリデータに変換
    while(read($filename, $buffer, 1024)) {
      $bufferfile .= $buffer;
    }
    # 作成ファイル名のmd5ダイジェストを生成
    my $regex_suffix = qr/\.[^\.]+$/;
    my $filefrontname = (fileparse $filename, $regex_suffix)[0];
    my $mdfilename = md5_hex($filefrontname);
    my $targetdir = './' . substr($mdfilename, 0, 2);
    # 保存先ディレクトリがなければ新規作成
    if (!-d $targetdir) {
      mkdir $targetdir;
    }
    # 保存ファイル名(ディレクトリ + md5ダイジェスト + 拡張子)
    my $openfilename = $targetdir . '/' . $mdfilename . (fileparse $filename, $regex_suffix)[2];
    # ファイルの保存処理
    open(OUT, "> $openfilename") or return("ファイルの更新に失敗しました。");
    binmode(OUT); #改行を行わない保存
    print OUT $bufferfile;
    close OUT;
  } else {
    $filename = $curfilename ? $curfilename : 0;
  }
  eval {
    my $sth = $dbh->prepare("UPDATE list SET name = ?, memo = ?, filename = ? where id = ?"); #id項目はMySQLのAUTO_INCREMENTを使用
    $sth->execute($upName, $upMemo, $filename, $updId) || die ($DBI::errstr);
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

# 削除実行
sub do_delete {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $filename = $self->query->param('filename');
  eval {
    my $delId = $self->query->param('itemId');
    $dbh->do("DELETE FROM list WHERE id = '$delId'");
    $dbh->commit;
  };
  if($@) {
    $dbh->rollback();
  }

  # 削除ファイル名のmd5ダイジェストを生成
  my $regex_suffix = qr/\.[^\.]+$/;
  my $filefrontname = (fileparse $filename, $regex_suffix)[0];
  my $delfilename = md5_hex($filefrontname);
  my $deldir = './' . substr($delfilename, 0, 2);

  # 削除処理
  unlink $deldir . '/' . $delfilename . (fileparse $filename, $regex_suffix)[2];
  return $self->forward('view');
}

1;  # Perlの全てのモジュールの末尾にはこれが必要

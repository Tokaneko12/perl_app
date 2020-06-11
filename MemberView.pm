package MemberView;
use base 'CGI::Application';
use CGI::Application::Plugin::Forward;
use CGI::Application::Plugin::Redirect;
use CGI;
use CGI::Session;
use CGI::Carp qw(fatalsToBrowser); #デバック用(開発時以外はコメントアウト)
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

### 初期化
sub cgiapp_init {
  my $self = shift;
  my $cgiNew = CGI->new;
  my $dbh = DBI->connect('DBI:mysql:ATMARKIT:localhost', 'test', 'test2001');
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

# ログイン入力画面
sub do_input_login {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $q = $self->param('cgiNew');
  my $sid = $q->cookie('sessionID') || undef;
  my $session = CGI::Session->new("driver:MySQL", $sid, {Handle=>$dbh}); #mysqlの「sessions」テーブル
  $session->expire("+1h");

  if($sid == $session->id) {
    return $self->forward('view');
  } else {
    my $template = $self->param('template');
    my $output;

    $template->process(
      'login.html',
      {},
      \$output,
    ) || return $template->error();

    return $output;
  }
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
  ) || print $template->error();
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

  my $sth = $dbh->prepare("SELECT * FROM authuser where email = '$formEmail'");
  $sth->execute() || die($DBI::errstr);
  my $r = $sth->fetchrow_hashref();

  if($r) {
    my $passData = $r->{password};
    my $salt = substr($passData, 0, 2);

    if(crypt($formPass, $salt) eq $passData) {
      my $q = $self->param('cgiNew');
      my $session = CGI::Session->new("driver:MySQL", undef, {Handle=>$dbh});
      $session->expire('+1h');
      my $CGISESSID = $session->id();

      my $cookie = $q->cookie(
        -name    => 'sessionID',
        -value   => $CGISESSID,
        -expires => '+1h',
      );

      $self->header_add(-cookie => $cookie); # クッキー設定

      return $self->redirect('memberview.cgi?rm=view', '302');
    } else {
      $template->process(
        'login.html',
        {
          formEmail => $formEmail,
          errPass => "入力したパスワードは間違っています。"
        },
        \$output,
      ) || return $template->error();

      return $output;
    }
  } else {
    $template->process(
      'login.html',
      {
        formEmail => $formEmail,
        errMail => "入力したメールアドレスは存在しません。"
      },
      \$output,
    ) || return $template->error();

    return $output;
  }
}

# ログアウト実行
sub do_logout {
  my $self = shift;
  my $q = $self->param('cgiNew');

  my $cookie = $q->cookie(
    -name    => 'sessionID',
    -value   => '',
    -expires => '+1h',
  );
  $self->header_add(-cookie => $cookie); # クッキー設定

  return $self->redirect('login.html', '302');
}

# 新規会員登録実行
sub do_regist {
  my $self = shift;
  my $dbh = $self->param('dbh');
  my $template = $self->param('template');
  my $output;

  my $profile = {
    required => [qw(password), qw(email)],

    constraint_methods => {
      password=>qr/^[A-Za-z0-9]$/,
      email => email(),
    },

    msgs => {
      prefix => 'err_',
      missing => '※この項目は入力必須です。',
      invalid => '※正しい形式で入力してください。',
      format => '<p class="error">%s</p>',
    }
  };

  my $results = Data::FormValidator->check($self->query, $profile);

  if ($results->has_invalid or $results->has_missing) {
    $template->process(
      'regist.html',
      {
        results => $results,
      },
      \$output,
    ) || return $template->error();

    return $output;
  } else {
    eval {
      my $formEmail = $self->query->param('email');
      my $formPass = $self->query->param('password');
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
    ) || print $template->error();

    return $output;
  }
}

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
  my $formName = $self->query->param('userName');
  my $formMemo = $self->query->param('memo');
  my $fileName = $self->query->param('fileName');
  my $output;

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

  if ($results->has_invalid or $results->has_missing) {
    $template->process(
      'insert_input.html',
      {
        results => $results,
      },
      \$output,
    ) || return $template->error();

    return $output;
  } else {
    eval {
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
  # my $filename = $self->query->param('upload_file');
  # my ($bytesread, $buffer, $bufferfile);
  # # ファイルをバイナリデータに変換
  # while($bytesread = read($filename, $buffer, 2048)) {
  #   $bufferfile .= $buffer;
  # }
  # # ファイルの保存処理
  # open(OUT, "> filedata/$filename.txt") or return("ファイルの保存に失敗しました。");
  # binmode(OUT);
  # print OUT $bufferfile;
  # close OUT;
  # return $bufferfile;
  #
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
  my $updId = $self->query->param('id');
  my $upName = $self->query->param('userName');
  my $upMemo = $self->query->param('memo');
  my $output;

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
  } else {
    eval {
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

package App::cart::Buffer;

use strict;
use warnings;

use autodie;

use Log::Any '$log';

use DBI;
use Data::Dumper;

sub new {
    my ($class, $conf) = @_;

    Log::Any->set_adapter('+App::cart::Logger', level => $conf->{loglevel});

    my $db = $conf->{home} . '/' . $conf->{database}->{dbfile};
    my $self = bless {
        dbh => DBI->connect(
            "dbi:SQLite:dbname=$db",
            undef,
            undef,
            {
                PrintError      => 0,
                RaiseError      => 1,
                AutoCommit      => 1,
                sqlite_unicode  => 1,
            },
        ),
    }, $class;

    eval { $self->{_insert} = $self->{dbh}->prepare(
        "INSERT INTO tweets (id, data, user) VALUES (?, ?, ?);"
    ); };
    if ($@) {
        if ($@ =~ /no such table/) {
            $self->init;
            $self->{_insert} = $self->{dbh}->prepare(
                "INSERT INTO tweets (id, data, user) VALUES (?, ?, ?);"
            );
        } else {
            die $@;
        };
    }

    return $self;
}

sub bpush {
    my ($self, $tweet) = @_;

    eval { $self->{_insert}->execute(
        $tweet->{id},
        $tweet->{text},
        $tweet->{user}->{screen_name}
    ); };
    if ($@) {
        $log->error("Looks like an insert failed!\n");
        $log->debug(Dumper($tweet)) if $log->is_debug;
        die $@;
    }

}

sub bshift {
    my $self = shift;

    my $dbh = $self->{dbh};
    $dbh->begin_work;

    my $row = $dbh->selectrow_hashref(
        "SELECT id, data, user FROM tweets ORDER BY id",
    );

    $dbh->do(
        "DELETE FROM tweets WHERE id = ?",
        undef,
        $row->{id},
    );

    $dbh->commit;
    return $row;
}

sub count {
    my ($count) = shift->{dbh}->selectrow_array("SELECT COUNT(*) FROM tweets");
    return $count;
}

sub init {
    $log->debug("Initializing tweets buffer");
    shift->{dbh}->do(
        'CREATE TABLE tweets (id VARCHAR(30) PRIMARY KEY, data TEXT, user VARCHAR(16));'
    );
}

1;

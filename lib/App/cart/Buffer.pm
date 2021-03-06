package App::cart::Buffer;

use strict;
use warnings;

use autodie;

use Try::Tiny;
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

    try {
        $self->{_insert} = $self->{dbh}->prepare(
            "INSERT INTO tweets (id, data, user) VALUES (?, ?, ?);"
        );
    } catch {
        if ($_ =~ /no such table/) {
            $self->init;
            $self->{_insert} = $self->{dbh}->prepare(
                "INSERT INTO tweets (id, data, user) VALUES (?, ?, ?);"
            );
        } else {
            die $@;
        };
    };

    return $self;
}

sub bpush {
    my ($self, $tweet) = @_;

    try {
        $self->{_insert}->execute(
            $tweet->{id},
            $tweet->{text},
            $tweet->{user}->{screen_name},
        );
    } catch {
        $log->error("Looks like an insert failed!\n");
        $log->debug(Dumper($tweet)) if $log->is_debug;
        # Rethrow the exception after log stuff
        die $_;
    };

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

sub get_user_id {
    my ($self, $name) = @_;
    my $row;

    try {
        $row = $self->{dbh}->selectrow_hashref(
            "SELECT id FROM users WHERE name = ?",
            undef,
            $name,
        );
    } catch {
        $log->error("Error getting id for $name: $_");
    };

    return $row->{id};
}

sub save_user_id {
    my ($self, $name, $id) = @_;
    my $sth = $self->{dbh}->prepare(
        "INSERT INTO users (name, id) VALUES (?, ?)"
    );

    try {
        $sth->execute($name, $id);
    } catch {
        $log->error("Error caching $name id '$id': $_");
    };
}

sub init {
    my $self = shift;
    $log->debug("Initializing tweets buffer");

    my $dbh = $self->{dbh};
    $dbh->do(
        'CREATE TABLE tweets (id VARCHAR(30) PRIMARY KEY, data TEXT, user VARCHAR(16));'
    );

    $dbh->do(
        'CREATE TABLE users (name VARCHAR(16) PRIMARY KEY, id VARCHAR(30));'
    );
}

1;

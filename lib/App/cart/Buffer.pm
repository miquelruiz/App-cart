package App::cart::Buffer;

use strict;
use warnings;

use autodie;

use DBI;
use Data::Dumper;

sub new {
    my ($class, $conf) = @_;

    my $db = $conf->{home} . '/' . $conf->{database}->{dbfile};
    my $self = bless {
        dbh => DBI->connect(
            "dbi:SQLite:dbname=$db",
            undef,
            undef,
            {
                RaiseError => 1,
                AutoCommit => 1,
            },
        ),
    }, $class;
    
    return $self;
}

sub bpush {
    my ($self, $tweet) = @_;

    unless ($self->{_insert}) {
        $self->{_insert} = $self->{dbh}->prepare(
            "INSERT INTO tweets (id, data, user) VALUES (?, ?, ?);"
        );
    }

    eval { $self->{_insert}->execute(
        $tweet->{id},
        $tweet->{text},
        $tweet->{user}->{screen_name}
    ); };
    if ($@) {
        print STDERR "Looks like an insert failed!\n";
        print STDERR Dumper($tweet);
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
    shift->{dbh}->do(
        'CREATE TABLE tweets (id VARCHAR(30) PRIMARY KEY, data TEXT, user VARCHAR(16));'
    );
}

1;

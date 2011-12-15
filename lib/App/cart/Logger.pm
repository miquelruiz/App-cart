package App::cart::Logger;

use strict;
use warnings;

use Log::Any::Adapter::Util 'make_method';
use base 'Log::Any::Adapter::Base';

use Carp;
our @CARP_NOT = qw(
    Log::Any
    Log::Any::Manager
    Log::Any::Adapter::Base
    Log::Any::Adapter::Base
    App::cart::Logger
);

binmode *STDOUT, ':encoding(UTF-8)';

my $i = 0;
my @methods = Log::Any->logging_methods;
my %levels  = map { $_ => $i++ } @methods;

sub init {
    my ($self) = @_;
    $self->{level} ||= 'info';
    
    croak "Unknown log level: '$self->{level}'"
        unless defined $levels{$self->{level}};
}

foreach my $method ( @methods ) {
    make_method($method, sub {
        my $check = "is_$method";
        print @_,"\n" if shift->$check;
    });
}

foreach ( Log::Any->detection_methods() ) {
    my $method = substr $_, 3;
    make_method($_, sub {
        return 1 if $levels{ shift->{level} } <= $levels{ $method };
        return 0;
    });
}

1;


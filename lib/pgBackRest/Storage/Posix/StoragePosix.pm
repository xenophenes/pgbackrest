####################################################################################################################################
# STORAGE POSIX MODULE
####################################################################################################################################
package pgBackRest::Storage::Posix::StoragePosix;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Fcntl qw(O_RDONLY O_WRONLY);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Storage::Posix::StoragePosixIO;

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
        );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# open
####################################################################################################################################
sub openRead
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFile,
    ) =
        logDebugParam
    (
        __PACKAGE__ . '->openRead', \@_,
        {name => 'strFile', trace => true},
    );

    my $oFileIO = new pgBackRest::Storage::Posix::StoragePosixIO($strFile);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oFileIO', value => $oFileIO, trace => true},
    );
}

1;

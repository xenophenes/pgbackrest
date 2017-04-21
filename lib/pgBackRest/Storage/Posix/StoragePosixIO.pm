####################################################################################################################################
# STORAGE POSIX IO MODULE
####################################################################################################################################
package pgBackRest::Storage::Posix::StoragePosixIO;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_TRUNC);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;

####################################################################################################################################
# CONSTRUCTOR
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
        $self->{strFile},
        $self->{bWrite},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strFile', trace => true},
            {name => 'bWrite', optional => true, default => false, trace => true},
        );

    # Attempt to open the file
    if (!sysopen($self->{fhFile}, $self->{strFile}, $self->{bWrite} ? O_WRONLY | O_CREAT | O_TRUNC : O_RDONLY))
    {
        logErrorResult(
            $OS_ERROR{ENOENT} ? ERROR_FILE_MISSING : ERROR_FILE_OPEN, "unable to open '$self->{strFile}'", $OS_ERROR);
    }

    # Set file mode to binary
    binmode($self->{fhFile});

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# read - read data from the file.
####################################################################################################################################
sub read
{
    my $self = shift;
    my $rtBuffer = shift;
    my $iSize = shift;
    my $iOffset = shift;

    # Read the block
    my $iActualSize;

    eval
    {
        $iActualSize = sysread($self->handle(), $$rtBuffer, $iSize, defined($iOffset) ? $iOffset : 0);
        return true;
    }
    or do
    {
        logErrorResult(ERROR_FILE_READ, "unable to read '$self->{strFile}'", $EVAL_ERROR);
    };

    # Report any errors
    # uncoverable branch true - all errors seem to be caught by the handler above but check for error here just in case
    defined($iActualSize)
        or logErrorResult(ERROR_FILE_READ, "unable to read '$self->{strFile}'", $OS_ERROR);

    return $iActualSize;
}

####################################################################################################################################
# write - write data to a file
####################################################################################################################################
sub write
{
    my $self = shift;
    my $rtBuffer = shift;
    my $iSize = shift;
    my $iOffset = shift;

    # Write the block
    my $iActualSize;

    eval
    {
        $iActualSize = syswrite($self->handle(), $$rtBuffer, $iSize, defined($iOffset) ? $iOffset : 0);
        return true;
    }
    or do
    {
        logErrorResult(ERROR_FILE_WRITE, "unable to write '$self->{strFile}'", $EVAL_ERROR);
    };

    # Report any errors
    # uncoverable branch true - all errors seem to be caught by the handler above but check for error here just in case
    defined($iActualSize)
        or logErrorResult(ERROR_FILE_WRITE, "unable to write '$self->{strFile}'", $OS_ERROR);

    return $iActualSize;
}

####################################################################################################################################
# close/DESTROY - close the file
####################################################################################################################################
sub close
{
    my $self = shift;

    if (defined($self->handle()))
    {
        close($self->handle());
        undef($self->{fhFile});
    }

    return true;
}

sub DESTROY {shift->close()}

####################################################################################################################################
# Getters
####################################################################################################################################
sub handle {shift->{fhFile}}

1;

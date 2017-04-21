####################################################################################################################################
# STORAGE POSIX IO MODULE
####################################################################################################################################
package pgBackRest::Storage::Posix::StoragePosixIO;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

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
        $self->{lFlag},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strFile', trace => true},
            {name => 'lFlag', trace => true},
        );

    # Attempt to open the file
    if (!sysopen($self->{fhFile}, $self->{strFile}, $self->{lFlag}))
    {
        logErrorResult(
            $OS_ERROR{ENOENT} ? ERROR_FILE_MISSING : ERROR_FILE_OPEN, "unable to open '$self->{strFile}'", $OS_ERROR);
    }

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

    my $iActualSize = sysread($self->handle(), $$rtBuffer, $iSize, defined($iOffset) ? $iOffset : 0);

    if (!defined($iActualSize))
    {
        logErrorResult(ERROR_FILE_READ, "unable to read !!![NEED FILENAME]", $OS_ERROR);
    }

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
    my $iActualSize = syswrite($self->handle(), $$rtBuffer, $iSize, defined($iOffset) ? $iOffset : 0);

    # Report any errors
    if (!defined($iActualSize) || $iActualSize != $iSize)
    {
        $self->error(ERROR_FILE_WRITE, "unable to write ${iSize} bytes", $!);
    }
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
    }
}

sub DESTROY {shift->close()}

####################################################################################################################################
# Getters
####################################################################################################################################
sub handle {shift->{fhFile}}

1;

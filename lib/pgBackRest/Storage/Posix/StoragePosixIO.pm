####################################################################################################################################
# STORAGE POSIX IO MODULE
####################################################################################################################################
package pgBackRest::Storage::Posix::StoragePosixIO;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
# use File::Basename qw(dirname);
# use IPC::Open3 qw(open3);
# use IO::Select;
# use POSIX qw(:sys_wait_h);
# use Symbol 'gensym';
# use Time::HiRes qw(gettimeofday);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Wait;

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
        $self->{fhFile},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'fhFile', trace => true},
        );

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

    my $iActualSize = sysread($self->handle(), $$rtBuffer, $iSize, $iOffset);

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
    my $rtBufferRef = shift;
    my $iSize = shift;
    my $iOffset = shift;

    # Write the block
    my $iActualSize = syswrite($self->handle(), $$rtBuffer, $iSize, $iOffset);

    # Report any errors
    if (!defined($iActualSize) || $iActualSize != $iSize)
    {
        $self->error(ERROR_FILE_WRITE, "unable to write ${iSize} bytes", $!);
    }
}

####################################################################################################################################
# Getters
####################################################################################################################################
sub handle {shift->{fhFile}}

1;

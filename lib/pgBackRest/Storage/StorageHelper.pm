####################################################################################################################################
# STORAGE HELPER MODULE
####################################################################################################################################
package pgBackRest::Storage::StorageHelper;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use pgBackRest::Common::Log;
use pgBackRest::Config::Config;
use pgBackRest::Storage::Storage;

####################################################################################################################################
# storageLocal
#
# Get local storage.
####################################################################################################################################
sub storageLocal
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $strRepoPath,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::storageLocal', \@_,
            {name => 'strStanza'},
            {name => 'strRepoPath'},
        );

    # !!! NEED TO FIX TIMEOUT
    my $oStorage = new pgBackRest::Storage::Storage(
        $strStanza,
        $strRepoPath,
        new pgBackRest::Protocol::Common(
            OPTION_DEFAULT_BUFFER_SIZE, OPTION_DEFAULT_COMPRESS_LEVEL, OPTION_DEFAULT_COMPRESS_LEVEL_NETWORK,
            30));

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oStorage', value => $oStorage},
    );
}

push @EXPORT, qw(storageLocal);

1;

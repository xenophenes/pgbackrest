####################################################################################################################################
# BACKUP COMMON MODULE
####################################################################################################################################
package pgBackRest::BackupCommon;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename;

use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Common::Wait;
use pgBackRest::Config::Config;
use pgBackRest::Storage::Storage;
use pgBackRest::Storage::Posix::StoragePosixCommon;
use pgBackRest::Manifest;

####################################################################################################################################
# Latest backup link constant
####################################################################################################################################
use constant LINK_LATEST                                            => OPTION_DEFAULT_RESTORE_SET;
    push @EXPORT, qw(LINK_LATEST);

####################################################################################################################################
# backupRegExpGet
#
# Generate a regexp depending on the backups that need to be found.
####################################################################################################################################
sub backupRegExpGet
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $bFull,
        $bDifferential,
        $bIncremental,
        $bAnchor
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::backupRegExpGet', \@_,
            {name => 'bFull', default => false},
            {name => 'bDifferential', default => false},
            {name => 'bIncremental', default => false},
            {name => 'bAnchor', default => true}
        );

    # One of the types must be selected
    if (!($bFull || $bDifferential || $bIncremental))
    {
        confess &log(ASSERT, 'at least one backup type must be selected');
    }

    # Standard regexp to match date and time formattting
    my $strDateTimeRegExp = "[0-9]{8}\\-[0-9]{6}";
    # Start the expression with the anchor if requested, date/time regexp and full backup indicator
    my $strRegExp = ($bAnchor ? '^' : '') . $strDateTimeRegExp . 'F';

    # Add the diff and/or incr expressions if requested
    if ($bDifferential || $bIncremental)
    {
        # If full requested then diff/incr is optional
        if ($bFull)
        {
            $strRegExp .= "(\\_";
        }
        # Else diff/incr is required
        else
        {
            $strRegExp .= "\\_";
        }

        # Append date/time regexp for diff/incr
        $strRegExp .= $strDateTimeRegExp;

        # Filter on both diff/incr
        if ($bDifferential && $bIncremental)
        {
            $strRegExp .= '(D|I)';
        }
        # Else just diff
        elsif ($bDifferential)
        {
            $strRegExp .= 'D';
        }
        # Else just incr
        else
        {
            $strRegExp .= 'I';
        }

        # If full requested then diff/incr is optional
        if ($bFull)
        {
            $strRegExp .= '){0,1}';
        }
    }

    # Append the end anchor if requested
    $strRegExp .= $bAnchor ? "\$" : '';

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strRegExp', value => $strRegExp}
    );
}

push @EXPORT, qw(backupRegExpGet);

####################################################################################################################################
# backupLabelFormat
#
# Format the label for a backup.
####################################################################################################################################
sub backupLabelFormat
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $strBackupLabelLast,
        $lTimestampStop
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::backupLabelFormat', \@_,
            {name => 'strType', trace => true},
            {name => 'strBackupLabelLast', required => false, trace => true},
            {name => 'lTimestampStop', trace => true}
        );

    # Full backup label
    my $strBackupLabel;

    if ($strType eq BACKUP_TYPE_FULL)
    {
        # Last backup label must not be defined
        if (defined($strBackupLabelLast))
        {
            confess &log(ASSERT, "strBackupLabelLast must not be defined when strType = '${strType}'");
        }

        # Format the timestamp and add the full indicator
        $strBackupLabel = timestampFileFormat(undef, $lTimestampStop) . 'F';
    }
    # Else diff or incr label
    else
    {
        # Last backup label must be defined
        if (!defined($strBackupLabelLast))
        {
            confess &log(ASSERT, "strBackupLabelLast must be defined when strType = '${strType}'");
        }

        # Get the full backup portion of the last backup label
        $strBackupLabel = substr($strBackupLabelLast, 0, 16);

        # Format the timestamp
        $strBackupLabel .= '_' . timestampFileFormat(undef, $lTimestampStop);

        # Add the diff indicator
        if ($strType eq BACKUP_TYPE_DIFF)
        {
            $strBackupLabel .= 'D';
        }
        # Else incr indicator
        else
        {
            $strBackupLabel .= 'I';
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strBackupLabel', value => $strBackupLabel, trace => true}
    );
}

push @EXPORT, qw(backupLabelFormat);

####################################################################################################################################
# backupLabel
#
# Get unique backup label.
####################################################################################################################################
sub backupLabel
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oFile,
        $strType,
        $strBackupLabelLast,
        $lTimestampStop
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::backupLabelFormat', \@_,
            {name => 'oFile', trace => true},
            {name => 'strType', trace => true},
            {name => 'strBackupLabelLast', required => false, trace => true},
            {name => 'lTimestampStop', trace => true}
        );

    # Create backup label
    my $strBackupLabel = backupLabelFormat($strType, $strBackupLabelLast, $lTimestampStop);

    # Make sure that the timestamp has not already been used by a prior backup.  This is unlikely for online backups since there is
    # already a wait after the manifest is built but it's still possible if the remote and local systems don't have synchronized
    # clocks.  In practice this is most useful for making offline testing faster since it allows the wait after manifest build to
    # be skipped by dealing with any backup label collisions here.
    if (fileList(
        $oFile->pathGet(PATH_BACKUP_CLUSTER),
        {strExpression =>
            ($strType eq BACKUP_TYPE_FULL ? '^' : '_') . timestampFileFormat(undef, $lTimestampStop) .
            ($strType eq BACKUP_TYPE_FULL ? 'F' : '(D|I)$')}) ||
        fileList(
            $oFile->pathGet(PATH_BACKUP_CLUSTER . qw{/} . PATH_BACKUP_HISTORY . qw{/} . timestampFormat('%4d', $lTimestampStop)),
            {strExpression =>
                ($strType eq BACKUP_TYPE_FULL ? '^' : '_') . timestampFileFormat(undef, $lTimestampStop) .
                ($strType eq BACKUP_TYPE_FULL ? 'F' : '(D|I)\.manifest\.' . $oFile->{strCompressExtension}),
                bIgnoreMissing => true}))
    {
        waitRemainder();
        $strBackupLabel = backupLabelFormat($strType, $strBackupLabelLast, time());
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strBackupLabel', value => $strBackupLabel, trace => true}
    );
}

push @EXPORT, qw(backupLabel);

1;

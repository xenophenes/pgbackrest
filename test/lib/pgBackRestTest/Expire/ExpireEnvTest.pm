####################################################################################################################################
# ExpireCommonTest.pm - Common code for expire tests
####################################################################################################################################
package pgBackRestTest::Expire::ExpireEnvTest;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use pgBackRest::Archive::ArchiveInfo;
use pgBackRest::BackupCommon;
use pgBackRest::BackupInfo;
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
use pgBackRest::Config::Config;
use pgBackRest::DbVersion;
use pgBackRest::Storage::Storage;
use pgBackRest::Storage::Posix::StoragePosixCommon;
use pgBackRest::Manifest;
use pgBackRest::Stanza;
use pgBackRest::Version;

use pgBackRestTest::Common::Env::EnvHostTest;
use pgBackRestTest::Common::Host::HostBaseTest;
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::FileTest;

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{oHostBackup},
        $self->{strBackRestExe},
        $self->{oFile},
        $self->{oLogTest},
        $self->{oRunTest},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'oHostBackup', required => false, trace => true},
            {name => 'strBackRestExe', trace => true},
            {name => 'oFile', trace => true},
            {name => 'oLogTest', required => false, trace => true},
            {name => 'oRunTest', required => false, trace => true},
        );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# stanzaSet - set the local stanza object
####################################################################################################################################
sub stanzaSet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $strDbVersion,
        $bStanzaUpgrade,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->stanzaSet', \@_,
            {name => 'strStanza'},
            {name => 'strDbVersion'},
            {name => 'bStanzaUpgrade'},
        );

    # Assign variables
    my $oStanza = {};

    my $oStanzaCreate = new pgBackRest::Stanza();

    # If we're not upgrading, then create the stanza
    if (!$bStanzaUpgrade)
    {
        $oStanzaCreate->stanzaCreate();
    }

    # Get the database info for the stanza
    $$oStanza{strDbVersion} = $strDbVersion;
    $$oStanza{ullDbSysId} = $oStanzaCreate->{oDb}{ullDbSysId};
    $$oStanza{iCatalogVersion} = $oStanzaCreate->{oDb}{iCatalogVersion};
    $$oStanza{iControlVersion} = $oStanzaCreate->{oDb}{iControlVersion};

    my $oArchiveInfo = new pgBackRest::Archive::ArchiveInfo($self->{oFile}->pathGet(PATH_REPO_ARCHIVE));
    my $oBackupInfo = new pgBackRest::BackupInfo($self->{oFile}->pathGet(PATH_REPO_BACKUP));

    if ($bStanzaUpgrade)
    {
        # Upgrade the stanza
        $oArchiveInfo->dbSectionSet($$oStanza{strDbVersion}, $$oStanza{ullDbSysId}, $oArchiveInfo->dbHistoryIdGet() + 1);
        $oArchiveInfo->save();

        $oBackupInfo->dbSectionSet($$oStanza{strDbVersion}, $$oStanza{iControlVersion}, $$oStanza{iCatalogVersion},
            $$oStanza{ullDbSysId}, $oBackupInfo->dbHistoryIdGet() + 1);
        $oBackupInfo->save();
    }

    # Get the archive and directory paths for the stanza
    $$oStanza{strArchiveClusterPath} = $self->{oFile}->pathGet(PATH_REPO_ARCHIVE) . '/' . ($oArchiveInfo->archiveId());
    $$oStanza{strBackupClusterPath} = $self->{oFile}->pathGet(PATH_REPO_BACKUP);
    filePathCreate($$oStanza{strArchiveClusterPath}, undef, undef, true);

    $self->{oStanzaHash}{$strStanza} = $oStanza;

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# stanzaCreate
####################################################################################################################################
sub stanzaCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $strDbVersion,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->stanzaCreate', \@_,
            {name => 'strStanza'},
            {name => 'strDbVersion'},
        );

    my $strDbVersionTemp = $strDbVersion;
    $strDbVersionTemp =~ s/\.//;

    my $strDbPath = optionGet(OPTION_DB_PATH);

    # Create the test path for pg_control
    filePathCreate(($strDbPath . '/' . DB_PATH_GLOBAL), undef, true);

    # Copy pg_control for stanza-create
    executeTest(
        'cp ' . $self->{oRunTest}->dataPath() . '/backup.pg_control_' . $strDbVersionTemp . '.bin ' . $strDbPath .
        '/' . DB_FILE_PGCONTROL);
    executeTest('sudo chmod 600 ' . $strDbPath . '/' . DB_FILE_PGCONTROL);

    # Create the stanza and set the local stanza object
    $self->stanzaSet($strStanza, $strDbVersion, false);

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# stanzaUpgrade
####################################################################################################################################
sub stanzaUpgrade
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $strDbVersion,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->stanzaUpgrade', \@_,
            {name => 'strStanza'},
            {name => 'strDbVersion'},
        );

    my $strDbVersionTemp = $strDbVersion;
    $strDbVersionTemp =~ s/\.//;

    # Remove pg_control
    fileRemove(optionGet(OPTION_DB_PATH) . '/' . DB_FILE_PGCONTROL);

    # Copy pg_control for stanza-upgrade
    executeTest(
        'cp ' . $self->{oRunTest}->dataPath() . '/backup.pg_control_' . $strDbVersionTemp . '.bin ' . optionGet(OPTION_DB_PATH) .
        '/' . DB_FILE_PGCONTROL);
    executeTest('sudo chmod 600 ' . optionGet(OPTION_DB_PATH) . '/' . DB_FILE_PGCONTROL);

    $self->stanzaSet($strStanza, $strDbVersion, true);

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}
####################################################################################################################################
# backupCreate
####################################################################################################################################
sub backupCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $strType,
        $lTimestamp,
        $iArchiveBackupTotal,
        $iArchiveBetweenTotal
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->backupCreate', \@_,
            {name => 'strStanza'},
            {name => 'strType'},
            {name => 'lTimestamp'},
            {name => 'iArchiveBackupTotal', default => 3},
            {name => 'iArchiveBetweenTotal', default => 3}
        );

    my $oStanza = $self->{oStanzaHash}{$strStanza};

    my ($strArchiveStart, $strArchiveStop);

    if ($iArchiveBackupTotal != -1)
    {
        ($strArchiveStart, $strArchiveStop) = $self->archiveCreate($strStanza, $iArchiveBackupTotal);
    }

    # Create the manifest
    my $oLastManifest = $strType ne BACKUP_TYPE_FULL ? $$oStanza{oManifest} : undef;

    my $strBackupLabel =
        backupLabelFormat($strType,
                          defined($oLastManifest) ? $oLastManifest->get(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL) : undef,
                          $lTimestamp);

    my $strBackupClusterSetPath = "$$oStanza{strBackupClusterPath}/${strBackupLabel}";
    filePathCreate($strBackupClusterSetPath);

    &log(INFO, "create backup ${strBackupLabel}");

    my $strManifestFile = "$$oStanza{strBackupClusterPath}/${strBackupLabel}/" . FILE_MANIFEST;
    my $oManifest = new pgBackRest::Manifest($strManifestFile, false);

    # Store information about the backup into the backup section
    $oManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL, undef, $strBackupLabel);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ARCHIVE_CHECK, undef, true);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ARCHIVE_COPY, undef, false);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_BACKUP_STANDBY, undef, false);
    $oManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_ARCHIVE_START, undef, $strArchiveStart);
    $oManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_ARCHIVE_STOP, undef, $strArchiveStop);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_CHECKSUM_PAGE, undef, true);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_COMPRESS, undef, true);
    $oManifest->numericSet(INI_SECTION_BACKREST, INI_KEY_FORMAT, undef, BACKREST_FORMAT);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_HARDLINK, undef, false);
    $oManifest->boolSet(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ONLINE, undef, true);
    $oManifest->numericSet(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_START, undef, $lTimestamp);
    $oManifest->numericSet(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_STOP, undef, $lTimestamp);
    $oManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TYPE, undef, $strType);
    $oManifest->set(INI_SECTION_BACKREST, INI_KEY_VERSION, undef, BACKREST_VERSION);

    if ($strType ne BACKUP_TYPE_FULL)
    {
        if (!defined($oLastManifest))
        {
            confess &log(ERROR, "oLastManifest must be defined when strType = ${strType}");
        }

        push(my @stryReference, $oLastManifest->get(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL));

        $oManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_PRIOR, undef, $stryReference[0]);
    }

    $oManifest->save();
    $$oStanza{oManifest} = $oManifest;

    # Create the compressed history manifest
    $self->{oFile}->compress($strManifestFile, false);

    # Add the backup to info
    my $oBackupInfo = new pgBackRest::BackupInfo($$oStanza{strBackupClusterPath}, false);

    $oBackupInfo->check($$oStanza{strDbVersion}, $$oStanza{iControlVersion}, $$oStanza{iCatalogVersion}, $$oStanza{ullDbSysId});
    $oBackupInfo->add($oManifest);

    # Create the backup description string
    if (defined($$oStanza{strBackupDescription}))
    {
        $$oStanza{strBackupDescription} .= "\n";
    }

    $$oStanza{strBackupDescription} .=
        "* ${strType} backup: label = ${strBackupLabel}" .
        (defined($oLastManifest) ? ', prior = ' . $oLastManifest->get(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL) : '') .
        (defined($strArchiveStart) ? ", start = ${strArchiveStart}, stop = ${strArchiveStop}" : ', not online');

    if ($iArchiveBetweenTotal != -1)
    {
        $self->archiveCreate($strStanza, $iArchiveBetweenTotal);
    }

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# archiveNext
####################################################################################################################################
sub archiveNext
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strArchive,
        $bSkipFF
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->archiveNext', \@_,
            {name => 'strArchive', trace => true},
            {name => 'bSkipFF', trace => true}
        );

    # Break archive log into components
    my $lTimeline = hex(substr($strArchive, 0, 8));
    my $lMajor = hex(substr($strArchive, 8, 8));
    my $lMinor = hex(substr($strArchive, 16, 8));

    # Increment the minor component (and major when needed)
    $lMinor += 1;

    if ($bSkipFF && $lMinor == 255 || !$bSkipFF && $lMinor == 256)
    {
        $lMajor += 1;
        $lMinor = 0;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strArchiveNext', value => uc(sprintf("%08x%08x%08x", $lTimeline, $lMajor, $lMinor)), trace => true}
    );
}

####################################################################################################################################
# archiveCreate
####################################################################################################################################
sub archiveCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $iArchiveTotal
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->archiveCreate', \@_,
            {name => 'strStanza'},
            {name => 'iArchiveTotal'}
        );

    my $oStanza = $self->{oStanzaHash}{$strStanza};
    my $iArchiveIdx = 0;
    my $bSkipFF = $$oStanza{strDbVersion} <= PG_VERSION_92;

    my $strArchive = defined($$oStanza{strArchiveLast}) ? $self->archiveNext($$oStanza{strArchiveLast}, $bSkipFF) :
                                                          '000000010000000000000000';

    push(my @stryArchive, $strArchive);

    do
    {
        my $strPath = "$$oStanza{strArchiveClusterPath}/" . substr($strArchive, 0, 16);
        filePathCreate($strPath, undef, true);

        my $strFile = "${strPath}/${strArchive}-0000000000000000000000000000000000000000" . ($iArchiveIdx % 2 == 0 ? '.gz' : '');
        testFileCreate($strFile, 'ARCHIVE');

        $iArchiveIdx++;

        if ($iArchiveIdx < $iArchiveTotal)
        {
            $strArchive = $self->archiveNext($strArchive, $bSkipFF);
        }
    }
    while ($iArchiveIdx < $iArchiveTotal);

    push(@stryArchive, $strArchive);
    $$oStanza{strArchiveLast} = $strArchive;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'stryArchive', value => \@stryArchive}
    );
}

####################################################################################################################################
# supplementalLog
####################################################################################################################################
sub supplementalLog
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->supplementalLog', \@_,
            {name => 'strStanza'}
        );

    my $oStanza = $self->{oStanzaHash}{$strStanza};

    if (defined($self->{oLogTest}))
    {
        $self->{oLogTest}->supplementalAdd($self->{oHostBackup}->repoPath() .
                                           "/backup/${strStanza}/backup.info", $$oStanza{strBackupDescription});

        executeTest(
            'ls ' . $self->{oHostBackup}->repoPath() . "/backup/${strStanza} | grep -v \"backup.*\"",
            {oLogTest => $self->{oLogTest}});

        executeTest(
            'ls -R ' . $self->{oHostBackup}->repoPath() . "/archive/${strStanza} | grep -v \"archive.info\"",
            {oLogTest => $self->{oLogTest}});
    }

    return logDebugReturn($strOperation);
}

####################################################################################################################################
# process
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strStanza,
        $iExpireFull,
        $iExpireDiff,
        $strExpireArchiveType,
        $iExpireArchive,
        $strDescription
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->process', \@_,
            {name => 'strStanza'},
            {name => 'iExpireFull', required => false},
            {name => 'iExpireDiff', required => false},
            {name => 'strExpireArchiveType'},
            {name => 'iExpireArchive', required => false},
            {name => 'strDescription'}
        );

    my $oStanza = $self->{oStanzaHash}{$strStanza};

    $self->supplementalLog($strStanza);

    undef($$oStanza{strBackupDescription});

    my $strCommand = $self->{strBackRestExe} .
                     ' --' . OPTION_CONFIG . '="' . $self->{oHostBackup}->backrestConfig() . '"' .
                     ' --' . OPTION_STANZA . '=' . $strStanza .
                     ' --' . OPTION_LOG_LEVEL_CONSOLE . '=' . lc(DETAIL);

    if (defined($iExpireFull))
    {
        $strCommand .= ' --retention-full=' . $iExpireFull;
    }

    if (defined($iExpireDiff))
    {
        $strCommand .= ' --retention-diff=' . $iExpireDiff;
    }

    if (defined($strExpireArchiveType))
    {
        if (defined($iExpireArchive))
        {
            $strCommand .= ' --retention-archive-type=' . $strExpireArchiveType .
                           ' --retention-archive=' . $iExpireArchive;
        }
        else
        {
            $strCommand .= ' --retention-archive-type=' . $strExpireArchiveType;
        }
    }

    $strCommand .= ' expire';

    $self->{oHostBackup}->executeSimple($strCommand, {strComment => $strDescription, oLogTest => $self->{oLogTest}});

    $self->supplementalLog($strStanza);

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

1;

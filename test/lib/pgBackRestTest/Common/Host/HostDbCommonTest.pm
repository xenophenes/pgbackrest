####################################################################################################################################
# HostDbTest.pm - Database host
####################################################################################################################################
package pgBackRestTest::Common::Host::HostDbCommonTest;
use parent 'pgBackRestTest::Common::Host::HostBackupTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use DBI;
use Exporter qw(import);
    our @EXPORT = qw();
use Fcntl ':mode';
use File::Basename qw(dirname);
use Storable qw(dclone);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Common::Wait;
use pgBackRest::Config::Config;
use pgBackRest::DbVersion;
use pgBackRest::File;
use pgBackRest::FileCommon;
use pgBackRest::Manifest;
use pgBackRest::Version;

use pgBackRestTest::Common::Host::HostBackupTest;
use pgBackRestTest::Common::Host::HostBaseTest;
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::HostGroupTest;

####################################################################################################################################
# Host defaults
####################################################################################################################################
use constant HOST_PATH_SPOOL                                        => 'spool';
use constant HOST_PATH_DB                                           => 'db';
use constant HOST_PATH_DB_BASE                                      => 'base';

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oParam,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'oParam', required => false, trace => true},
        );

    # Get host group
    my $oHostGroup = hostGroupGet();

    # Is standby?
    my $bStandby = defined($$oParam{bStandby}) && $$oParam{bStandby} ? true : false;

    my $self = $class->SUPER::new(
        {
            strName => $bStandby ? HOST_DB_STANDBY : HOST_DB_MASTER,
            strImage => $$oParam{strImage},
            strBackupDestination => $$oParam{strBackupDestination},
            oLogTest => $$oParam{oLogTest},
            bSynthetic => $$oParam{bSynthetic},
        });
    bless $self, $class;

    # Set parameters
    $self->{bStandby} = $bStandby;

    $self->{strDbPath} = $self->testPath() . '/' . HOST_PATH_DB;
    $self->{strDbBasePath} = $self->dbPath() . '/' . HOST_PATH_DB_BASE;
    $self->{strTablespacePath} = $self->dbPath() . '/tablespace';

    filePathCreate($self->dbBasePath(), undef, undef, true);

    if ($$oParam{strBackupDestination} ne $self->nameGet())
    {
        $self->{strSpoolPath} = $self->testPath() . '/' . HOST_PATH_SPOOL;
        $self->{strLogPath} = $self->spoolPath() . '/' . HOST_PATH_LOG;
        $self->{strLockPath} = $self->spoolPath() . '/' . HOST_PATH_LOCK;

        filePathCreate($self->spoolPath());
    }
    else
    {
        $self->{strSpoolPath} = $self->repoPath();
    }

    # Initialize linkRemap Hashes
    $self->{hLinkRemap} = {};

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self, trace => true}
    );
}

####################################################################################################################################
# archivePush
####################################################################################################################################
sub archivePush
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strXlogPath,
        $strArchiveTestFile,
        $iArchiveNo,
        $iExpectedError,
        $bAsync,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->archivePush', \@_,
            {name => 'strXlogPath'},
            {name => 'strArchiveTestFile', required => false},
            {name => 'iArchiveNo', required => false},
            {name => 'iExpectedError', required => false},
            {name => 'bAsync', default => true},
        );

    my $strSourceFile;

    if (defined($strArchiveTestFile))
    {
        $strSourceFile = "${strXlogPath}/" . uc(sprintf('0000000100000001%08x', $iArchiveNo));

        $self->{oFile}->copy(
            PATH_DB_ABSOLUTE, $strArchiveTestFile,                      # Source file
            PATH_DB_ABSOLUTE, $strSourceFile,                           # Destination file
            false,                                                      # Source is not compressed
            false,                                                      # Destination is not compressed
            undef, undef, undef,                                        # Unused params
            true);                                                      # Create path if it does not exist

        filePathCreate("${strXlogPath}/archive_status/", undef, true, true);
        fileStringWrite("${strXlogPath}/archive_status/" . uc(sprintf('0000000100000001%08x', $iArchiveNo)) . '.ready');
    }

    $self->executeSimple(
        $self->backrestExe() .
        ' --config=' . $self->backrestConfig() .
        ' --log-level-console=warn --archive-queue-max=' . int(2 * PG_WAL_SIZE) .
        ' --stanza=' . $self->stanza() .
        (defined($iExpectedError) && $iExpectedError == ERROR_HOST_CONNECT ? ' --backup-host=bogus' : '') .
        ($bAsync ? '' : ' --no-archive-async') .
        " archive-push" . (defined($strSourceFile) ? " ${strSourceFile}" : ''),
        {iExpectedExitStatus => $iExpectedError, oLogTest => $self->{oLogTest}, bLogOutput => $self->synthetic()});

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# configRecovery
####################################################################################################################################
sub configRecovery
{
    my $self = shift;
    my $oHostBackup = shift;
    my $oRecoveryHashRef = shift;

    # Get stanza
    my $strStanza = $self->stanza();

    # Load db config file
    my $oConfig = iniParse(fileStringRead($self->backrestConfig()), {bRelaxed => true});

    # Rewrite recovery options
    my @stryRecoveryOption;

    foreach my $strOption (sort(keys(%$oRecoveryHashRef)))
    {
        push (@stryRecoveryOption, "${strOption}=${$oRecoveryHashRef}{$strOption}");
    }

    if (@stryRecoveryOption)
    {
        $oConfig->{$strStanza}{&OPTION_RESTORE_RECOVERY_OPTION} = \@stryRecoveryOption;
    }

    # Save db config file
    fileStringWrite($self->backrestConfig(), iniRender($oConfig, true));
}

####################################################################################################################################
# configRemap
####################################################################################################################################
sub configRemap
{
    my $self = shift;
    my $oRemapHashRef = shift;
    my $oManifestRef = shift;

    # Get stanza name
    my $strStanza = $self->stanza();

    # Load db config file
    my $oConfig = iniParse(fileStringRead($self->backrestConfig()), {bRelaxed => true});

    # Load backup config file
    my $oRemoteConfig;
    my $oHostBackup =
        !$self->standby() && !$self->nameTest($self->backupDestination()) ?
            hostGroupGet()->hostGet($self->backupDestination()) : undef;

    if (defined($oHostBackup))
    {
        $oRemoteConfig = iniParse(fileStringRead($oHostBackup->backrestConfig()), {bRelaxed => true});
    }

    # Rewrite recovery section
    delete($oConfig->{"${strStanza}:restore"}{&OPTION_TABLESPACE_MAP});
    my @stryTablespaceMap;

    foreach my $strRemap (sort(keys(%$oRemapHashRef)))
    {
        my $strRemapPath = ${$oRemapHashRef}{$strRemap};

        if ($strRemap eq MANIFEST_TARGET_PGDATA)
        {
            $oConfig->{$strStanza}{&OPTION_DB_PATH} = $strRemapPath;
            ${$oManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{&MANIFEST_TARGET_PGDATA}{&MANIFEST_SUBKEY_PATH} = $strRemapPath;

            if (defined($oHostBackup))
            {
                my $bForce = $oHostBackup->nameTest(HOST_BACKUP) && defined(hostGroupGet()->hostGet(HOST_DB_STANDBY, true));
                $oRemoteConfig->{$strStanza}{optionIndex(OPTION_DB_PATH, 1, $bForce)} = $strRemapPath;
            }
        }
        else
        {
            my $strTablespaceOid = (split('\/', $strRemap))[1];
            push (@stryTablespaceMap, "${strTablespaceOid}=${strRemapPath}");

            ${$oManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{$strRemap}{&MANIFEST_SUBKEY_PATH} = $strRemapPath;
            ${$oManifestRef}{&MANIFEST_SECTION_TARGET_LINK}{MANIFEST_TARGET_PGDATA . "/${strRemap}"}{destination} = $strRemapPath;
        }
    }

    if (@stryTablespaceMap)
    {
        $oConfig->{"${strStanza}:restore"}{&OPTION_TABLESPACE_MAP} = \@stryTablespaceMap;
    }

    # Save db config file
    fileStringWrite($self->backrestConfig(), iniRender($oConfig, true));

    # Save backup config file (but not is this is the standby which is not the source of backups)
    if (defined($oHostBackup))
    {
        # Modify the file permissions so it can be read/saved by all test users
        executeTest(
            'sudo chmod 660 ' . $oHostBackup->backrestConfig() . ' && sudo chmod 770 ' . dirname($oHostBackup->backrestConfig()));

        fileStringWrite($oHostBackup->backrestConfig(), iniRender($oRemoteConfig, true));

        # Fix permissions
        executeTest(
            'sudo chmod 660 ' . $oHostBackup->backrestConfig() . ' && sudo chmod 770 ' . dirname($oHostBackup->backrestConfig()) .
            ' && sudo chown ' . $oHostBackup->userGet() . ' ' . $oHostBackup->backrestConfig());
    }
}

####################################################################################################################################
# linkRemap
####################################################################################################################################
sub linkRemap
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strTarget,
        $strDestination
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->linkRemap', \@_,
            {name => 'strTarget'},
            {name => 'strDestination'},
        );

    ${$self->{hLinkRemap}}{$strTarget} = $strDestination;

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# restore
####################################################################################################################################
sub restore
{
    my $self = shift;
    my $strBackup = shift;
    my $oExpectedManifestRef = shift;
    my $oRemapHashRef = shift;
    my $bDelta = shift;
    my $bForce = shift;
    my $strType = shift;
    my $strTarget = shift;
    my $bTargetExclusive = shift;
    my $strTargetAction = shift;
    my $strTargetTimeline = shift;
    my $oRecoveryHashRef = shift;
    my $strComment = shift;
    my $iExpectedExitStatus = shift;
    my $strOptionalParam = shift;
    my $bTablespace = shift;
    my $strUser = shift;

    # Set defaults
    $bDelta = defined($bDelta) ? $bDelta : false;
    $bForce = defined($bForce) ? $bForce : false;

    # Build link map options
    my $strLinkMap;

    foreach my $strTarget (sort(keys(%{$self->{hLinkRemap}})))
    {
        $strLinkMap .= " --link-map=\"${strTarget}=${$self->{hLinkRemap}}{$strTarget}\"";
    }

    $strComment = 'restore' .
                  ($bDelta ? ' delta' : '') .
                  ($bForce ? ', force' : '') .
                  ($strBackup ne OPTION_DEFAULT_RESTORE_SET ? ", backup '${strBackup}'" : '') .
                  ($strType ? ", type '${strType}'" : '') .
                  ($strTarget ? ", target '${strTarget}'" : '') .
                  ($strTargetTimeline ? ", timeline '${strTargetTimeline}'" : '') .
                  (defined($bTargetExclusive) && $bTargetExclusive ? ', exclusive' : '') .
                  (defined($strTargetAction) && $strTargetAction ne OPTION_DEFAULT_RESTORE_TARGET_ACTION
                      ? ', ' . OPTION_TARGET_ACTION . "=${strTargetAction}" : '') .
                  (defined($oRemapHashRef) ? ', remap' : '') .
                  (defined($iExpectedExitStatus) ? ", expect exit ${iExpectedExitStatus}" : '') .
                  (defined($strComment) ? " - ${strComment}" : '') .
                  ' (' . $self->nameGet() . ' host)';
    &log(INFO, "        ${strComment}");

    # Get the backup host
    my $oHostGroup = hostGroupGet();
    my $oHostBackup = defined($oHostGroup->hostGet(HOST_BACKUP, true)) ? $oHostGroup->hostGet(HOST_BACKUP) : $self;

    # Load the expected manifest if it was not defined
    my $oExpectedManifest = undef;

    if (!defined($oExpectedManifestRef))
    {
        # Load the manifest
        my $oExpectedManifest = new pgBackRest::Manifest(
            $self->{oFile}->pathGet(
                PATH_BACKUP_CLUSTER, ($strBackup eq 'latest' ? $oHostBackup->backupLast() : $strBackup) . '/' . FILE_MANIFEST),
            true);

        $oExpectedManifestRef = $oExpectedManifest->{oContent};

        # Remap links in the expected manifest
        foreach my $strTarget (sort(keys(%{$self->{hLinkRemap}})))
        {
            my $strDestination = ${$self->{hLinkRemap}}{$strTarget};
            my $strTarget = 'pg_data/' . $strTarget;
            my $strTargetPath = $strDestination;

            # If this link is to a file then the specified path must be split into file and path parts
            if ($oExpectedManifest->isTargetFile($strTarget))
            {
                $strTargetPath = dirname($strTargetPath);

                # Error when the path is not deep enough to be valid
                if (!defined($strTargetPath))
                {
                    confess &log(ERROR, "${strDestination} is not long enough to be target for ${strTarget}");
                }

                # Set the file part
                $oExpectedManifest->set(
                    MANIFEST_SECTION_BACKUP_TARGET, $strTarget, MANIFEST_SUBKEY_FILE,
                    substr($strDestination, length($strTargetPath) + 1));

                # Set the link target
                $oExpectedManifest->set(
                    MANIFEST_SECTION_TARGET_LINK, $strTarget, MANIFEST_SUBKEY_DESTINATION, $strDestination);
            }
            else
            {
                # Set the link target
                $oExpectedManifest->set(MANIFEST_SECTION_TARGET_LINK, $strTarget, MANIFEST_SUBKEY_DESTINATION, $strTargetPath);
            }

            # Set the target path
            $oExpectedManifest->set(MANIFEST_SECTION_BACKUP_TARGET, $strTarget, MANIFEST_SUBKEY_PATH, $strTargetPath);
        }
    }

    # Get the backup host
    if (defined($oRemapHashRef))
    {
        $self->configRemap($oRemapHashRef, $oExpectedManifestRef);
    }

    if (defined($oRecoveryHashRef))
    {
        $self->configRecovery($oHostBackup, $oRecoveryHashRef);
    }

    # Create the restorecommand
    $self->executeSimple(
        $self->backrestExe() .
        ' --config=' . $self->backrestConfig() .
        (defined($bDelta) && $bDelta ? ' --delta' : '') .
        (defined($bForce) && $bForce ? ' --force' : '') .
        ($strBackup ne OPTION_DEFAULT_RESTORE_SET ? " --set=${strBackup}" : '') .
        (defined($strOptionalParam) ? " ${strOptionalParam} " : '') .
        (defined($strType) && $strType ne RECOVERY_TYPE_DEFAULT ? " --type=${strType}" : '') .
        (defined($strTarget) ? " --target=\"${strTarget}\"" : '') .
        (defined($strTargetTimeline) ? " --target-timeline=\"${strTargetTimeline}\"" : '') .
        (defined($bTargetExclusive) && $bTargetExclusive ? ' --target-exclusive' : '') .
        (defined($strLinkMap) ? $strLinkMap : '') .
        ($self->synthetic() ? '' : ' --link-all') .
        (defined($strTargetAction) && $strTargetAction ne OPTION_DEFAULT_RESTORE_TARGET_ACTION
            ? ' --' . OPTION_TARGET_ACTION . "=${strTargetAction}" : '') .
        ' --stanza=' . $self->stanza() . ' restore',
        {strComment => $strComment, iExpectedExitStatus => $iExpectedExitStatus, oLogTest => $self->{oLogTest},
         bLogOutput => $self->synthetic()},
        $strUser);

    if (!defined($iExpectedExitStatus))
    {
        $self->restoreCompare($strBackup, dclone($oExpectedManifestRef), $bTablespace);

        if (defined($self->{oLogTest}))
        {
            $self->{oLogTest}->supplementalAdd(
                $$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_TARGET}{&MANIFEST_TARGET_PGDATA}{&MANIFEST_SUBKEY_PATH} .
                "/recovery.conf");
        }
    }
}

####################################################################################################################################
# restoreCompare
####################################################################################################################################
sub restoreCompare
{
    my $self = shift;
    my $strBackup = shift;
    my $oExpectedManifestRef = shift;
    my $bTablespace = shift;

    my $strTestPath = $self->testPath();

    # Get the backup host
    my $oHostGroup = hostGroupGet();
    my $oHostBackup = defined($oHostGroup->hostGet(HOST_BACKUP, true)) ? $oHostGroup->hostGet(HOST_BACKUP) : $self;

    # Load the last manifest if it exists
    my $oLastManifest = undef;

    if (defined(${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_PRIOR}))
    {
        my $oExpectedManifest =
            new pgBackRest::Manifest(
                $self->{oFile}->pathGet(
                    PATH_BACKUP_CLUSTER,
                    ($strBackup eq 'latest' ? $oHostBackup->backupLast() : $strBackup) .
                    '/'. FILE_MANIFEST), true);

        $oLastManifest =
            new pgBackRest::Manifest(
                $self->{oFile}->pathGet(
                    PATH_BACKUP_CLUSTER,
                    ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_PRIOR} .
                    '/' . FILE_MANIFEST), true);
    }

    # Generate the tablespace map for real backups
    my $oTablespaceMap = undef;

    if (!$self->synthetic())
    {
        # Tablespace_map file is not restored in versions >= 9.5 because it interferes with internal remapping features.
        if (${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_DB_VERSION} >= PG_VERSION_95)
        {
            delete(${$oExpectedManifestRef}{&MANIFEST_SECTION_TARGET_FILE}{MANIFEST_TARGET_PGDATA . '/tablespace_map'});
        }

        foreach my $strTarget (keys(%{${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}}))
        {
            if (defined(${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TABLESPACE_ID}))
            {
                my $iTablespaceId =
                    ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TABLESPACE_ID};

                $$oTablespaceMap{$iTablespaceId} =
                    ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TABLESPACE_NAME};
            }
        }
    }

    # Generate the actual manifest
    my $strDbClusterPath =
        ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}{&MANIFEST_TARGET_PGDATA}{&MANIFEST_SUBKEY_PATH};

    if (defined($bTablespace) && !$bTablespace)
    {
        foreach my $strTarget (keys(%{${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_TARGET}}))
        {
            if ($$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TYPE} eq
                MANIFEST_VALUE_LINK &&
                defined($$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TABLESPACE_ID}))
            {
                my $strRemapPath;
                my $iTablespaceName =
                    $$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_TABLESPACE_NAME};

                $strRemapPath = "../../tablespace/${iTablespaceName}";

                $$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_TARGET}{$strTarget}{&MANIFEST_SUBKEY_PATH} = $strRemapPath;
                $$oExpectedManifestRef{&MANIFEST_SECTION_TARGET_LINK}{MANIFEST_TARGET_PGDATA . "/${strTarget}"}
                    {&MANIFEST_SUBKEY_DESTINATION} = $strRemapPath;
            }
        }
    }

    my $oActualManifest = new pgBackRest::Manifest("${strTestPath}/" . FILE_MANIFEST, false);

    $oActualManifest->set(
        MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_DB_VERSION, undef,
        $$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_DB_VERSION});
    $oActualManifest->numericSet(
        MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_CATALOG, undef,
        $$oExpectedManifestRef{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_CATALOG});

    $oActualManifest->build(
        $self->{oFile}, ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_DB_VERSION}, $strDbClusterPath,
        $oLastManifest, false, $oTablespaceMap);

    my $strSectionPath = $oActualManifest->get(MANIFEST_SECTION_BACKUP_TARGET, MANIFEST_TARGET_PGDATA, MANIFEST_SUBKEY_PATH);

    foreach my $strName ($oActualManifest->keys(MANIFEST_SECTION_TARGET_FILE))
    {
        # If synthetic match checksum errors since they can't be verified here
        if ($self->synthetic)
        {
            my $bChecksumPage = $oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM_PAGE};

            if (defined($bChecksumPage))
            {
                $oActualManifest->boolSet(MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_CHECKSUM_PAGE, $bChecksumPage);

                if (!$bChecksumPage &&
                    defined($oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM_PAGE_ERROR}))
                {
                    $oActualManifest->set(
                        MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_CHECKSUM_PAGE_ERROR,
                        $oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM_PAGE_ERROR});
                }
            }
        }
        # Else if page checksums are enabled make sure the correct files are being checksummed
        else
        {
            if ($oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_CHECKSUM_PAGE})
            {
                if (defined($oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM_PAGE}) !=
                    isChecksumPage($strName))
                {
                    confess
                        "check-page actual for ${strName} is " .
                        ($oActualManifest->test(MANIFEST_SECTION_TARGET_FILE, $strName,
                            MANIFEST_SUBKEY_CHECKSUM_PAGE) ? 'set' : '[undef]') .
                        ' but isChecksumPage() says it should be ' .
                        (isChecksumPage($strName) ? 'set' : '[undef]') . '.';
                }

                # Because the page checksum flag is copied to incr and diff from the previous backup but further processing is not
                # done, they can't be expected to match so delete them.
                delete($oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM_PAGE});
                $oActualManifest->remove(MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_CHECKSUM_PAGE);
            }
        }

        if (!$self->synthetic())
        {
            $oActualManifest->set(
                MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_SIZE,
                ${$oExpectedManifestRef}{&MANIFEST_SECTION_TARGET_FILE}{$strName}{size});
        }

        # Remove repo-size from the manifest.  ??? This could be improved to get actual sizes from the backup.
        $oActualManifest->remove(MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_REPO_SIZE);
        delete($oExpectedManifestRef->{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_REPO_SIZE});

        if ($oActualManifest->get(MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_SIZE) != 0)
        {
            my $oStat = fileStat($oActualManifest->dbPathGet($strSectionPath, $strName));

            if ($oStat->blocks > 0 || S_ISLNK($oStat->mode))
            {
                $oActualManifest->set(
                    MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_CHECKSUM,
                    $self->{oFile}->hash(PATH_DB_ABSOLUTE, $oActualManifest->dbPathGet($strSectionPath, $strName)));
            }
            else
            {
                $oActualManifest->remove(MANIFEST_SECTION_TARGET_FILE, $strName, MANIFEST_SUBKEY_CHECKSUM);
                delete(${$oExpectedManifestRef}{&MANIFEST_SECTION_TARGET_FILE}{$strName}{&MANIFEST_SUBKEY_CHECKSUM});
            }
        }
    }

    # If the link section is empty then delete it and the default section
    if (keys(%{${$oExpectedManifestRef}{&MANIFEST_SECTION_TARGET_LINK}}) == 0)
    {
        delete($$oExpectedManifestRef{&MANIFEST_SECTION_TARGET_LINK});
        delete($$oExpectedManifestRef{&MANIFEST_SECTION_TARGET_LINK . ':default'});
    }

    # Set actual to expected for settings that always change from backup to backup
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ARCHIVE_CHECK, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_ARCHIVE_CHECK});
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ARCHIVE_COPY, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_ARCHIVE_COPY});
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_BACKUP_STANDBY, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_BACKUP_STANDBY});
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_COMPRESS, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_COMPRESS});
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_HARDLINK, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_HARDLINK});
    $oActualManifest->set(MANIFEST_SECTION_BACKUP_OPTION, MANIFEST_KEY_ONLINE, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_ONLINE});

    $oActualManifest->set(MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_DB_VERSION, undef,
                          ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_DB_VERSION});
    $oActualManifest->numericSet(MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_CONTROL, undef,
                                 ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_CONTROL});
    $oActualManifest->numericSet(MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_CATALOG, undef,
                                 ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_CATALOG});
    $oActualManifest->numericSet(MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_SYSTEM_ID, undef,
                                 ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_SYSTEM_ID});
    $oActualManifest->numericSet(MANIFEST_SECTION_BACKUP_DB, MANIFEST_KEY_DB_ID, undef,
                                 ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_DB}{&MANIFEST_KEY_DB_ID});

    $oActualManifest->set(INI_SECTION_BACKREST, INI_KEY_VERSION, undef,
                          ${$oExpectedManifestRef}{&INI_SECTION_BACKREST}{&INI_KEY_VERSION});

    # This option won't be set in the actual manifest
    delete($oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_CHECKSUM_PAGE});

    if ($self->synthetic())
    {
        $oActualManifest->remove(MANIFEST_SECTION_BACKUP);
        delete($oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP});
    }
    else
    {
        $oActualManifest->set(
            INI_SECTION_BACKREST, INI_KEY_CHECKSUM, undef, $oExpectedManifestRef->{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM});
        $oActualManifest->set(
            MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LABEL, undef,
            $oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_LABEL});
        $oActualManifest->set(
            MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_COPY_START, undef,
            $oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_TIMESTAMP_COPY_START});
        $oActualManifest->set(
            MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_START, undef,
            $oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_TIMESTAMP_START});
        $oActualManifest->set(
            MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TIMESTAMP_STOP, undef,
            $oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_TIMESTAMP_STOP});
        $oActualManifest->set(
            MANIFEST_SECTION_BACKUP, MANIFEST_KEY_TYPE, undef,
            $oExpectedManifestRef->{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_TYPE});

        $oActualManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LSN_START, undef,
                              ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_LSN_START});
        $oActualManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_LSN_STOP, undef,
                              ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_LSN_STOP});

        if (defined(${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_ARCHIVE_START}))
        {
            $oActualManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_ARCHIVE_START, undef,
                                  ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_ARCHIVE_START});
        }

        if (${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_ARCHIVE_STOP})
        {
            $oActualManifest->set(MANIFEST_SECTION_BACKUP, MANIFEST_KEY_ARCHIVE_STOP, undef,
                                  ${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP}{&MANIFEST_KEY_ARCHIVE_STOP});
        }
    }

    # Error when archive status exists in the manifest for an online backup
    if (${$oExpectedManifestRef}{&MANIFEST_SECTION_BACKUP_OPTION}{&MANIFEST_KEY_ONLINE} &&
        defined(${$oExpectedManifestRef}{&MANIFEST_SECTION_TARGET_PATH}{MANIFEST_PATH_PGXLOG . '/archive_status'}))
    {
        confess 'archive_status was backed up in pg_xlog - the filter did not work';
    }

    # Delete the list of DBs
    delete($$oExpectedManifestRef{&MANIFEST_SECTION_DB});

    $self->manifestDefault($oExpectedManifestRef);

    # Delete sequences
    delete($oActualManifest->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE});
    delete($oExpectedManifestRef->{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE});

    fileStringWrite("${strTestPath}/actual.manifest", iniRender($oActualManifest->{oContent}));
    fileStringWrite("${strTestPath}/expected.manifest", iniRender($oExpectedManifestRef));

    executeTest("diff ${strTestPath}/expected.manifest ${strTestPath}/actual.manifest");

    fileRemove("${strTestPath}/expected.manifest");
    fileRemove("${strTestPath}/actual.manifest");
}

####################################################################################################################################
# Getters
####################################################################################################################################
sub dbPath {return shift->{strDbPath};}

sub dbBasePath
{
    my $self = shift;
    my $iIndex = shift;

    return $self->{strDbBasePath} . (defined($iIndex) ? "-${iIndex}" : '');
}

sub spoolPath {return shift->{strSpoolPath}}
sub standby {return shift->{bStandby}}

sub tablespacePath
{
    my $self = shift;
    my $iTablespace = shift;
    my $iIndex = shift;

    return
        $self->{strTablespacePath} .
        (defined($iTablespace) ? "/ts${iTablespace}" .
        (defined($iIndex) ? "-${iIndex}" : '') : '');
}

1;

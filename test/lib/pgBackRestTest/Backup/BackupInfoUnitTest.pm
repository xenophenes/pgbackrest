####################################################################################################################################
# BackupInfoUnitTest.pm - Unit tests for BackupInfo
####################################################################################################################################
package pgBackRestTest::Backup::BackupInfoUnitTest;
use parent 'pgBackRestTest::Common::Env::EnvHostTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use File::Basename qw(dirname);
use Storable qw(dclone);

use pgBackRest::BackupInfo;
use pgBackRest::Common::Exception;
use pgBackRest::Common::Lock;
use pgBackRest::Common::Log;
use pgBackRest::Config::Config;
use pgBackRest::DbVersion;
use pgBackRest::Storage::Storage;
use pgBackRest::Storage::StorageHelper;
use pgBackRest::InfoCommon;
use pgBackRest::Manifest;
use pgBackRest::Protocol::Common;
use pgBackRest::Protocol::Protocol;

use pgBackRestTest::Common::Env::EnvHostTest;
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::Host::HostBackupTest;
use pgBackRestTest::Common::RunTest;

####################################################################################################################################
# initModule
####################################################################################################################################
sub initModule
{
    my $self = shift;

    $self->{strRepoPath} = $self->testPath() . '/repo';
}

####################################################################################################################################
# initTest
####################################################################################################################################
sub initTest
{
    my $self = shift;

    # Create the local file object
    $self->{oStorage} = storageLocal($self->stanza(), $self->{strRepoPath});

    # Create backup info path
    $self->{oStorage}->pathCreate(PATH_REPO_BACKUP, {bCreateParent => true});
}

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Increment the run, log, and decide whether this unit test should be run
    ################################################################################################################################
    if ($self->begin("BackupInfo::confirmDb()"))
    {
        my $oBackupInfo = new pgBackRest::BackupInfo($self->{oStorage}->pathGet(PATH_REPO_BACKUP), false, false);
        $oBackupInfo->create(PG_VERSION_93, WAL_VERSION_93_SYS_ID, '937', '201306121', true);

        my $strBackupLabel = "20170403-175647F";

        $oBackupInfo->set(INFO_BACKUP_SECTION_BACKUP_CURRENT, $strBackupLabel, INFO_BACKUP_KEY_HISTORY_ID,
            $oBackupInfo->get(INFO_BACKUP_SECTION_DB, INFO_BACKUP_KEY_HISTORY_ID));

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oBackupInfo->confirmDb($strBackupLabel, PG_VERSION_93, WAL_VERSION_93_SYS_ID,)}, true,
            'backup db matches');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oBackupInfo->confirmDb($strBackupLabel, PG_VERSION_94, WAL_VERSION_93_SYS_ID,)}, false,
            'backup db wrong version');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oBackupInfo->confirmDb($strBackupLabel, PG_VERSION_93, WAL_VERSION_94_SYS_ID,)}, false,
            'backup db wrong system-id');
    }
}

1;

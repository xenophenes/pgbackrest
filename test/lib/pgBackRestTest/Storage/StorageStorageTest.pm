####################################################################################################################################
# StorageStorageTest.pm - Tests for Storage module.
####################################################################################################################################
package pgBackRestTest::Storage::StorageStorageTest;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use pgBackRest::Config::Config;
use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Protocol::Common;
use pgBackRest::Protocol::RemoteMaster;
use pgBackRest::Storage::Storage;

use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::Host::HostBackupTest;

####################################################################################################################################
# initModule - common objects and variables used by all tests.
####################################################################################################################################
sub initModule
{
    my $self = shift;

    # Local path
    $self->{strPathLocal} = $self->testPath() . '/local';

    # Create local protocol
    $self->{oProtocolLocal} = new pgBackRest::Protocol::Common(
        262144,
        1,
        OPTION_DEFAULT_COMPRESS_LEVEL_NETWORK,
        HOST_PROTOCOL_TIMEOUT);

    # Create local storage
    $self->{oStorageLocal} = new pgBackRest::Storage::Storage(
        '<LOCAL>', new pgBackRest::Storage::Posix::StoragePosix(), $self->pathLocal(), {oProtocol => $self->protocolLocal()});

    # Remote path
    $self->{strPathRemote} = $self->testPath() . '/remote';

    # Create the repo path so the remote won't complain that it's missing
    mkdir($self->pathRemote())
        or confess &log(ERROR, "unable to create repo directory '" . $self->pathRemote() . qw{'});

    # !!! REMOTE IS CURRENTLY BROKEN SO USING LOCAL FOR NOW
    # Create remote protocol
    # $self->{oProtocolRemote} = new pgBackRest::Protocol::RemoteMaster(
    #     BACKUP,
    #     OPTION_DEFAULT_CMD_SSH,
    #     $self->backrestExeOriginal() . ' --stanza=' . $self->stanza() .
    #         ' --type=backup --repo-path=' . $self->pathRemote() . ' --no-config --command=test remote',
    #     262144,
    #     OPTION_DEFAULT_COMPRESS_LEVEL,
    #     OPTION_DEFAULT_COMPRESS_LEVEL_NETWORK,
    #     $self->host(),
    #     $self->backrestUser(),
    #     HOST_PROTOCOL_TIMEOUT);

    # Remove repo path now that the remote is created
    rmdir($self->{strPathRemote})
        or confess &log(ERROR, "unable to remove repo directory '" . $self->pathRemote() . qw{'});

    # Create remote storage
    $self->{oStorageRemote} = new pgBackRest::Storage::Storage(
        '<REMOTE>', new pgBackRest::Storage::Posix::StoragePosix(), $self->pathRemote(),
        # !!! REMOTE IS CURRENTLY BROKEN SO USING LOCAL FOR NOW
        {oProtocol => $self->protocolLocal(), bAllowTemp => true});
}

####################################################################################################################################
# initTest - initialization before each test
####################################################################################################################################
sub initTest
{
    my $self = shift;

    executeTest(
        'ssh ' . $self->backrestUser() . '\@' . $self->host() . ' mkdir -m 700 ' . $self->pathRemote(), {bSuppressStdErr => true});

    executeTest('mkdir -m 700 ' . $self->pathLocal());
}

####################################################################################################################################
# cleanModule - close objects created for tests.
####################################################################################################################################
sub cleanModule
{
    my $self = shift;

    # !!! FIX THIS WHEN REMOTE IS FIXED
    # $self->protocolRemote()->close();
}

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Define test file
    my $strFile = 'file.txt';
    my $strFileCopy = 'file.txt.copy';
    # my $strFileHash = 'bbbcf2c59433f68f22376cd2439d6cd309378df6';
    my $strFileContent = 'TESTDATA';
    my $iFileSize = length($strFileContent);

    # !!! LOTS OF WORK TO FIX THIS FUNCTION
    # Test File->pathGet()
    #---------------------------------------------------------------------------------------------------------------------------
    if ($self->begin("pathGet()"))
    {
        # Test temp file errors
        $self->testException(
            sub {$self->storageLocal()->pathGet(PATH_REPO . '/test', {bTemp => true})},
            ERROR_ASSERT, "temp file not supported for storage type <LOCAL>");
        $self->testException(
            sub {$self->storageRemote()->pathGet()},
            ERROR_ASSERT, "strPathExp is required in Storage::Storage->pathGet");
        # $self->testException(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE, {bTemp => true})},
        #     ERROR_ASSERT, "file part must be defined when temp file specified for path type <REPO:ARCHIVE>");
        # $self->testException(
        #     sub {$self->storageRemote()->pathGet(PATH_SPOOL_ARCHIVE_OUT, {bTemp => true})},
        #     ERROR_ASSERT, "file part must be defined when temp file specified for path type <SPOOL:ARCHIVE:OUT>");
        # $self->testException(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP_TMP, {bTemp => true})},
        #     ERROR_ASSERT, "file part must be defined when temp file specified for path type <REPO:BACKUP:TMP>");

        # Test absolute path
        $self->testResult(sub {$self->storageRemote()->pathGet('/file', {bTemp => true})}, "/file.pgbackrest.tmp", 'absolute path temp');
        $self->testResult(sub {$self->storageRemote()->pathGet('/file')}, "/file", 'absolute path file');

        # Test backup path
        $self->testResult(
            sub {$self->storageRemote()->pathGet(PATH_REPO . '/file')}, $self->storageRemote()->pathBase() . '/file',
            'backup path file');
        $self->testResult(sub {$self->storageRemote()->pathGet(PATH_REPO)}, $self->storageRemote()->pathBase(), 'backup path');

        # Error when stanza not defined
        # $self->testException(
        #     sub {(new pgBackRest::Storage::Storage(undef, $self->storageRemote()->pathBase(), $self->local()))->pathGet(PATH_REPO_BACKUP_TMP)},
        #     ERROR_ASSERT, "strStanza not defined");

        # # Test backup tmp path
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP_TMP . '/file', {bTemp => true})},
        #     $self->storageRemote()->pathBase() . '/temp/db.tmp/file.pgbackrest.tmp',
        #     'backup temp path temp file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP_TMP . '/file')}, $self->storageRemote()->pathBase() . '/temp/db.tmp/file', 'backup temp path file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP_TMP)}, $self->storageRemote()->pathBase() . '/temp/db.tmp', 'backup temp path');
        #
        # # Test archive path
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE, undef)}, $self->storageRemote()->pathBase() . '/archive/db', 'archive path');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE . '/9.3-1')}, $self->storageRemote()->pathBase() . '/archive/db/9.3-1', 'archive id path');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/000000010000000100000001')},
        #     $self->storageRemote()->pathBase() . '/archive/db/9.3-1/0000000100000001/000000010000000100000001',
        #     'archive path file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/000000010000000100000001', {bTemp => true})},
        #     $self->storageRemote()->pathBase() . '/archive/db/9.3-1/0000000100000001/000000010000000100000001.pgbackrest.tmp',
        #     'archive path temp file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/00000001.history')},
        #     $self->storageRemote()->pathBase() . '/archive/db/9.3-1/00000001.history',
        #     'archive path history file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/00000001.history', {bTemp => true})},
        #     $self->storageRemote()->pathBase() . '/archive/db/9.3-1/00000001.history.pgbackrest.tmp',
        #     'archive path history temp file');
        #
        # # Test archive out path
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_SPOOL_ARCHIVE_OUT . '/000000010000000100000001')},
        #     $self->storageRemote()->pathBase() . '/archive/db/out/000000010000000100000001',
        #     'archive out path file');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_SPOOL_ARCHIVE_OUT)}, $self->storageRemote()->pathBase() . '/archive/db/out', 'archive out path');
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_SPOOL_ARCHIVE_OUT . '/000000010000000100000001', {bTemp => true})},
        #     $self->storageRemote()->pathBase() . '/archive/db/out/000000010000000100000001.pgbackrest.tmp',
        #     'archive out path temp file');
        #
        # # Test backup cluster path
        # $self->testResult(
        #     sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP . '/file')}, $self->storageRemote()->pathBase() . '/backup/db/file', 'cluster path file');
        # $self->testResult(sub {$self->storageRemote()->pathGet(PATH_REPO_BACKUP)}, $self->storageRemote()->pathBase() . '/backup/db', 'cluster path');
        #
        # # Test invalid path type
        # $self->testException(sub {$self->storageRemote()->pathGet('<bogus>')}, ERROR_ASSERT, "invalid path type <bogus>");
    }

    ################################################################################################################################
    if ($self->begin('openRead()'))
    {
        my $tContent;

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(
            sub {$self->storageLocal()->openRead($strFile, {bIgnoreMissing => true})}, true, 'ignore missing');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(
            sub {$self->storageLocal()->openRead($strFile)}, ERROR_FILE_MISSING,
            "unable to open '" . $self->storageLocal()->pathBase() . "/${strFile}': No such file or directory");

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest('sudo touch ' . $self->pathLocal() . "/${strFile} && sudo chmod 700 " . $self->pathLocal() . "/${strFile}");

        $self->testException(
            sub {$self->storageLocal()->openRead($strFile)}, ERROR_FILE_OPEN,
            "unable to open '" . $self->storageLocal()->pathBase() . "/${strFile}': Permission denied");

        executeTest('sudo rm ' . $self->pathLocal() . "/${strFile}");

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest("echo -n '${strFileContent}' | tee " . $self->pathLocal() . "/${strFile}");

        my $oFileIO = $self->testResult(sub {$self->storageLocal()->openRead($strFile)}, '[object]', 'open read');

        $self->testResult(sub {$oFileIO->read(\$tContent, $iFileSize)}, $iFileSize, "read $iFileSize bytes");
        $self->testResult($tContent, $strFileContent, 'check read');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(
            sub {$self->storageRemote()->openRead($strFile)}, ERROR_ASSERT,
            'pgBackRest::Storage::Storage->copy: remote operation not supported');
    }
}

####################################################################################################################################
# Getters
####################################################################################################################################
sub host {return '127.0.0.1'}
sub pathLocal {return shift->{strPathLocal}};
sub pathRemote {return shift->{strPathRemote}};
sub protocolLocal {return shift->{oProtocolLocal}};
sub protocolRemote {return shift->{oProtocolRemote}};
sub storageLocal {return shift->{oStorageLocal}};
sub storageRemote {return shift->{oStorageRemote}};

1;

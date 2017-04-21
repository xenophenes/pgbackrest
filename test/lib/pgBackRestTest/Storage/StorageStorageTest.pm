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
        new pgBackRest::Storage::Posix::StoragePosix(), $self->pathLocal(), {oProtocol => $self->protocolLocal()});

    # Remote path
    $self->{strPathRemote} = $self->testPath() . '/remote';

    # Create the repo path so the remote won't complain that it's missing
    mkdir($self->pathRemote())
        or confess &log(ERROR, "unable to create repo directory '" . $self->pathRemote() . qw{'});

    # Create remote protocol
    $self->{oProtocolRemote} = new pgBackRest::Protocol::RemoteMaster(
        BACKUP,
        OPTION_DEFAULT_CMD_SSH,
        $self->backrestExeOriginal() . ' --stanza=' . $self->stanza() .
            ' --type=backup --repo-path=' . $self->pathRemote() . ' --no-config --command=test remote',
        262144,
        OPTION_DEFAULT_COMPRESS_LEVEL,
        OPTION_DEFAULT_COMPRESS_LEVEL_NETWORK,
        $self->host(),
        $self->backrestUser(),
        HOST_PROTOCOL_TIMEOUT);

    # Remove repo path now that the remote is created
    rmdir($self->{strPathRemote})
        or confess &log(ERROR, "unable to remove repo directory '" . $self->pathRemote() . qw{'});

    # Create remote storage
    $self->{oStorageRemote} = new pgBackRest::Storage::Storage(
        new pgBackRest::Storage::Posix::StoragePosix(), $self->pathRemote(),
        {oProtocol => $self->protocolRemote(), bAllowTemp => true});
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

    $self->protocolRemote()->close();
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

    ################################################################################################################################
    if ($self->begin('openRead'))
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

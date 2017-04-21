####################################################################################################################################
# StoragePosixIoTest.pm - Tests for StoragePosixIO module.
####################################################################################################################################
package pgBackRestTest::Storage::StoragePosixIoTest;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Storage::Posix::StoragePosixIO;

use pgBackRestTest::Common::ExecuteTest;

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Test data
    my $strFile = $self->testPath() . qw{/} . 'file.txt';
    my $strFileContent = 'TESTDATA';
    my $iFileLength = length($strFileContent);
    my $iFileLengthHalf = int($iFileLength / 2);

    ################################################################################################################################
    if ($self->begin('new()'))
    {
        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)},
            ERROR_FILE_MISSING,
            "unable to open '${strFile}': No such file or directory");

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest("echo -n '${strFileContent}' | tee ${strFile}");

        $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)}, '[object]', 'open read');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile, {bWrite => true})}, '[object]', 'open write');

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest("chmod 600 ${strFile} && sudo chown root:root ${strFile}");

        $self->testException(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)},
            ERROR_FILE_OPEN, "unable to open '${strFile}': Permission denied");
    }

    ################################################################################################################################
    if ($self->begin('read()'))
    {
        my $tContent;

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest("echo -n '${strFileContent}' | tee ${strFile}");

        my $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)}, '[object]', 'open');
        $self->testException(
            sub {$oPosixIo->read(\$tContent, 1, -1)}, ERROR_FILE_READ, "unable to read '${strFile}': Offset outside string");

        #---------------------------------------------------------------------------------------------------------------------------
        $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)}, '[object]', 'open');

        $self->testResult(sub {$oPosixIo->read(\$tContent, length($strFileContent))}, length($strFileContent), 'read');
        $self->testResult($tContent, $strFileContent, 'check read');

        $self->testResult(sub {$oPosixIo->read(\$tContent, length($strFileContent))}, 0, 'eof');

        #---------------------------------------------------------------------------------------------------------------------------
        $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile)}, '[object]', 'open');

        $self->testResult(sub {$oPosixIo->read(\$tContent, $iFileLengthHalf)}, $iFileLengthHalf, 'read part 1');
        $self->testResult($tContent, substr($strFileContent, 0, $iFileLengthHalf), 'check read');

        $self->testResult(
            sub {$oPosixIo->read(\$tContent, $iFileLength - $iFileLengthHalf, $iFileLengthHalf)}, $iFileLength - $iFileLengthHalf,
            'read part 1');
        $self->testResult($tContent, $strFileContent, 'check read');

        $self->testResult(sub {$oPosixIo->read(\$tContent, 1)}, 0, 'eof');
    }

    ################################################################################################################################
    if ($self->begin('write()'))
    {
        my $tContent = $strFileContent;

        #---------------------------------------------------------------------------------------------------------------------------
        my $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile, {bWrite => true})}, '[object]', 'open');

        $self->testException(
            sub {$oPosixIo->write(\$tContent, -1)}, ERROR_FILE_WRITE,
            "unable to write '/home/ubuntu/test/test-0/file.txt': Negative length");

        #---------------------------------------------------------------------------------------------------------------------------
        $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile, {bWrite => true})}, '[object]', 'open');

        $self->testResult(sub {$oPosixIo->write(\$tContent, $iFileLength)}, $iFileLength, 'write');
        $oPosixIo->close();

        $self->testResult(
            sub {(new pgBackRest::Storage::Posix::StoragePosixIO($strFile))->read(\$tContent, $iFileLength)},
            $iFileLength, 'check write content length');
        $self->testResult($tContent, $strFileContent, 'check write content');

        #---------------------------------------------------------------------------------------------------------------------------
        $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile, {bWrite => true})}, '[object]', 'open');

        $self->testResult(
            sub {$oPosixIo->write(\$tContent, $iFileLengthHalf, 0)}, $iFileLengthHalf, 'write part 1');
        $self->testResult(
            sub {$oPosixIo->write(\$tContent, $iFileLength - $iFileLengthHalf, $iFileLengthHalf)}, $iFileLength - $iFileLengthHalf,
            'write part 2');
        $oPosixIo->close();

        $self->testResult(
            sub {(new pgBackRest::Storage::Posix::StoragePosixIO($strFile))->read(\$tContent, $iFileLength)},
            $iFileLength, 'check write content length');
        $self->testResult($tContent, $strFileContent, 'check write content');
    }

    ################################################################################################################################
    if ($self->begin('close()'))
    {
        #---------------------------------------------------------------------------------------------------------------------------
        my $oPosixIo = $self->testResult(
            sub {new pgBackRest::Storage::Posix::StoragePosixIO($strFile, {bWrite => true})}, '[object]', 'open');

        $self->testResult(sub {$oPosixIo->close()}, true, 'close');

        undef($oPosixIo);
    }
}

1;

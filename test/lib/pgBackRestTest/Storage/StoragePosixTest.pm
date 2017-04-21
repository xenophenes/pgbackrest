####################################################################################################################################
# StoragePosixTest.pm - Tests for StoragePosix module.
####################################################################################################################################
package pgBackRestTest::Storage::StoragePosixTest;
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
use pgBackRest::Storage::Posix::StoragePosix;

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

    ################################################################################################################################
    if ($self->begin('new()'))
    {
        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {new pgBackRest::Storage::Posix::StoragePosix()}, '[object]', 'new');
    }

    ################################################################################################################################
    if ($self->begin('openRead'))
    {
        my $tContent;
        my $oPosix = new pgBackRest::Storage::Posix::StoragePosix();

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(
            sub {$oPosix->openRead($strFile)}, ERROR_FILE_MISSING, "unable to open '${strFile}': No such file or directory");

        #---------------------------------------------------------------------------------------------------------------------------
        executeTest("echo -n '${strFileContent}' | tee ${strFile}");

        $self->testResult(
            sub {$oPosix->openRead($strFile)}, '[object]', 'open read');
    }
}

1;

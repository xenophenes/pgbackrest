####################################################################################################################################
# StorageS3Test.pm - S3 Storage Tests
####################################################################################################################################
package pgBackRestTest::Storage::StorageS3Test;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use pgBackRest::Common::Log;
use pgBackRest::Common::String;
# use pgBackRest::Config::Config;
# use pgBackRest::FileCommon;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Protocol::RemoteMaster;
use pgBackRest::Storage::StorageS3::StorageS3;

# use pgBackRestTest::Common::Host::HostBackupTest;
# use pgBackRestTest::Common::ExecuteTest;

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Get test data

    if (!defined($self->testData()) || split(':', $self->testData()) != 4)
    {
        # confess coalesce($self->testData(), 'UNDEF');

        confess &log(ERROR, 'test requires data: <endpoint>:<region>:<access-key-id>:<secret-access-key>');
    }

    my ($strEndPoint, $strRegion, $strAccessKeyId, $strSecretAccessKey) = split(':', $self->testData());
    &log(INFO,
        "testing with endpoint = ${strEndPoint}, region = ${strRegion}, access-key-id = ${strAccessKeyId}" .
        ", secret-access-key = ${strSecretAccessKey}");

    ################################################################################################################################
    if ($self->begin('StorageS3->new()'))
    {
        my $oS3 = new pgBackRest::Storage::StorageS3::StorageS3($strEndPoint, $strRegion, $strAccessKeyId, $strSecretAccessKey);
        $oS3->manifest('');
    }
}

1;

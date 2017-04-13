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

    ################################################################################################################################
    if ($self->begin('StorageS3->new()'))
    {
        my $oS3 = new pgBackRest::Storage::StorageS3::StorageS3('AKIAISS77TLGHHQLM2CA', XXX);
    }
}

1;

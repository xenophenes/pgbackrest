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
use pgBackRest::Storage::StorageS3::StorageS3;

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Get test data
    my @stryData = split(':', $self->testData());

    if (!defined($self->testData()) || @stryData != 4)
    {
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

        # &log(WARN, "START OBJECT CREATE");
        #
        # for (my $iIndex = 1; $iIndex < 255; $iIndex++)
        # {
        #     # $oS3->put('/dude2.txt', 'DUDEMAN2');
        #     $oS3->put(sprintf('/dude%05X.txt', $iIndex));
        # }
        #
        # &log(WARN, "STOP OBJECT CREATE");

        $oS3->put('/dude1.txt', 'DUDEMAN1');
        $oS3->put('/dude2.txt', 'DUDEMAN2');
        $oS3->remove('/dude2.txt');

        &log(WARN, "START MANIFEST REQUEST");
        my $hManifest = $oS3->manifest('/', {bRecurse => false});

        my @stryFile;

        foreach my $strName (sort(keys(%{$hManifest})))
        {
            if ($hManifest->{$strName}{type} eq 'd')
            {
                &log(WARN, "PATH: ${strName}");
            }
            else
            {
                &log(WARN, "FILE: ${strName}, size: " . $hManifest->{$strName}{size});
                push(@stryFile, "/${strName}");
            }
        }

        # ---
        $oS3->remove(\@stryFile);
    }
}

1;

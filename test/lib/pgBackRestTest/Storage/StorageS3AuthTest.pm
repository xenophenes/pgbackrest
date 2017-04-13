####################################################################################################################################
# StorageS3AuthTest.pm - S3 Storage Authentication Tests
####################################################################################################################################
package pgBackRestTest::Storage::StorageS3AuthTest;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use pgBackRest::Common::Log;
use pgBackRest::Storage::StorageS3::StorageS3Auth;

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    ################################################################################################################################
    if ($self->begin('s3CanonicalRequest'))
    {
        $self->testResult(
            sub {s3CanonicalRequest('bucket.s3.amazonaws.com', 'GET', qw(/), 'list-type=2', '20170606T121212Z')},
            "GET\n/\nlist-type=2\nhost:bucket.s3.amazonaws.com\n" .
                "x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n" .
                "x-amz-date:20170606T121212Z\n\nhost;x-amz-content-sha256;x-amz-date\n" .
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            'canonical request');

        $self->testResult(
            sub {s3CanonicalRequest('bucket.s3.amazonaws.com', 'GET', qw(/), 'list-type=2', '20170606T121212Z',
                {strPayloadHash => '705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9'})},
            "GET\n/\nlist-type=2\nhost:bucket.s3.amazonaws.com\n" .
                "x-amz-content-sha256:705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9\n" .
                "x-amz-date:20170606T121212Z\n\nhost;x-amz-content-sha256;x-amz-date\n" .
                "705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9",
            'canonical request with payload hash (instead of default)');
    }

    ################################################################################################################################
    if ($self->begin('s3SigningKey'))
    {
        $self->testResult(
            sub {unpack('H*', s3SigningKey('20170412', 'us-east-1', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'))},
            '705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9', 'signing key');

        $self->testResult(
            sub {unpack('H*', s3SigningKey('20170412', 'us-east-1', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'))},
            '705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9', 'same signing key from cache');

        $self->testResult(
            sub {unpack('H*', s3SigningKey('20170505', 'us-west-1', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'))},
            'c1a1cb590bbc38ba789c8e5695a1ec0cd7fd44c6949f922e149005a221524c09', 'new signing key');
    }

    ################################################################################################################################
    if ($self->begin('s3StringToSign'))
    {
        $self->testResult(
            sub {s3StringToSign(
                '20170412T141414Z', 'us-east-1', '705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9')},
            "AWS4-HMAC-SHA256\n20170412T141414Z\n20170412/us-east-1/s3/aws4_request\n" .
                "705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9",
            'string to sign');
    }

    ################################################################################################################################
    if ($self->begin('s3Authorization'))
    {
        $self->testResult(
            sub {s3Authorization(
                'us-east-1', 'bucket.s3.amazonaws.com', 'GET', qw(/), 'list-type=2', '20170606T121212Z',
                'AKIAIOSFODNN7EXAMPLE', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY')},
            'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20170606/us-east-1/s3/aws4_request,' .
                'SignedHeaders=host;x-amz-content-sha256;x-amz-date,' .
                'Signature=cb03bf1d575c1f8904dabf0e573990375340ab293ef7ad18d049fc1338fd89b3',
            'canonical request');

        $self->testResult(
            sub {s3Authorization(
                'us-east-1', 'bucket.s3.amazonaws.com', 'GET', qw(/), 'list-type=2', '20170606T121212Z',
                'AKIAIOSFODNN7EXAMPLE', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
                {strPayloadHash => '705636ecdedffc09f140497bcac3be1e8d069008ecc6a8029e104d6291b4e4e9'})},
            'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20170606/us-east-1/s3/aws4_request,' .
                'SignedHeaders=host;x-amz-content-sha256;x-amz-date,' .
                'Signature=5f35b983c794fbb80b9b93d5f86145dfe8d65af34f50ef120ecf03d07193da5a',
            'canonical request');
    }
}

1;

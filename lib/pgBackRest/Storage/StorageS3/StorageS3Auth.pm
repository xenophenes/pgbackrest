####################################################################################################################################
# STORAGE S3 AUTH MODULE
#
# http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3Auth;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
# use Fcntl qw(:mode :flock O_RDONLY O_WRONLY O_CREAT);
# use File::Basename qw(dirname basename);
# use File::Copy qw(cp);
# use File::Path qw(make_path remove_tree);
# use File::stat;
# use IO::Handle;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use POSIX qw(strftime);
# use WWW::Curl::Easy;
# use XML::LibXML;

# use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Wait;
# use pgBackRest::FileCommon;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Version;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant S3                                                     => 's3';
use constant AWS4                                                   => 'AWS4';
use constant AWS4_REQUEST                                           => 'aws4_request';
use constant AWS4_HMAC_SHA256                                       => 'AWS4-HMAC-SHA256';

use constant HEADER_DATE                                            => 'x-amz-date';
use constant HEADER_CONTENT_SHA256                                  => 'x-amz-content-sha256';
use constant HEADER_HOST                                            => 'host';

use constant PAYLOAD_DEFAULT_HASH                                   => sha256_hex('');

####################################################################################################################################
# s3CanonicalRequest
#
#
####################################################################################################################################
sub s3CanonicalRequest
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strHost,
        $strVerb,
        $strUri,
        $strQuery,
        $strDateTime,
        $strPayloadHash,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::s3CanonicalRequest', \@_,
            {name => 'strHost', trace => true},
            {name => 'strVerb', trace => true},
            {name => 'strUri', trace => true},
            {name => 'strQuery', trace => true},
            {name => 'strDateTime', trace => true},
            {name => 'strPayloadHash', optional => true, default => PAYLOAD_DEFAULT_HASH, trace => true},
        );

    # Create the canonical request
    my $strCanonicalRequest =
        "${strVerb}\n${strUri}\n${strQuery}\n" .
        HEADER_HOST . ":${strHost}\n" .
        HEADER_CONTENT_SHA256 . ":${strPayloadHash}\n" .
        HEADER_DATE . ":${strDateTime}\n\n" .
        HEADER_HOST . qw(;) . HEADER_CONTENT_SHA256 . qw(;) . HEADER_DATE . "\n" .
        "${strPayloadHash}";

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strCanonicalRequest', value => $strCanonicalRequest, trace => true}
    );
}

push @EXPORT, qw(s3CanonicalRequest);

####################################################################################################################################
# s3SigningKey
#
# A signing key lasts for seven days, but we'll regenerate every day because it doesn't seem too burdensome.
####################################################################################################################################
my $hSigningKeyCache;                                               # Cache signing keys rather than regenerating them every time

sub s3SigningKey
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strDate,
        $strRegion,
        $strSecretAccessKey,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::s3SigningKey', \@_,
            {name => 'strDate', trace => true},
            {name => 'strRegion', trace => true},
            {name => 'strSecretAccessKey', trace => true},
        );

    # Check for signing key in cache
    my $strSigningKey = $hSigningKeyCache->{$strDate}{$strRegion}{$strSecretAccessKey};

    # If not found then generate it
    if (!defined($strSigningKey))
    {
        my $strDateKey = hmac_sha256($strDate, AWS4 . $strSecretAccessKey);
        my $strRegionKey = hmac_sha256($strRegion, $strDateKey);
        my $strServiceKey = hmac_sha256(S3, $strRegionKey);
        $strSigningKey = hmac_sha256(AWS4_REQUEST, $strServiceKey);

        # Cache the signing key
        $hSigningKeyCache->{$strDate}{$strRegion}{$strSecretAccessKey} = $strSigningKey;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strSigningKey', value => $strSigningKey, trace => true}
    );
}

push @EXPORT, qw(s3SigningKey);

####################################################################################################################################
# s3StringToSign
#
# The string that will be signed by the signing key for authentication.
####################################################################################################################################
sub s3StringToSign
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strDateTime,
        $strRegion,
        $strCanonicalRequestHash,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::s3StringToSign', \@_,
            {name => 'strDateTime', trace => true},
            {name => 'strRegion', trace => true},
            {name => 'strCanonicalRequestHash', trace => true},
        );

    my $strStringToSign =
        AWS4_HMAC_SHA256 . "\n${strDateTime}\n" . substr($strDateTime, 0, 8) . "/${strRegion}/" . S3 . '/' . AWS4_REQUEST . "\n" .
        $strCanonicalRequestHash;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strStringToSign', value => $strStringToSign, trace => true}
    );
}

push @EXPORT, qw(s3StringToSign);

1;

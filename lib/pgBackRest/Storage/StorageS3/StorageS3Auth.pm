####################################################################################################################################
# STORAGE S3 AUTH MODULE
#
# This module contains the functions required to do S3 authentication.  It's a complicated topic and too much to cover here, but
# there is excellent documentation at http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html.
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3Auth;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use POSIX qw(strftime);

use pgBackRest::Common::Log;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant S3                                                     => 's3';
use constant AWS4                                                   => 'AWS4';
use constant AWS4_REQUEST                                           => 'aws4_request';
use constant AWS4_HMAC_SHA256                                       => 'AWS4-HMAC-SHA256';

use constant S3_HEADER_AUTHORIZATION                                => 'authorization';
    push @EXPORT, qw(S3_HEADER_AUTHORIZATION);
use constant S3_HEADER_DATE                                         => 'x-amz-date';
    push @EXPORT, qw(S3_HEADER_DATE);
use constant S3_HEADER_CONTENT_SHA256                               => 'x-amz-content-sha256';
    push @EXPORT, qw(S3_HEADER_CONTENT_SHA256);
use constant S3_HEADER_HOST                                         => 'host';
    push @EXPORT, qw(S3_HEADER_HOST);

use constant PAYLOAD_DEFAULT_HASH                                   => sha256_hex('');
    push @EXPORT, qw(PAYLOAD_DEFAULT_HASH);

####################################################################################################################################
# s3DateTime
#
# Format date/time for authentication.
####################################################################################################################################
sub s3DateTime
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $lTime,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::s3DateTime', \@_,
            {name => 'lTime', default => time(), trace => true},
        );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strDateTime', value => strftime("%Y%m%dT%k%M%SZ", gmtime($lTime)), trace => true}
    );
}

push @EXPORT, qw(s3DateTime);

####################################################################################################################################
# s3CanonicalRequest
#
# Strictly formatted version of the HTTP request used for signing.
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
        S3_HEADER_HOST . ":${strHost}\n" .
        S3_HEADER_CONTENT_SHA256 . ":${strPayloadHash}\n" .
        S3_HEADER_DATE . ":${strDateTime}\n\n" .
        S3_HEADER_HOST . qw(;) . S3_HEADER_CONTENT_SHA256 . qw(;) . S3_HEADER_DATE . "\n" .
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

####################################################################################################################################
# s3Authorization
#
# Authorization string that will be used in the HTTP "authorization" header.
####################################################################################################################################
sub s3Authorization
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strRegion,
        $strHost,
        $strVerb,
        $strUri,
        $strQuery,
        $strDateTime,
        $strAccessKeyId,
        $strSecretAccessKey,
        $strPayloadHash,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::s3CanonicalRequest', \@_,
            {name => 'strRegion', trace => true},
            {name => 'strHost', trace => true},
            {name => 'strVerb', trace => true},
            {name => 'strUri', trace => true},
            {name => 'strQuery', trace => true},
            {name => 'strDateTime', trace => true},
            {name => 'strAccessKeyId', trace => true},
            {name => 'strSecretAccessKey', trace => true},
            {name => 'strPayloadHash', optional => true, default => PAYLOAD_DEFAULT_HASH, trace => true},
        );

    # Create authorization string
    my $strAuthorization =
        AWS4_HMAC_SHA256 . " Credential=${strAccessKeyId}/" . substr($strDateTime, 0, 8) . "/${strRegion}/" . S3 . '/' .
            AWS4_REQUEST . ",SignedHeaders=" . S3_HEADER_HOST . qw(;) . S3_HEADER_CONTENT_SHA256 . qw(;) . S3_HEADER_DATE .
            ",Signature=" .  hmac_sha256_hex(
                s3StringToSign(
                    $strDateTime, $strRegion, sha256_hex(s3CanonicalRequest(
                        $strHost, 'GET', '/', $strQuery, $strDateTime, {strPayloadHash => $strPayloadHash}))),
                s3SigningKey(substr($strDateTime, 0, 8), $strRegion, $strSecretAccessKey));

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strAuthorization', value => $strAuthorization, trace => true}
    );
}

push @EXPORT, qw(s3Authorization);

1;

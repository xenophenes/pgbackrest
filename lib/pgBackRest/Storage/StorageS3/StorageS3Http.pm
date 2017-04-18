####################################################################################################################################
# STORAGE S3 HTTP MODULE
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3Http;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use Exporter qw(import);
    our @EXPORT = qw();
use IO::Socket::SSL;

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Common::Xml;
use pgBackRest::Protocol::Http::HttpClient;
use pgBackRest::Protocol::Http::HttpCommon;
use pgBackRest::Protocol::IO::IO;
use pgBackRest::Storage::StorageS3::StorageS3Auth;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant HTTP_VERB_GET                                          => 'GET';
    push @EXPORT, qw(HTTP_VERB_GET);
use constant HTTP_VERB_POST                                         => 'POST';
    push @EXPORT, qw(HTTP_VERB_POST);
use constant HTTP_VERB_PUT                                          => 'PUT';
    push @EXPORT, qw(HTTP_VERB_PUT);

use constant S3_HEADER_CONTENT_LENGTH                               => 'content-length';
    push @EXPORT, qw(S3_HEADER_CONTENT_LENGTH);
use constant S3_HEADER_TRANSFER_ENCODING                            => 'transfer-encoding';
    push @EXPORT, qw(S3_HEADER_TRANSFER_ENCODING);
use constant S3_HEADER_ETAG                                         => 'etag';
    push @EXPORT, qw(S3_HEADER_ETAG);

use constant S3_RESPONSE_TYPE_NONE                                  => 'none';
    push @EXPORT, qw(S3_RESPONSE_TYPE_NONE);
use constant S3_RESPONSE_TYPE_XML                                   => 'xml';
    push @EXPORT, qw(S3_RESPONSE_TYPE_XML);

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    (
        my $strOperation,
        $self->{strEndPoint},
        $self->{strRegion},
        $self->{strAccessKeyId},
        $self->{strSecretAccessKey},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strEndPoint'},
            {name => 'strRegion'},
            {name => 'strAccessKeyId'},
            {name => 'strSecretAccessKey'},
        );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# httpRequest
#
# Request data from S3.
####################################################################################################################################
sub httpRequest
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strVerb,
        $strUri,
        $hQuery,
        $hHeader,
        $rstrBody,
        $strResponseType,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->httpRequest', \@_,
            {name => 'strVerb', trace => true},
            {name => 'strUri', optional => true, default => '/', trace => true},
            {name => 'hQuery', optional => true, trace => true},
            {name => 'hHeader', optional => true, trace => true},
            {name => 'rstrBody', optional => true, trace => true},
            {name => 'strResponseType', optional => true, default => S3_RESPONSE_TYPE_NONE, trace => true},
        );

    my $strDateTime = s3DateTime();

    my $strContentHash = PAYLOAD_DEFAULT_HASH;
    my $iContentLength = 0;

    if (defined($rstrBody))
    {
        $iContentLength = length($$rstrBody);
        $strContentHash = sha256_hex($$rstrBody);
    }

    $hHeader->{&S3_HEADER_CONTENT_SHA256} = $strContentHash;
    $hHeader->{&S3_HEADER_CONTENT_LENGTH} = $iContentLength;

    $hHeader = s3AuthorizationHeader(
        $self->{strRegion}, $self->{strEndPoint}, $strVerb, $strUri, httpQuery($hQuery), $strDateTime, $hHeader,
        $self->{strAccessKeyId}, $self->{strSecretAccessKey}, $strContentHash);

    my $oHttpClient = new pgBackRest::Protocol::Http::HttpClient(
        $self->{strEndPoint}, $strVerb,
        {strUri => $strUri, hQuery => $hQuery, hRequestHeader => $hHeader, rstrRequestBody => $rstrBody});

    $self->{hResponseHeader} = $oHttpClient->responseHeader();

    # Convert to XML if there is content
    my $oResponseXml;

    if ($strResponseType eq S3_RESPONSE_TYPE_XML)
    {
        if ($oHttpClient->contentLength() == 0)
        {
            confess &log(ERROR, "response type '${strResponseType}' was requested but content length is zero", ERROR_PROTOCOL);
        }

        $oResponseXml = xmlParse(${$oHttpClient->responseBody()});
    }
    #
    # $oHttpClient->close();

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oResponseXml', value => $oResponseXml, trace => true, ref => true}
    );
}

1;

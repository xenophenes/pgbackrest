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
use pgBackRest::Protocol::IO::IO;
use pgBackRest::Storage::StorageS3::StorageS3Auth;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant HTTP_VERB_GET                                          => 'GET';
    push @EXPORT, qw(HTTP_VERB_GET);
use constant HTTP_VERB_PUT                                          => 'PUT';
    push @EXPORT, qw(HTTP_VERB_PUT);

use constant S3_HEADER_CONTENT_LENGTH                               => 'content-length';
    push @EXPORT, qw(S3_HEADER_CONTENT_LENGTH);

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
# uriEncode
#
# Encode query values to conform with URI specs.
####################################################################################################################################
sub uriEncode
{
    my $strString = shift;

    # Only encode if source string is defined
    my $strEncodedString;

    if (defined($strString))
    {
        # Iterate all characters in the string
        for (my $iIndex = 0; $iIndex < length($strString); $iIndex++)
        {
            my $cChar = substr($strString, $iIndex, 1);

            # These characters are reproduced verbatim
            if (($cChar ge 'A' && $cChar le 'Z') || ($cChar ge 'a' && $cChar le 'z') || ($cChar ge '0' && $cChar le '9') ||
                $cChar eq '_' || $cChar eq '-' || $cChar eq '~' || $cChar eq '.')
            {
                $strEncodedString .= $cChar;
            }
            # Forward slash is encoded
            elsif ($cChar eq '/')
            {
                $strEncodedString .= '%2F';
            }
            # All other characters are hex-encoded
            else
            {
                $strEncodedString .= sprintf('%%%02X', ord($cChar));
            }
        }
    }

    return $strEncodedString;
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
        $rstrContent,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->httpRequest', \@_,
            {name => 'strVerb', trace => true},
            {name => 'strUri', default => '/', trace => true},
            {name => 'hQuery', required => false, trace => true},
            {name => 'rstrContent', required => false, trace => true},
        );

    # Generate the query string
    my $strQuery = '';

    foreach my $strParam (sort(keys(%{$hQuery})))
    {
        # Parameters may not be defined - this is OK
        if (defined($hQuery->{$strParam}))
        {
            $strQuery .= ($strQuery eq '' ? '' : '&') . $strParam . '=' . uriEncode($hQuery->{$strParam});
        }
    }

    # my $oCurl = WWW::Curl::Easy->new;
    my $strDateTime = s3DateTime();

    my $oSocket = IO::Socket::SSL->new("$self->{strEndPoint}:443");
    my $oSocketIO = new pgBackRest::Protocol::IO::IO($oSocket, $oSocket, undef, 30, 4 * 1024 * 1024);
    # my $oRequest = new HTTP::Request($strVerb, "https://$self->{strEndPoint}${strUri}?${strQuery}");


    my $strRequestHeader = "${strVerb} ${strUri}?${strQuery} HTTP/1.0" . "\r\n";

    # $oCurl->setopt(CURLOPT_URL, "https://$self->{strEndPoint}${strUri}?${strQuery}");

    $strRequestHeader .= S3_HEADER_HOST . ': ' . $self->{strEndPoint} . "\r\n";
    $strRequestHeader .= S3_HEADER_DATE . ': ' . $strDateTime . "\r\n";

    my $strContentHash = PAYLOAD_DEFAULT_HASH;
    my $iContentLength = 0;

    if (defined($rstrContent))
    {
        $iContentLength = length($$rstrContent);
        $strContentHash = sha256_hex($$rstrContent);
    }

    $strRequestHeader .= S3_HEADER_CONTENT_SHA256 . ': ' . $strContentHash . "\r\n";
    $strRequestHeader .= S3_HEADER_CONTENT_LENGTH . ': ' . $iContentLength . "\r\n";

    $strRequestHeader .=
        S3_HEADER_AUTHORIZATION . ': ' . s3Authorization(
            $self->{strRegion}, $self->{strEndPoint}, $strVerb, $strUri, $strQuery, $strDateTime, $self->{strAccessKeyId},
            $self->{strSecretAccessKey}, $strContentHash) . "\r\n";

    $strRequestHeader .= "\r\n";

    # &log(WARN, "START HEADER WRITE");

    $oSocketIO->bufferWrite(\$strRequestHeader);

    # &log(WARN, "STOP REQUEST SEND");

    # &log(WARN, "REQUEST HEADER:\n" . trim($strRequestHeader));

    if (defined($rstrContent))
    {
        # &log(WARN, "START CONTENT WRITE");
        $oSocketIO->bufferWrite($rstrContent);
    }

    # confess "REQUEST:\n" . $oRequest->as_string();

    # &log(WARN, "START HEADER READ");

    # Read response code
    my ($strProtocol, $iResponseCode, $strResponseMessage) = split(' ', trim($oSocketIO->lineRead()));

    # Read the response headers
    my $strResponseHeader = '';
    my $strHeader = $oSocketIO->lineRead();

    while ($strHeader ne "\r")
    {
        $strResponseHeader .= "${strHeader}\n";
        $strHeader = $oSocketIO->lineRead();
    }

    # &log(WARN, "RESPONSE HEADER:\n" . trim($strResponseHeader));

    # &log(WARN, "START BODY READ");

    my $strResponseBody = '';
    do {} while ($oSocketIO->bufferRead(\$strResponseBody, 1024 * 1024 * 4, length($strResponseBody)) != 0);

    # &log(WARN, "STOP BODY READ");

    # Test response code
    if ($iResponseCode != 200)
    {
        confess &log(ERROR,
            "S3 request error [$iResponseCode]\n${strProtocol} ${iResponseCode} ${strResponseMessage}\r\n${strResponseHeader}" .
            "\n${strResponseBody}", ERROR_PROTOCOL);
    }

    # Create xml object if the response is xml
    my $oResponseXml;

    if (defined($strResponseBody) && $strResponseBody ne '')
    {
        $oResponseXml = xmlParse($strResponseBody);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oResponseXml', value => $oResponseXml, trace => true, ref => true}
    );
}

1;

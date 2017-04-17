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
use constant HTTP_VERB_POST                                         => 'POST';
    push @EXPORT, qw(HTTP_VERB_POST);
use constant HTTP_VERB_PUT                                          => 'PUT';
    push @EXPORT, qw(HTTP_VERB_PUT);

use constant S3_HEADER_CONTENT_LENGTH                               => 'content-length';
    push @EXPORT, qw(S3_HEADER_CONTENT_LENGTH);
use constant S3_HEADER_TRANSFER_ENCODING                            => 'transfer-encoding';
    push @EXPORT, qw(S3_HEADER_TRANSFER_ENCODING);

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
        $hHeader,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->httpRequest', \@_,
            {name => 'strVerb', trace => true},
            {name => 'strUri', default => '/', trace => true},
            {name => 'hQuery', required => false, trace => true},
            {name => 'rstrContent', required => false, trace => true},
            {name => 'hHeader', required => false, trace => true},
        );

    # Generate the query string
    my $strQuery = '';

    # If a hash (the normal case)
    if (ref($hQuery))
    {
        foreach my $strParam (sort(keys(%{$hQuery})))
        {
            # Parameters may not be defined - this is OK
            if (defined($hQuery->{$strParam}))
            {
                $strQuery .= ($strQuery eq '' ? '' : '&') . $strParam . '=' . uriEncode($hQuery->{$strParam});
            }
        }
    }
    elsif (defined($hQuery))
    {
        # Else query string was passed directly as a scalar
        $strQuery = $hQuery;
    }

    my $strDateTime = s3DateTime();

    my $oSocket = IO::Socket::SSL->new("$self->{strEndPoint}:443");
    my $oSocketIO = new pgBackRest::Protocol::IO::IO($oSocket, $oSocket, undef, 30, 4 * 1024 * 1024);

    my $strRequestHeader = "${strVerb} ${strUri}?${strQuery} HTTP/1.1" . "\r\n";

    # $strRequestHeader .= S3_HEADER_HOST . ': ' . $self->{strEndPoint} . "\r\n";
    # $strRequestHeader .= S3_HEADER_DATE . ': ' . $strDateTime . "\r\n";

    my $strContentHash = PAYLOAD_DEFAULT_HASH;
    my $iContentLength = 0;

    if (defined($rstrContent))
    {
        $iContentLength = length($$rstrContent);
        $strContentHash = sha256_hex($$rstrContent);
    }

    $hHeader->{&S3_HEADER_CONTENT_SHA256} = $strContentHash;
    $hHeader->{&S3_HEADER_CONTENT_LENGTH} = $iContentLength;

    $hHeader = s3AuthorizationHeader(
        $self->{strRegion}, $self->{strEndPoint}, $strVerb, $strUri, $strQuery, $strDateTime, $hHeader, $self->{strAccessKeyId},
        $self->{strSecretAccessKey}, $strContentHash);

    # Write headers
    foreach my $strHeader (sort(keys(%{$hHeader})))
    {
        $strRequestHeader .= "${strHeader}: $hHeader->{$strHeader}\r\n";
    }

    $strRequestHeader .= "\r\n";

    # &log(WARN, "START HEADER WRITE");

    $oSocketIO->bufferWrite(\$strRequestHeader);

    # &log(WARN, "STOP REQUEST SEND");

    # &log(WARN, "REQUEST HEADER:\n" . trim($strRequestHeader));

    if (defined($rstrContent))
    {
        my $iTotalSize = length($$rstrContent);
        my $iTotalSent = 0;

        do
        {
            my $strBufferWrite = substr($$rstrContent, $iTotalSent, $iTotalSize - $iTotalSent > 16384 ? 16384 : $iTotalSize - $iTotalSent);

            $iTotalSent += $oSocketIO->bufferWrite(\$strBufferWrite);
            # &log(WARN, "SENT:" . $iTotalSent);
        } while ($iTotalSent < $iTotalSize);

        # &log(WARN, "START CONTENT WRITE");
    }

    # confess "REQUEST:\n" . $oRequest->as_string();

    # &log(WARN, "START HEADER READ");

    # Read response code
    my ($strProtocol, $iResponseCode, $strResponseMessage) = split(' ', trim($oSocketIO->lineRead()));

    # Read the response headers
    $self->{iContentLength} = undef;

    my $strResponseHeader = '';
    my $strHeader = trim($oSocketIO->lineRead());

    while ($strHeader ne '')
    {
        $strResponseHeader .= "${strHeader}\n";

        my $iColonPos = index($strHeader, ':');

        if ($iColonPos == -1)
        {
            confess &log(ERROR, "http header '${strHeader}' requires colon separator", ERROR_PROTOCOL);
        }

        my $strHeaderKey = lc(substr($strHeader, 0, $iColonPos));
        my $strHeaderValue = trim(substr($strHeader, $iColonPos + 1));

        # Store the header
        $self->{hHeader}{$strHeaderKey} = $strHeaderValue;

        if ($strHeaderKey eq S3_HEADER_CONTENT_LENGTH)
        {
            $self->{iContentLength} = $strHeaderValue + 0;

            if ($self->{iContentLength} > 0)
            {
                confess &log(ASSERT, "can't deal with content-length > 0");
            }
        }
        elsif ($strHeaderKey eq S3_HEADER_TRANSFER_ENCODING)
        {
            if ($strHeaderValue eq 'chunked')
            {
                $self->{iContentLength} = -1;
            }
            else
            {
                confess &log(ERROR, "invalid value '${strHeaderValue} for http header '${strHeaderKey}'", ERROR_PROTOCOL);
            }
        }

        # &log(WARN, "HEADER '$strHeader' - $iColonPos - '$strHeaderKey' = '$strHeaderValue'");
        $strHeader = trim($oSocketIO->lineRead());
    }

    # &log(WARN, "RESPONSE HEADER:\n" . trim($strResponseHeader));

    # Content length should have been defined either by content-length or transfer encoding
    if (!defined($self->{iContentLength}))
    {
        confess &log(ERROR, S3_HEADER_CONTENT_LENGTH . ' or ' . S3_HEADER_TRANSFER_ENCODING . ' must be defined', ERROR_PROTOCOL);
    }

    # &log(WARN, "START BODY READ");
    my $oResponseXml;
    my $strResponseBody = '';


    if ($self->{iContentLength} != 0)
    {
        my $iSize = 0;

        while (1)
        {
            my $strChunkLength = trim($oSocketIO->lineRead());
            my $iChunkLength = hex($strChunkLength);
            # &log(WARN, "READ CHUNK $strChunkLength - $iChunkLength");

            last if ($iChunkLength == 0);

            my $strResponseChunk;
            $oSocketIO->bufferRead(\$strResponseChunk, $iChunkLength, 0, true);
            $strResponseBody .= $strResponseChunk;
            $oSocketIO->lineRead();

            $iSize += $iChunkLength;

            # &log(WARN, "REPONSE BODY LENGTH: " . $iSize);
        };

        if (defined($strResponseBody) && $strResponseBody ne '')
        {

            $oResponseXml = xmlParse($strResponseBody);
        }
    }

    # &log(WARN, "FINISHED READ");

    # &log(WARN, "STOP BODY READ");

    # Test response code
    if ($iResponseCode != 200)
    {
        confess &log(ERROR,
            "S3 request error [$iResponseCode]\n${strProtocol} ${iResponseCode} ${strResponseMessage}\r\n${strResponseHeader}" .
            "\n${strResponseBody}", ERROR_PROTOCOL);
    }

    # Create xml object if the response is xml

        # &log(WARN, "RESPONSE:\n${strResponseHeader}\n" . $strResponseBody);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oResponseXml', value => $oResponseXml, trace => true, ref => true}
    );
}

1;

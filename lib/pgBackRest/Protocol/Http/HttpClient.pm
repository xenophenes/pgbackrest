####################################################################################################################################
# HTTP CLIENT MODULE
####################################################################################################################################
package pgBackRest::Protocol::Http::HttpClient;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use IO::Socket::SSL;

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Common::Xml;
use pgBackRest::Protocol::Http::HttpCommon;
use pgBackRest::Protocol::IO::IO;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant HTTP_VERB_GET                                          => 'GET';
    push @EXPORT, qw(HTTP_VERB_GET);
use constant HTTP_VERB_POST                                         => 'POST';
    push @EXPORT, qw(HTTP_VERB_POST);
use constant HTTP_VERB_PUT                                          => 'PUT';
    push @EXPORT, qw(HTTP_VERB_PUT);

use constant HTTP_HEADER_CONTENT_LENGTH                               => 'content-length';
    push @EXPORT, qw(HTTP_HEADER_CONTENT_LENGTH);
use constant HTTP_HEADER_TRANSFER_ENCODING                            => 'transfer-encoding';
    push @EXPORT, qw(HTTP_HEADER_TRANSFER_ENCODING);

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
        $self->{strHost},
        $self->{strVerb},
        $self->{strUri},
        $self->{hQuery},
        $self->{hHeader},
        my $rstrContent,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strHost', trace => true},
            {name => 'strVerb', trace => true},
            {name => 'strUri', optional => true, default => qw(/), trace => true},
            {name => 'hQuery', optional => true, trace => true},
            {name => 'hHeader', optional => true, trace => true},
            {name => 'rstrContent', optional => true, trace => true},
        );

    # Generate the query string
    my $strQuery = httpQuery($self->{hQuery});

    # Construct the request headers
    $self->{strRequestHeader} = "$self->{strVerb} $self->{strUri}?${strQuery} HTTP/1.1" . "\r\n";

    foreach my $strHeader (sort(keys(%{$hHeader})))
    {
        $self->{strRequestHeader} .= "${strHeader}: $hHeader->{$strHeader}\r\n";
    }

    $self->{strRequestHeader} .= "\r\n";

    # Connect to the server
    my $oSocket = IO::Socket::SSL->new("$self->{strHost}:443");

    # Create the buffered IO object
    my $oSocketIO = new pgBackRest::Protocol::IO::IO($oSocket, $oSocket, undef, 30, 4 * 1024 * 1024);

    # Write request headers
    $oSocketIO->bufferWrite(\$self->{strRequestHeader});

    # Write content
    if (defined($rstrContent))
    {
        my $iTotalSize = length($$rstrContent);
        my $iTotalSent = 0;

        do
        {
            my $strBufferWrite = substr(
                $$rstrContent, $iTotalSent, $iTotalSize - $iTotalSent > 16384 ? 16384 : $iTotalSize - $iTotalSent);

            $iTotalSent += $oSocketIO->bufferWrite(\$strBufferWrite);
        } while ($iTotalSent < $iTotalSize);
    }

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

        $strHeader = trim($oSocketIO->lineRead());
    }

    # Test response code
    if ($iResponseCode != 200)
    {
        confess &log(ERROR,
            "S3 request error [$iResponseCode]\n${strProtocol} ${iResponseCode} ${strResponseMessage}\r\n${strResponseHeader}" .
            "\n" . $self->responseBody(), ERROR_PROTOCOL);
    }

    # Content length should have been defined either by content-length or transfer encoding
    if (!defined($self->{iContentLength}))
    {
        confess &log(ERROR,
            HTTP_HEADER_CONTENT_LENGTH . ' or ' . HTTP_HEADER_TRANSFER_ENCODING . ' must be defined', ERROR_PROTOCOL);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# responseBody
####################################################################################################################################
sub responseBody
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->responseBody'
        );

    # Error if there is no response body
    if ($self->{iContentLength} == 0)
    {
        confess &log(ERROR, 'content length is zero', ERROR_PROTOCOL);
    }

    # Read response body
    my $strResponseBody = '';
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
    };

    if (defined($strResponseBody) && $strResponseBody ne '')
    {
        $strResponseBody = undef;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'rstrResponseBody', value => \$strResponseBody}
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
# Properties.
####################################################################################################################################
sub contentLength {shift->{iContentLength}}                         # Content length if available (-1 means not known yet)

1;

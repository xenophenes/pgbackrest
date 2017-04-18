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
        $self->{hRequestHeader},
        my $rstrRequestBody,
        $self->{iProtocolTimeout},
        $self->{iBufferSize},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strHost', trace => true},
            {name => 'strVerb', trace => true},
            {name => 'strUri', optional => true, default => qw(/), trace => true},
            {name => 'hQuery', optional => true, trace => true},
            {name => 'hRequestHeader', optional => true, trace => true},
            {name => 'rstrRequestBody', optional => true, trace => true},
            {name => 'iProtocolTimeout', optional => true, default => 30, trace => true},
            {name => 'iBufferSize', optional => true, default => 32768, trace => true},
        );

    # Generate the query string
    my $strQuery = httpQuery($self->{hQuery});

    # Construct the request headers
    $self->{strRequestHeader} = "$self->{strVerb} $self->{strUri}?${strQuery} HTTP/1.1" . "\r\n";

    foreach my $strHeader (sort(keys(%{$self->{hRequestHeader}})))
    {
        $self->{strRequestHeader} .= "${strHeader}: $self->{hRequestHeader}->{$strHeader}\r\n";
    }

    $self->{strRequestHeader} .= "\r\n";

    # &log(WARN, "REQUEST HEADER\n$self->{strRequestHeader}");

    # Connect to the server
    $self->{oSocket} = IO::Socket::SSL->new("$self->{strHost}:443");

    # Create the buffered IO object
    my $oSocketIO = new pgBackRest::Protocol::IO::IO(
        $self->{oSocket}, $self->{oSocket}, undef, $self->{iProtocolTimeout}, $self->{iBufferSize});

    # Write request headers
    $oSocketIO->bufferWrite(\$self->{strRequestHeader});

    # Write content
    # !!! NEEDS TO BE OPTIMIZED
    if (defined($rstrRequestBody))
    {
        my $iTotalSize = length($$rstrRequestBody);
        my $iTotalSent = 0;

        do
        {
            my $strBufferWrite = substr(
                $$rstrRequestBody, $iTotalSent, $iTotalSize - $iTotalSent > 16384 ? 16384 : $iTotalSize - $iTotalSent);

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
        $self->{hResponseHeader}{$strHeaderKey} = $strHeaderValue;

        if ($strHeaderKey eq HTTP_HEADER_CONTENT_LENGTH)
        {
            $self->{iContentLength} = $strHeaderValue + 0;

            if ($self->{iContentLength} > 0)
            {
                confess &log(ASSERT, "can't deal with content-length > 0");
            }
        }
        elsif ($strHeaderKey eq HTTP_HEADER_TRANSFER_ENCODING)
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

    # &log(WARN, "RESPONSE HEADER\n${strResponseHeader}");

    # Test response code
    if ($iResponseCode != 200)
    {
        confess &log(ERROR,
            "S3 request error [$iResponseCode]\n${strProtocol} ${iResponseCode} ${strResponseMessage}\r\n${strResponseHeader}" .
            "\n" . ${$self->responseBody()}, ERROR_PROTOCOL);
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
# close/DESTROY - close the HTTP connection
####################################################################################################################################
sub close
{
    my $self = shift;

    # Only close if the socket is open
    if (defined($self->{oSocket}))
    {
        $self->{oSocket}->close();
        undef($self->{oSocket});
    }
}

sub DESTROY {shift->close()}

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

    # Create the buffered IO object
    my $oSocketIO = new pgBackRest::Protocol::IO::IO(
        $self->{oSocket}, undef, undef, $self->{iProtocolTimeout}, $self->{iBufferSize});

    # Read response body
    my $strResponseBody = undef;
    my $iSize = 0;

    while (1)
    {
        my $strChunkLength = trim($oSocketIO->lineRead());
        my $iChunkLength = hex($strChunkLength);

        last if ($iChunkLength == 0);

        # !!! NEEDS TO BE OPTIMIZED
        my $strResponseChunk;
        $oSocketIO->bufferRead(\$strResponseChunk, $iChunkLength, 0, true);
        $strResponseBody .= $strResponseChunk;
        $oSocketIO->lineRead();

        $iSize += $iChunkLength;
    };

    $self->close();

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'rstrResponseBody', value => \$strResponseBody}
    );
}

####################################################################################################################################
# Properties.
####################################################################################################################################
sub contentLength {shift->{iContentLength}}                         # Content length if available (-1 means not known yet)
sub responseHeader {shift->{hResponseHeader}}                       # Response header
sub requestHeader {shift->{hResponseHeader}}                        # Request header

1;

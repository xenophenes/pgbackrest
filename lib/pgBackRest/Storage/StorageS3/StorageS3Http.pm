####################################################################################################################################
# STORAGE S3 HTTP MODULE
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3Http;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use WWW::Curl::Easy;

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::Xml;
use pgBackRest::Storage::StorageS3::StorageS3Auth;

####################################################################################################################################
# Constants
####################################################################################################################################
use constant HTTP_VERB_GET                                          => 'GET';
    push @EXPORT, qw(HTTP_VERB_GET);

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
# Encode query values so to conform with URI specs
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

            if (($cChar ge 'A' && $cChar le 'Z') || ($cChar ge 'a' && $cChar le 'z') || ($cChar ge '0' && $cChar le '9') ||
                $cChar eq '_' || $cChar eq '-' || $cChar eq '~' || $cChar eq '.')
            {
                $strEncodedString .= $cChar;
            }
            elsif ($cChar eq '/')
            {
                $strEncodedString .= '%2F';
            }
            else
            {
                $strEncodedString .= sprintf("%%%02X", ord($cChar));
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
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->httpRequest', \@_,
            {name => 'strVerb', trace => true},
            {name => 'strUri', default => '/', trace => true},
            {name => 'hQuery', required => false, trace => true},
        );

    my $oCurl = WWW::Curl::Easy->new;
    my $strDateTime = s3DateTime();

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

    $oCurl->setopt(CURLOPT_URL, "https://$self->{strEndPoint}?${strQuery}");

    my @myheaders;
    $myheaders[0] = S3_HEADER_HOST . ": $self->{strEndPoint}";
    $myheaders[1] = S3_HEADER_DATE . ": ${strDateTime}";
    $myheaders[2] = S3_HEADER_CONTENT_SHA256 . qw(:) . PAYLOAD_DEFAULT_HASH;
    $myheaders[3] =
        S3_HEADER_AUTHORIZATION . qw(:) . s3Authorization(
            $self->{strRegion}, $self->{strEndPoint}, 'GET', '/', $strQuery, $strDateTime, $self->{strAccessKeyId},
            $self->{strSecretAccessKey});

    $oCurl->setopt(CURLOPT_HTTPHEADER, \@myheaders);

    # A filehandle, reference to a scalar or reference to a typeglob can be used here.
    my $strResponse = '';
    $oCurl->setopt(CURLOPT_WRITEFUNCTION, sub {$strResponse .= $_[0]; return length($_[0])});

    # Starts the actual request
    my $iCode = $oCurl->perform;

    # Looking at the results...
    if ($iCode == 0)
    {
        my $iResponseCode = $oCurl->getinfo(CURLINFO_HTTP_CODE);

        if ($iResponseCode != 200)
        {
            confess &log(ERROR,
                "S3 request error [$iResponseCode]" . (defined($strResponse) ? ": ${strResponse}" : ''), ERROR_PROTOCOL);
        }
    }
    else
    {
        confess &log(ERROR,
            "http request error [$iCode] " . $oCurl->strerror($iCode) . ': ' . $oCurl->errbuf, ERROR_HOST_CONNECT);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oResponseXml', value => xmlParse(\$strResponse), trace => true, ref => true}
    );
}

1;

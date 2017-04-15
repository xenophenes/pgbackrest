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
        $strQuery,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->httpRequest', \@_,
            {name => 'strVerb', trace => true},
            {name => 'strUri', default => '/', trace => true},
            {name => 'strQuery', trace => true},
        );

    my $oCurl = WWW::Curl::Easy->new;
    my $strDateTime = s3DateTime();

    $oCurl->setopt(CURLOPT_URL, "https://$self->{strEndPoint}?${strQuery}");

    my @myheaders;
    $myheaders[0] = S3_HEADER_HOST . ": $self->{strEndPoint}";
    $myheaders[1] = S3_HEADER_DATE . ": ${strDateTime}";
    $myheaders[2] = S3_HEADER_CONTENT_SHA256 . qw(:) . PAYLOAD_DEFAULT_HASH;
    $myheaders[3] =
        S3_HEADER_AUTHORIZATION . qw(:) . s3Authorization(
            $self->{strRegion}, $self->{strEndPoint}, 'GET', '/', $strQuery, $strDateTime, $self->{strAccessKeyId},
            $self->{strSecretAccessKey});

        # &log(WARN, "HEADERS: " . join("\n", @myheaders));

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
        {name => 'rstrResponse', value => \$strResponse, trace => true, ref => true}
    );
}

1;

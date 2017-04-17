####################################################################################################################################
# STORAGE S3 MODULE
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3;
use parent 'pgBackRest::Storage::StorageS3::StorageS3Http';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

# use Exporter qw(import);
#     our @EXPORT = qw();
# use Fcntl qw(:mode :flock O_RDONLY O_WRONLY O_CREAT);
# use File::Basename qw(dirname basename);
# use File::Copy qw(cp);
# use File::Path qw(make_path remove_tree);
# use File::stat;
# use IO::Handle;
# use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
# use POSIX qw(strftime);
# use WWW::Curl::Easy;
# use XML::LibXML;
use Digest::MD5 qw(md5_base64);

# use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::Xml;
# use pgBackRest::Storage::StorageS3::StorageS3Auth;
use pgBackRest::Storage::StorageS3::StorageS3Http;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Wait;
# use pgBackRest::FileCommon;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Version;

####################################################################################################################################
# Query constants
####################################################################################################################################
use constant S3_QUERY_CONTINUATION_TOKEN                            => 'continuation-token';
use constant S3_QUERY_DELIMITER                                     => 'delimiter';
use constant S3_QUERY_LIST_TYPE                                     => 'list-type';
use constant S3_QUERY_PREFIX                                        => 'prefix';

####################################################################################################################################
# put
####################################################################################################################################
sub put
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFile,
        $strContent,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->put', \@_,
            {name => 'strFile'},
            {name => 'strContent', required => false},
        );

    # Put a file
    my $oResponse = $self->httpRequest(
        HTTP_VERB_PUT, $strFile, undef, defined($strContent) ? (ref($strContent) ? $strContent : \$strContent) : undef);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bResult', value => true}
    );
}

####################################################################################################################################
# putMultiInit
####################################################################################################################################
sub putMultiInit
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFile,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->putMultiInit', \@_,
            {name => 'strFile'},
        );

    my $oResponse = $self->httpRequest(HTTP_VERB_POST, $strFile, 'uploads=');

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strUploadId', value => xmlTagText($oResponse, 'UploadId')}
    );
}

####################################################################################################################################
# putMulti
####################################################################################################################################
sub putMulti
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFile,
        $strUploadId,
        $iPartNo,
        $rstrContent,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->putMulti', \@_,
            {name => 'strFile'},
            {name => 'strUploadId'},
            {name => 'iPartNo'},
            {name => 'rstrContent'},
        );

    # Put a file
    my $hHeader = {'content-md5' => md5_base64($$rstrContent) . '=='};

    # Put a file
    $self->httpRequest(
        HTTP_VERB_PUT, $strFile, {'partNumber' => $iPartNo, 'uploadId' => $strUploadId}, $rstrContent, $hHeader);

    # use Data::Dumper; confess Dumper($self->{hHeader});
    my $strETag = $self->{hHeader}{'etag'};

    if (!defined($strETag))
    {
        confess &log(ERROR, 'etag header not defined');
    }

    push(@{$self->{hMultiPart}{$strUploadId}}, $strETag);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strETag', value => $strETag}
    );
}

####################################################################################################################################
# putMultiComplete
####################################################################################################################################
sub putMultiComplete
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFile,
        $strUploadId,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->put', \@_,
            {name => 'strFile'},
            {name => 'strUploadId'},
        );

    my $strXml = XML_HEADER . '<CompleteMultipartUpload>';
    my $iPartNo = 0;

    foreach my $strETag (@{$self->{hMultiPart}{$strUploadId}})
    {
        $iPartNo++;

        $strXml .= "<Part><PartNumber>${iPartNo}</PartNumber><ETag>${strETag}</ETag></Part>";
    }

    $strXml .= '</CompleteMultipartUpload>';

    # confess "COMPLETE: " . $strXml;

    my $hHeader = {'content-md5' => md5_base64($strXml) . '=='};

    # Put a file
    my $oResponse = $self->httpRequest(HTTP_VERB_POST, $strFile, {'uploadId' => $strUploadId}, \$strXml, $hHeader);
    my $strETag = xmlTagText($oResponse, "ETag");
    #
    # if (!defined($strETag))
    # {
    #
    # }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strETag', value => $strETag}
    );
}

####################################################################################################################################
# manifest
####################################################################################################################################
sub manifest
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPath,
        $bRecurse,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->manifest', \@_,
            {name => 'strPath'},
            {name => 'bRecurse', optional => true, default => true},
            # Optional parameters not part of the driver spec
            # {name => 'bRecurse', optional => true, default => true},
        );

    # Determine the prefix (this is the search patch within the bucket
    my $strPrefix = $strPath eq '/' ? undef : "${strPath}/";

    # A delimiter must be used if recursion is not desired
    my $strDelimiter = $bRecurse ? undef : '/';

    # Hash to hold the manifest
    my $hManifest;

    # Continuation token - returned from requests where there is more data to be fetched
    my $strContinuationToken;

    my $iFileTotal = 0;
    my $iPathTotal = 0;

    do
    {
        # Get the file list
        my $oResponse = $self->httpRequest(
            HTTP_VERB_GET, undef,
            {&S3_QUERY_LIST_TYPE => 2, &S3_QUERY_PREFIX => $strPrefix, &S3_QUERY_DELIMITER => $strDelimiter,
                &S3_QUERY_CONTINUATION_TOKEN => $strContinuationToken});

        foreach my $oFile (xmlTagChildren($oResponse, "Contents"))
        {
            my $strName = xmlTagText($oFile, "Key");
            $hManifest->{$strName}->{type} = 'f';
            $hManifest->{$strName}->{size} = xmlTagText($oFile, "Size");
            $iFileTotal++;
        }


        foreach my $oPath (xmlTagChildren($oResponse, "CommonPrefixes"))
        {
            my $strName = xmlTagText($oPath, "Prefix");
            $hManifest->{$strName}->{type} = 'd';
            $iPathTotal++;
        }

        &log(WARN, "PATH = ${iPathTotal}, FILE = ${iFileTotal}");

        $strContinuationToken = xmlTagText($oResponse, "NextContinuationToken", false);
    }
    while (defined($strContinuationToken));

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hManifest', value => $hManifest}
    );
}

####################################################################################################################################
# remove
####################################################################################################################################
sub remove
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $rstryFile,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->put', \@_,
            {name => 'rstryFile'},
        );

    # If stryFile is a scalar, convert to an array
    my $rstryFileAll = ref($rstryFile) ? $rstryFile : [$rstryFile];

    do
    {
        my $strFile = shift(@{$rstryFileAll});
        my $iTotal = 0;
        my $strXml = XML_HEADER . '<Delete><Quiet>true</Quiet>';

        while (defined($strFile))
        {
            $iTotal++;
            $strXml .= '<Object><Key>' . substr($strFile, 1) . '</Key></Object>';

            $strFile = $iTotal < 1000 ? shift(@{$rstryFileAll}) : undef;
        }

        $strXml .= '</Delete>';

        my $hHeader = {'content-md5' => md5_base64($strXml) . '=='};

        # Put a file
        my $oResponse = $self->httpRequest(HTTP_VERB_POST, undef, 'delete=', \$strXml, $hHeader);
    }
    while (@{$rstryFileAll} > 0);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bResult', value => true}
    );
}

1;

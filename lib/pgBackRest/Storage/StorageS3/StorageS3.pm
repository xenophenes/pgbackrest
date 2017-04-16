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

1;

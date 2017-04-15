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

        # @truncated = $root->getElementsByTagName("NextContinuationToken");
        # &log(WARN, "TOKEN: " . $truncated[0]->textContent());
        # &log(WARN, "KEY COUNT: " . xmlTagInt($oReponse, "KeyCount"));

        foreach my $oFile (xmlTagChildren($oResponse, "Contents"))
        {
            my $strName = xmlTagText($oFile, "Key");
            $hManifest->{$strName}->{type} = 'f';
            $iFileTotal++;
        }


        foreach my $oPath (xmlTagChildren($oResponse, "CommonPrefixes"))
        {
            my $strName = xmlTagText($oPath, "Prefix");
            $hManifest->{$strName}->{type} = 'd';
            $iPathTotal++;
        }

        &log(WARN, "PATH = ${iPathTotal}, FILE = ${iFileTotal}");
        #
        # if (xmlTagBool($oResponse, "IsTruncated"))
        # {
        $strContinuationToken = xmlTagText($oResponse, "NextContinuationToken", false);
        #
        # if (defined($strContinuationToken))
        # {
        #     &log(WARN, "LOOPING on $strContinuationToken");
        # }
        #     &log(WARN, "CONTINUE TOKEN = $strContinuationToken");
        # }
        # else
        # {
        #     $strContinuationToken = xmlTagText($oResponse, "NextContinuationToken")
        # }
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

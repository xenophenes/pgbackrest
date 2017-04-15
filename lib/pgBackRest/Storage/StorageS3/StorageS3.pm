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
use XML::LibXML;

# use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
# use pgBackRest::Storage::StorageS3::StorageS3Auth;
use pgBackRest::Storage::StorageS3::StorageS3Http;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Wait;
# use pgBackRest::FileCommon;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Version;

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
            {name => 'bRecurse', optional => true},
        );

    # Generate the manifest
    my $hManifest;

    my $response_body = $self->httpRequest(
        HTTP_VERB_GET, undef, 'delimiter=%2F&list-type=2&prefix=backup%2Fmain%2F20170215-151600F%2Fpg_data%2F');

    # confess "RESPONSE: $response_body\n";
    my $doc = XML::LibXML->load_xml(string => $response_body);
    # use Data::Dumper; confess $doc->toString();
    my $root = $doc->documentElement();

    my @truncated = $root->getElementsByTagName("IsTruncated");
    &log(WARN, "TRUNCATED: " . $truncated[0]->textContent());
    # @truncated = $root->getElementsByTagName("NextContinuationToken");
    # &log(WARN, "TOKEN: " . $truncated[0]->textContent());
    @truncated = $root->getElementsByTagName("KeyCount");
    &log(WARN, "KEY COUNT: " . $truncated[0]->textContent());

    my @nodes = $root->getChildrenByTagName("Contents");
    &log(WARN, "FOUND " . @nodes . " FILES");

    foreach my $oFile (@nodes)
    {
        my @name = $oFile->getElementsByTagName("Key");
        &log(WARN, "FILE: " . $name[0]->textContent());
    }

    my @oyPath = $root->getChildrenByTagName("CommonPrefixes");
    &log(WARN, "FOUND " . @oyPath . " PATHS");

    foreach my $oPath (@oyPath)
    {
        my @oPathKey = $oPath->getElementsByTagName("Prefix");
        &log(WARN, "PATH: " . $oPathKey[0]->textContent());
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hManifest', value => $hManifest}
    );
}

1;

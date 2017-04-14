####################################################################################################################################
# STORAGE S3 MODULE
####################################################################################################################################
package pgBackRest::Storage::StorageS3::StorageS3;

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
use WWW::Curl::Easy;
use XML::LibXML;

# use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Storage::StorageS3::StorageS3Auth;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Wait;
# use pgBackRest::FileCommon;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Version;

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
        $self->{strAccessKeyId},
        $self->{strSecretAccessKey},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strAccessKeyId'},
            {name => 'strSecretAccessKey'},
        );

        BEGIN { $| = 1 }

        my $oCurl = WWW::Curl::Easy->new;

        # Generate dates to be used
        my $strDateTime = s3DateTime;

        # Request info
        my $strBucket = 'pgbackrest-dev';
        my $strService = 's3.amazonaws.com';
        my $strHost = "${strBucket}.${strService}";
        # my $strQuery = 'list-type=2&prefix=archive%2Fmain%2F9.5-1%2F0000000100000000%2F';
        my $strQuery = 'delimiter=%2F&list-type=2&prefix=backup%2Fmain%2F20170215-151600F%2Fpg_data%2F';
        my $strRegion = 'us-east-1';

        # $oCurl->setopt(CURLOPT_HEADER, true);
        # $oCurl->setopt(CURLOPT_VERBOSE, true);
        $oCurl->setopt(CURLOPT_URL, "https://${strService}?${strQuery}");

        my @myheaders;
        $myheaders[0] = S3_HEADER_HOST . ": ${strHost}";
        $myheaders[1] = S3_HEADER_DATE . ": ${strDateTime}";
        $myheaders[2] = S3_HEADER_CONTENT_SHA256 . qw(:) . PAYLOAD_DEFAULT_HASH;
        $myheaders[3] =
            S3_HEADER_AUTHORIZATION . qw(:) . s3Authorization(
                $strRegion, $strHost, 'GET', '/', $strQuery, $strDateTime, $self->{strAccessKeyId}, $self->{strSecretAccessKey});

        # &log(WARN, "HEADERS: " . join("\n", @myheaders));

        $oCurl->setopt(CURLOPT_HTTPHEADER, \@myheaders);

        # A filehandle, reference to a scalar or reference to a typeglob can be used here.
        my $response_body = '';
        $oCurl->setopt(CURLOPT_WRITEFUNCTION, sub {$response_body .= $_[0]; return length($_[0]) });

        # Starts the actual request
        my $retcode = $oCurl->perform;

        # Looking at the results...
        if ($retcode == 0) {
                my $response_code = $oCurl->getinfo(CURLINFO_HTTP_CODE);
                print("\nOK [$response_code]\n");
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

                # judge result and next action based on $response_code
                # print("Received response: $response_body\n");
        } else {
                # Error code, type of error, error message
                print("AAA An error happened: $retcode ".$oCurl->strerror($retcode)." ".$oCurl->errbuf."\n");
        }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

1;

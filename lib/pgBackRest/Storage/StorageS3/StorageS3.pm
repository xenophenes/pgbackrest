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
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use POSIX qw(strftime);
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

        # my $strTest = hmac_sha256_hex('dude', 'dude');
        # my $strTest = sha256_hex("GET\n/test.txt\n\nhost:examplebucket.s3.amazonaws.com\nrange:bytes=0-9\n" .
        #     "x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n" .
        #     "x-amz-date:20130524T000000Z\n\n" .
        #     "host;range;x-amz-content-sha256;x-amz-date\n" .
        #     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        # confess $strTest;

        # Generate dates to be used
        my $strDate = strftime("%Y%m%d", gmtime);
        my $strDateTime = strftime("%Y%m%dT%k%M%SZ", gmtime);

        # Request info
        my $strBucket = 'pgbackrest-dev';
        my $strService = 's3.amazonaws.com';
        my $strHost = "${strBucket}.${strService}";
        my $strQuery = 'list-type=2';
        my $strPayloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        my $strRegion = 'us-east-1';
        my $strRegionService = 's3';
        my $strScope = "${strDate}/${strRegion}/${strRegionService}/aws4_request";
        #
        # # Create the canonical request
        # my $strCanonicalRequest =
        #     ;

        # &log(WARN, "CANONICAL REQUEST: ${strCanonicalRequest}");

        # Create the String to Sign
        # my $strStringToSign =
        #     s3StringToSign($strDateTime, $strRegion, sha256_hex($strCanonicalRequest));

        # &log(WARN, "STRING TO SIGN: ${strStringToSign}");

        # $oCurl->setopt(CURLOPT_HEADER, true);
        # $oCurl->setopt(CURLOPT_VERBOSE, true);
        $oCurl->setopt(CURLOPT_URL, "https://${strService}?${strQuery}");

        my @myheaders;
        $myheaders[0] = "Host: ${strHost}";
        $myheaders[1] = "x-amz-date: ${strDateTime}";
        $myheaders[2] = "x-amz-content-sha256: ${strPayloadHash}";
        $myheaders[3] =
            "Authorization: AWS4-HMAC-SHA256 " .
            "Credential=$self->{strAccessKeyId}/${strScope}," .
            "SignedHeaders=host;x-amz-content-sha256;x-amz-date," .
            "Signature=" .  hmac_sha256_hex(
                s3StringToSign(
                    $strDateTime, $strRegion, sha256_hex(s3CanonicalRequest($strHost, 'GET', '/', $strQuery, $strDateTime))),
                s3SigningKey($strDate, $strRegion, $self->{strSecretAccessKey}));
        # $myheaders[4] = "Content-Type: text/plain";

        # &log(WARN, "HEADERS: " . join("\n", @myheaders));

        $oCurl->setopt(CURLOPT_HTTPHEADER, \@myheaders);

        # eval
        # {
        #     &log(WARN, "GOT HERE");
        #     $oCurl->setopt(
        #         CURLOPT_HTTPHEADER,
        #         "Host: pgbackrest-dev.s3.amazonaws.com");
        #     # \nx-amz-date: 20160430T233541Z\nAuthorization: beepboop\nContent-Type: text/plain
        #     return 1;
        # } or do
        # {
        #     &log(WARN, "AND HERE");
        #     # &log(WARN, $oCurl->errbuf);
        #     exit 1;
        # };

        # A filehandle, reference to a scalar or reference to a typeglob can be used here.
        my $response_body = '';
        $oCurl->setopt(CURLOPT_WRITEFUNCTION, sub {$response_body .= $_[0]; return length($_[0]) });

        # Starts the actual request
        # print "DUDE\n";
        my $retcode = $oCurl->perform;

        # Looking at the results...
        if ($retcode == 0) {
                my $response_code = $oCurl->getinfo(CURLINFO_HTTP_CODE);
                print("\nOK [$response_code]\n");
                # print("$response_body\n");
                my $doc = XML::LibXML->load_xml(string => $response_body);
                # use Data::Dumper; confess $doc->toString();
                my $root = $doc->documentElement();
                my @nodes = $root->getChildrenByTagName("Contents");
                &log(WARN, "FOUND " . @nodes . " FILES");

                my @truncated = $root->getElementsByTagName("IsTruncated");
                &log(WARN, "TRUNCATED: " . $truncated[0]->textContent());
                @truncated = $root->getElementsByTagName("NextContinuationToken");
                &log(WARN, "TOKEN: " . $truncated[0]->textContent());
                @truncated = $root->getElementsByTagName("KeyCount");
                &log(WARN, "KEY COUNT: " . $truncated[0]->textContent());

                foreach my $oFile (@nodes)
                {
                    my @name = $oFile->getElementsByTagName("Key");
                    # &log(WARN, "FILE: " . $name[0]->textContent());
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

####################################################################################################################################
# HTTP COMMON MODULE
####################################################################################################################################
package pgBackRest::Protocol::Http::HttpCommon;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
# use pgBackRest::Common::String;
# use pgBackRest::Common::Xml;
# use pgBackRest::Protocol::IO::IO;

####################################################################################################################################
# httpQuery
####################################################################################################################################
sub httpQuery
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $hQuery,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::httpQuery', \@_,
            {name => 'hQuery', required => false, trace => true},
        );

    # Generate the query string
    my $strQuery = '';

    # If a hash (the normal case)
    if (ref($hQuery))
    {
        foreach my $strParam (sort(keys(%{$hQuery})))
        {
            # Parameters may not be defined - this is OK
            if (defined($hQuery->{$strParam}))
            {
                $strQuery .= ($strQuery eq '' ? '' : '&') . $strParam . '=' . uriEncode($hQuery->{$strParam});
            }
        }
    }
    # Else query string was passed directly as a scalar
    elsif (defined($hQuery))
    {
        $strQuery = $hQuery;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strQuery', value => $strQuery}
    );
}

push @EXPORT, qw(httpQuery);

1;

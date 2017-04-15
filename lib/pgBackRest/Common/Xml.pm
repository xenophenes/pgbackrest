####################################################################################################################################
# COMMON XML MODULE
####################################################################################################################################
package pgBackRest::Common::Xml;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use XML::LibXML;

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;

####################################################################################################################################
# xmlParse - parse a string into an xml document and return the root node.
####################################################################################################################################
sub xmlParse
{
    my $rstrXml = shift;

    my $oXml = XML::LibXML->load_xml(string => $rstrXml)->documentElement();

    return $oXml;
}

push @EXPORT, qw(xmlParse);

####################################################################################################################################
# xmlTagChildren - get all children that match the tag.
####################################################################################################################################
sub xmlTagChildren
{
    my $oXml = shift;
    my $strTag = shift;

    return $oXml->getChildrenByTagName($strTag);
}

push @EXPORT, qw(xmlTagChildren);

####################################################################################################################################
# xmlTagContent - get the text content for a tag, error if the tag is required and does not exist.
####################################################################################################################################
sub xmlTagContent
{
    my $oXml = shift;
    my $strTag = shift;
    my $bRequired = shift;
    # my $strDefault = shift;

    # Get the tag or tags
    my @oyTag = $oXml->getElementsByTagName($strTag);

    # Error if the tag does not exist and is required
    if (@oyTag > 1)
    {
        confess &log(ERROR, @oyTag . " '${strTag}' tag(s) exist, but only one was expected", ERROR_FORMAT);
    }
    elsif (@oyTag == 0 && (!defined($bRequired) || $bRequired))
    {
        confess &log(ERROR, "tag '${strTag}' does not exist", ERROR_FORMAT);
    }
    else
    {
        return $oyTag[0]->textContent();
    }

    return;
}

push @EXPORT, qw(xmlTagContent);

1;

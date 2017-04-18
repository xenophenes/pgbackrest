####################################################################################################################################
# DOC EXECUTE MODULE
####################################################################################################################################
package BackRestDoc::Common::DocExecute;
use parent 'BackRestDoc::Common::DocRender';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use Storable qw(dclone);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Config::Config;
use pgBackRest::Storage::Posix::StoragePosixCommon;
use pgBackRest::Version;

use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::HostTest;
use pgBackRestTest::Common::HostGroupTest;

use BackRestDoc::Common::DocManifest;

####################################################################################################################################
# User that's building the docs
####################################################################################################################################
use constant DOC_USER                                              => 'ubuntu';

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $oManifest,
        $strRenderOutKey,
        $bExe
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strType'},
            {name => 'oManifest'},
            {name => 'strRenderOutKey'},
            {name => 'bExe'}
        );

    # Create the class hash
    my $self = $class->SUPER::new($strType, $oManifest, $strRenderOutKey);
    bless $self, $class;

    if (defined($self->{oSource}{hyCache}))
    {
        $self->{bCache} = true;
        $self->{iCacheIdx} = 0;
    }
    else
    {
        $self->{bCache} = false;
    }

    $self->{bExe} = $bExe;

    $self->{iCmdLineLen} = $self->{oDoc}->paramGet('cmd-line-len', false, 80);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# executeKey
#
# Get a unique key for the execution step to determine if the cache is valid.
####################################################################################################################################
sub executeKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strHostName,
        $oCommand,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->executeKey', \@_,
            {name => 'strHostName', trace => true},
            {name => 'oCommand', trace => true},
        );

    # Add user to command
    my $strCommand = $self->{oManifest}->variableReplace(trim($oCommand->fieldGet('exe-cmd')));
    my $strUser = $self->{oManifest}->variableReplace($oCommand->paramGet('user', false, 'postgres'));
    $strCommand = ($strUser eq DOC_USER ? '' : ('sudo ' . ($strUser eq 'root' ? '' : "-u $strUser "))) . $strCommand;

    # Format and split command
    $strCommand =~ s/[ ]*\n[ ]*/ \\\n    /smg;
    $strCommand =~ s/ \\\@ \\//smg;
    my @stryCommand = split("\n", $strCommand);

    my $hCacheKey =
    {
        host => $strHostName,
        cmd => \@stryCommand,
        output => JSON::PP::false,
    };

    if (defined($oCommand->fieldGet('exe-cmd-extra', false)))
    {
        $$hCacheKey{'cmd-extra'} = $oCommand->fieldGet('exe-cmd-extra');
    }

    if (defined($oCommand->paramGet('err-expect', false)))
    {
        $$hCacheKey{'err-expect'} = $oCommand->paramGet('err-expect');
    }

    if ($oCommand->paramTest('output', 'y') || $oCommand->paramTest('show', 'y') || $oCommand->paramTest('variable-key'))
    {
        $$hCacheKey{'output'} = JSON::PP::true;
    }

    if (defined($oCommand->fieldGet('exe-highlight', false)))
    {
        $$hCacheKey{'output'} = JSON::PP::true;
        $$hCacheKey{highlight}{'filter'} = $oCommand->paramTest('filter', 'n') ? JSON::PP::false : JSON::PP::true;
        $$hCacheKey{highlight}{'filter-context'} = $oCommand->paramGet('filter-context', false, 2);

        my @stryHighlight;
        $stryHighlight[0] = $self->{oManifest}->variableReplace($oCommand->fieldGet('exe-highlight'));

        $$hCacheKey{highlight}{list} = \@stryHighlight;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hExecuteKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# execute
####################################################################################################################################
sub execute
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $strHostName,
        $oCommand,
        $iIndent,
        $bCache,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->execute', \@_,
            {name => 'oSection'},
            {name => 'strHostName'},
            {name => 'oCommand'},
            {name => 'iIndent', default => 1},
            {name => 'bCache', default => true},
        );

    # Working variables
    my $hCacheKey = $self->executeKey($strHostName, $oCommand);
    my $strCommand = join("\n", @{$$hCacheKey{cmd}});
    my $strOutput;

    if (!$oCommand->paramTest('show', 'n') && $self->{bExe} && $self->isRequired($oSection))
    {
        # Make sure that no lines are greater than 80 chars
        foreach my $strLine (split("\n", $strCommand))
        {
            if (length(trim($strLine)) > $self->{iCmdLineLen})
            {
                confess &log(ERROR,
                    "command has a line > $self->{iCmdLineLen} characters:\n${strCommand}\noffending line: ${strLine}");
            }
        }
    }

    &log(DEBUG, ('    ' x $iIndent) . "execute: $strCommand");

    if ($self->{oManifest}->variableReplace($oCommand->paramGet('skip', false, 'n')) ne 'y')
    {
        if ($self->{bExe} && $self->isRequired($oSection))
        {
            my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('exe', $hCacheKey);

            if ($bCacheHit)
            {
                $strOutput = defined($$hCacheValue{output}) ? join("\n", @{$$hCacheValue{output}}) : undef;
            }
            else
            {
                # Check that the host is valid
                my $oHost = $self->{host}{$strHostName};

                if (!defined($oHost))
                {
                    confess &log(ERROR, "cannot execute on host ${strHostName} because the host does not exist");
                }

                my $oExec = $oHost->execute(
                    $strCommand . (defined($$hCacheKey{'cmd-extra'}) ? ' ' . $$hCacheKey{'cmd-extra'} : ''),
                    {iExpectedExitStatus => $$hCacheKey{'err-expect'},
                     bSuppressError => $oCommand->paramTest('err-suppress', 'y'),
                     iRetrySeconds => $oCommand->paramGet('retry', false)});
                $oExec->begin();
                $oExec->end();

                if (defined($oExec->{strOutLog}) && $oExec->{strOutLog} ne '')
                {
                    $strOutput = $oExec->{strOutLog};

                    # Trim off extra linefeeds before and after
                    $strOutput =~ s/^\n+|\n$//g;
                }

                if (defined($$hCacheKey{'err-expect'}) && defined($oExec->{strErrorLog}) && $oExec->{strErrorLog} ne '')
                {
                    $strOutput .= $oExec->{strErrorLog};
                }

                if ($$hCacheKey{output} && defined($$hCacheKey{highlight}) && $$hCacheKey{highlight}{filter} && defined($strOutput))
                {
                    my $strHighLight = @{$$hCacheKey{highlight}{list}}[0];

                    if (!defined($strHighLight))
                    {
                        confess &log(ERROR, 'filter requires highlight definition: ' . $strCommand);
                    }

                    my $iFilterContext = $$hCacheKey{highlight}{'filter-context'};

                    my @stryOutput = split("\n", $strOutput);
                    undef($strOutput);
                    # my $iFiltered = 0;
                    my $iLastOutput = -1;

                    for (my $iIndex = 0; $iIndex < @stryOutput; $iIndex++)
                    {
                        if ($stryOutput[$iIndex] =~ /$strHighLight/)
                        {
                            # Determine the first line to output
                            my $iFilterFirst = $iIndex - $iFilterContext;

                            # Don't go past the beginning
                            $iFilterFirst = $iFilterFirst < 0 ? 0 : $iFilterFirst;

                            # Don't repeat lines that have already been output
                            $iFilterFirst  = $iFilterFirst <= $iLastOutput ? $iLastOutput + 1 : $iFilterFirst;

                            # Determine the last line to output
                            my $iFilterLast = $iIndex + $iFilterContext;

                            # Don't got past the end
                            $iFilterLast = $iFilterLast >= @stryOutput ? @stryOutput -1 : $iFilterLast;

                            # Mark filtered lines if any
                            if ($iFilterFirst > $iLastOutput + 1)
                            {
                                my $iFiltered = $iFilterFirst - ($iLastOutput + 1);

                                if ($iFiltered > 1)
                                {
                                    $strOutput .= (defined($strOutput) ? "\n" : '') .
                                                  "       [filtered ${iFiltered} lines of output]";
                                }
                                else
                                {
                                    $iFilterFirst -= 1;
                                }
                            }

                            # Output the lines
                            for (my $iOutputIndex = $iFilterFirst; $iOutputIndex <= $iFilterLast; $iOutputIndex++)
                            {
                                    $strOutput .= (defined($strOutput) ? "\n" : '') . $stryOutput[$iOutputIndex];
                            }

                            $iLastOutput = $iFilterLast;
                        }
                    }

                    if (@stryOutput - 1 > $iLastOutput + 1)
                    {
                        my $iFiltered = (@stryOutput - 1) - ($iLastOutput + 1);

                        if ($iFiltered > 1)
                        {
                            $strOutput .= (defined($strOutput) ? "\n" : '') .
                                          "       [filtered ${iFiltered} lines of output]";
                        }
                        else
                        {
                            $strOutput .= (defined($strOutput) ? "\n" : '') . $stryOutput[-1];
                        }
                    }
                }

                if (!$$hCacheKey{output})
                {
                    $strOutput = undef;
                }

                if (defined($strOutput))
                {
                    my @stryOutput = split("\n", $strOutput);
                    $$hCacheValue{output} = \@stryOutput;
                }

                if ($bCache)
                {
                    $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
                }
            }

            # Output is assigned to a var
            if ($oCommand->paramTest('variable-key'))
            {
                $self->{oManifest}->variableSet($oCommand->paramGet('variable-key'), trim($strOutput), true);
            }
        }
        elsif ($$hCacheKey{output})
        {
            $strOutput = 'Output suppressed for testing';
        }
    }

    # Default variable output when it was not set by execution
    if ($oCommand->paramTest('variable-key') && !defined($self->{oManifest}->variableGet($oCommand->paramGet('variable-key'))))
    {
        $self->{oManifest}->variableSet($oCommand->paramGet('variable-key'), '[Test Variable]', true);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strCommand', value => $strCommand, trace => true},
        {name => 'strOutput', value => $strOutput, trace => true}
    );
}


####################################################################################################################################
# configKey
####################################################################################################################################
sub configKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oConfig,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'oConfig', trace => true},
        );

    my $hCacheKey =
    {
        host => $self->{oManifest}->variableReplace($oConfig->paramGet('host')),
        file => $self->{oManifest}->variableReplace($oConfig->paramGet('file')),
    };

    if ($oConfig->paramTest('reset', 'y'))
    {
        $$hCacheKey{reset} = JSON::PP::true;
    }

    # Add all options to the key
    my $strOptionTag = $oConfig->nameGet() eq 'backrest-config' ? 'backrest-config-option' : 'postgres-config-option';

    foreach my $oOption ($oConfig->nodeList($strOptionTag))
    {
        my $hOption = {};

        if ($oOption->paramTest('remove', 'y'))
        {
            $$hOption{remove} = JSON::PP::true;
        }

        if (defined($oOption->valueGet(false)))
        {
            $$hOption{value} = $self->{oManifest}->variableReplace($oOption->valueGet());
        }

        my $strKey = $self->{oManifest}->variableReplace($oOption->paramGet('key'));

        if ($oConfig->nameGet() eq 'backrest-config')
        {
            my $strSection = $self->{oManifest}->variableReplace($oOption->paramGet('section'));

            $$hCacheKey{option}{$strSection}{$strKey} = $hOption;
        }
        else
        {
            $$hCacheKey{option}{$strKey} = $hOption;
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hCacheKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# backrestConfig
####################################################################################################################################
sub backrestConfig
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oConfig,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->backrestConfig', \@_,
            {name => 'oSection'},
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $hCacheKey = $self->configKey($oConfig);
    my $strFile = $$hCacheKey{file};
    my $strConfig = undef;

    &log(DEBUG, ('    ' x $iDepth) . 'process backrest config: ' . $$hCacheKey{file});

    if ($self->{bExe} && $self->isRequired($oSection))
    {
        my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('cfg-' . BACKREST_EXE, $hCacheKey);

        if ($bCacheHit)
        {
            $strConfig = defined($$hCacheValue{config}) ? join("\n", @{$$hCacheValue{config}}) : undef;
        }
        else
        {
            # Check that the host is valid
            my $strHostName = $self->{oManifest}->variableReplace($oConfig->paramGet('host'));
            my $oHost = $self->{host}{$strHostName};

            if (!defined($oHost))
            {
                confess &log(ERROR, "cannot configure backrest on host ${strHostName} because the host does not exist");
            }

            # Reset all options
            if ($oConfig->paramTest('reset', 'y'))
            {
                delete(${$self->{config}}{$strHostName}{$$hCacheKey{file}})
            }

            foreach my $oOption ($oConfig->nodeList('backrest-config-option'))
            {
                my $strSection = $self->{oManifest}->variableReplace($oOption->paramGet('section'));
                my $strKey = $self->{oManifest}->variableReplace($oOption->paramGet('key'));
                my $strValue;

                if (!$oOption->paramTest('remove', 'y'))
                {
                    $strValue = $self->{oManifest}->variableReplace(trim($oOption->valueGet(false)));
                }

                if (!defined($strValue))
                {
                    delete(${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}{$strKey});

                    if (keys(%{${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}}) == 0)
                    {
                        delete(${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection});
                    }

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strSection}->${strKey}");
                }
                else
                {
                    # Get the config options hash
                    my $oOption = optionRuleGet();

                    # Make sure the specified option exists
                    # ??? This is too simplistic to handle new indexed options.  The check below works for now but it would be good
                    # ??? to bring back more sophisticated checking in the future.
                    # if (!defined($$oOption{$strKey}))
                    # {
                    #     confess &log(ERROR, "option ${strKey} does not exist");
                    # }

                    # If this option is a hash and the value is already set then append to the array
                    if (defined($$oOption{$strKey}) &&
                        $$oOption{$strKey}{&OPTION_RULE_TYPE} eq OPTION_TYPE_HASH &&
                        defined(${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}{$strKey}))
                    {
                        my @oValue = ();
                        my $strHashValue = ${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}{$strKey};

                        # If there is only one key/value
                        if (ref(\$strHashValue) eq 'SCALAR')
                        {
                            push(@oValue, $strHashValue);
                        }
                        # Else if there is an array of values
                        else
                        {
                            @oValue = @{$strHashValue};
                        }

                        push(@oValue, $strValue);
                        ${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}{$strKey} = \@oValue;
                    }
                    # else just set the value
                    else
                    {
                        ${$self->{config}}{$strHostName}{$$hCacheKey{file}}{$strSection}{$strKey} = $strValue;
                    }

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strSection}->${strKey} = ${strValue}");
                }
            }

            my $strLocalFile = '/home/' . DOC_USER . '/data/pgbackrest.conf';

            # Save the ini file
            fileStringWrite($strLocalFile, iniRender($self->{config}{$strHostName}{$$hCacheKey{file}}, true));

            $oHost->copyTo(
                $strLocalFile, $$hCacheKey{file},
                $self->{oManifest}->variableReplace($oConfig->paramGet('owner', false, 'postgres:postgres')), '640');

            # Remove the log-console-stderr option before pushing into the cache
            # ??? This is not very pretty and should be replaced with a general way to hide config options
            my $oConfigClean = dclone($self->{config}{$strHostName}{$$hCacheKey{file}});
            delete($$oConfigClean{&CONFIG_SECTION_GLOBAL}{&OPTION_LOG_LEVEL_STDERR});
            delete($$oConfigClean{&CONFIG_SECTION_GLOBAL}{&OPTION_LOG_TIMESTAMP});

            if (keys(%{$$oConfigClean{&CONFIG_SECTION_GLOBAL}}) == 0)
            {
                delete($$oConfigClean{&CONFIG_SECTION_GLOBAL});
            }

            fileStringWrite("${strLocalFile}.clean", iniRender($oConfigClean, true));

            # Push config file into the cache
            $strConfig = fileStringRead("${strLocalFile}.clean");

            my @stryConfig = undef;

            if (trim($strConfig) ne '')
            {
                @stryConfig = split("\n", $strConfig);
            }

            $$hCacheValue{config} = \@stryConfig;
            $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
        }
    }
    else
    {
        $strConfig = 'Config suppressed for testing';
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true},
        {name => 'bShow', value => $oConfig->paramTest('show', 'n') ? false : true, trace => true}
    );
}

####################################################################################################################################
# postgresConfig
####################################################################################################################################
sub postgresConfig
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oConfig,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->postgresConfig', \@_,
            {name => 'oSection'},
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $hCacheKey = $self->configKey($oConfig);
    my $strFile = $$hCacheKey{file};
    my $strConfig;

    if ($self->{bExe} && $self->isRequired($oSection))
    {
        my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('cfg-postgresql', $hCacheKey);

        if ($bCacheHit)
        {
            $strConfig = defined($$hCacheValue{config}) ? join("\n", @{$$hCacheValue{config}}) : undef;
        }
        else
        {
            # Check that the host is valid
            my $strHostName = $self->{oManifest}->variableReplace($oConfig->paramGet('host'));
            my $oHost = $self->{host}{$strHostName};

            if (!defined($oHost))
            {
                confess &log(ERROR, "cannot configure postgres on host ${strHostName} because the host does not exist");
            }

            my $strLocalFile = '/home/' . DOC_USER . '/data/postgresql.conf';
            $oHost->copyFrom($$hCacheKey{file}, $strLocalFile);

            if (!defined(${$self->{'pg-config'}}{$strHostName}{$$hCacheKey{file}}{base}) && $self->{bExe})
            {
                ${$self->{'pg-config'}}{$strHostName}{$$hCacheKey{file}}{base} = fileStringRead($strLocalFile);
            }

            my $oConfigHash = $self->{'pg-config'}{$strHostName}{$$hCacheKey{file}};
            my $oConfigHashNew;

            if (!defined($$oConfigHash{old}))
            {
                $oConfigHashNew = {};
                $$oConfigHash{old} = {}
            }
            else
            {
                $oConfigHashNew = dclone($$oConfigHash{old});
            }

            &log(DEBUG, ('    ' x $iDepth) . 'process postgres config: ' . $$hCacheKey{file});

            foreach my $oOption ($oConfig->nodeList('postgres-config-option'))
            {
                my $strKey = $oOption->paramGet('key');
                my $strValue = $self->{oManifest}->variableReplace(trim($oOption->valueGet()));

                if ($strValue eq '')
                {
                    delete($$oConfigHashNew{$strKey});

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strKey}");
                }
                else
                {
                    $$oConfigHashNew{$strKey} = $strValue;
                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strKey} = ${strValue}");
                }
            }

            # Generate config text
            foreach my $strKey (sort(keys(%$oConfigHashNew)))
            {
                if (defined($strConfig))
                {
                    $strConfig .= "\n";
                }

                $strConfig .= "${strKey} = $$oConfigHashNew{$strKey}";
            }

            # Save the conf file
            if ($self->{bExe})
            {
                fileStringWrite($strLocalFile, $$oConfigHash{base} .
                                (defined($strConfig) ? "\n# pgBackRest Configuration\n${strConfig}\n" : ''));

                $oHost->copyTo($strLocalFile, $$hCacheKey{file}, 'postgres:postgres', '640');
            }

            $$oConfigHash{old} = $oConfigHashNew;

            my @stryConfig = undef;

            if (trim($strConfig) ne '')
            {
                @stryConfig = split("\n", $strConfig);
            }

            $$hCacheValue{config} = \@stryConfig;
            $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
        }
    }
    else
    {
        $strConfig = 'Config suppressed for testing';
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true},
        {name => 'bShow', value => $oConfig->paramTest('show', 'n') ? false : true, trace => true}
    );
}

####################################################################################################################################
# hostKey
####################################################################################################################################
sub hostKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oHost,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'oHost', trace => true},
        );

    my $hCacheKey =
    {
        name => $self->{oManifest}->variableReplace($oHost->paramGet('name')),
        user => $self->{oManifest}->variableReplace($oHost->paramGet('user')),
        image => $self->{oManifest}->variableReplace($oHost->paramGet('image')),
    };

    if (defined($oHost->paramGet('option', false)))
    {
        $$hCacheKey{option} = $self->{oManifest}->variableReplace($oHost->paramGet('option'));
    }

    if (defined($oHost->paramGet('os', false)))
    {
        $$hCacheKey{os} = $self->{oManifest}->variableReplace($oHost->paramGet('os'));
    }

    if (defined($oHost->paramGet('mount', false)))
    {
        $$hCacheKey{mount} = $self->{oManifest}->variableReplace($oHost->paramGet('mount'));
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hCacheKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# cachePop
####################################################################################################################################
sub cachePop
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strCacheType,
        $hCacheKey,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'strCacheType', trace => true},
            {name => 'hCacheKey', trace => true},
        );

    my $bCacheHit = false;
    my $oCacheValue = undef;

    if ($self->{bCache})
    {
        my $oJSON = JSON::PP->new()->canonical()->allow_nonref();
        # &log(WARN, "checking cache for\ncurrent key: " . $oJSON->encode($hCacheKey));

        my $hCache = ${$self->{oSource}{hyCache}}[$self->{iCacheIdx}];

        if (!defined($hCache))
        {
            confess &log(ERROR, 'unable to get index from cache', ERROR_FILE_INVALID);
        }

        if (!defined($$hCache{key}))
        {
            confess &log(ERROR, 'unable to get key from cache', ERROR_FILE_INVALID);
        }

        if (!defined($$hCache{type}))
        {
            confess &log(ERROR, 'unable to get type from cache', ERROR_FILE_INVALID);
        }

        if ($$hCache{type} ne $strCacheType)
        {
            confess &log(ERROR, 'types do not match, cache is invalid', ERROR_FILE_INVALID);
        }

        if ($oJSON->encode($$hCache{key}) ne $oJSON->encode($hCacheKey))
        {
            confess &log(ERROR,
                "keys at index $self->{iCacheIdx} do not match, cache is invalid." .
                "\ncache key: " . $oJSON->encode($$hCache{key}) .
                "\ncurrent key: " . $oJSON->encode($hCacheKey), ERROR_FILE_INVALID);
        }

        $bCacheHit = true;
        $oCacheValue = $$hCache{value};
        $self->{iCacheIdx}++;
    }
    else
    {
        if ($self->{oManifest}{bCacheOnly})
        {
            confess &log(ERROR, 'Cache only operation forced by --cache-only option');
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bCacheHit', value => $bCacheHit, trace => true},
        {name => 'strCacheType', value => $strCacheType, trace => true},
        {name => 'hCacheKey', value => $hCacheKey, trace => true},
        {name => 'oCacheValue', value => $oCacheValue, trace => true},
    );
}

####################################################################################################################################
# cachePush
####################################################################################################################################
sub cachePush
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $hCacheKey,
        $oCacheValue,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'strType', trace => true},
            {name => 'hCacheKey', trace => true},
            {name => 'oCacheValue', required => false, trace => true},
        );

    if ($self->{bCache})
    {
        confess &log(ASSERT, "cachePush should not be called when cache is already present");
    }

    # Create the cache entry
    my $hCache =
    {
        key => $hCacheKey,
        type => $strType,
    };

    if (defined($oCacheValue))
    {
        $$hCache{value} = $oCacheValue;
    }

    push @{$self->{oSource}{hyCache}}, $hCache;

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# sectionChildProcesss
####################################################################################################################################
sub sectionChildProcess
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oChild,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->sectionChildProcess', \@_,
            {name => 'oSection'},
            {name => 'oChild'},
            {name => 'iDepth'}
        );

    &log(DEBUG, ('    ' x ($iDepth + 1)) . 'process child: ' . $oChild->nameGet());

    # Execute a command
    if ($oChild->nameGet() eq 'host-add')
    {
        if ($self->{bExe} && $self->isRequired($oSection))
        {
            my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('host', $self->hostKey($oChild));

            if ($bCacheHit)
            {
                $self->{oManifest}->variableSet("host-$$hCacheKey{name}-ip", $$hCacheValue{ip}, true);
            }
            else
            {
                if (defined($self->{host}{$$hCacheKey{name}}))
                {
                    confess &log(ERROR, 'cannot add host ${strName} because the host already exists');
                }

                executeTest("rm -rf ~/data/$$hCacheKey{name}");
                executeTest("mkdir -p ~/data/$$hCacheKey{name}/etc");

                my $oHost = new pgBackRestTest::Common::HostTest(
                    $$hCacheKey{name}, "doc-$$hCacheKey{name}", $$hCacheKey{image}, $$hCacheKey{user}, $$hCacheKey{os},
                    defined($$hCacheKey{mount}) ? [$$hCacheKey{mount}] : undef, $$hCacheKey{option});

                $self->{host}{$$hCacheKey{name}} = $oHost;
                $self->{oManifest}->variableSet("host-$$hCacheKey{name}-ip", $oHost->{strIP}, true);
                $$hCacheValue{ip} = $oHost->{strIP};

                # Add to the host group
                my $oHostGroup = hostGroupGet();
                $oHostGroup->hostAdd($oHost);

                # Execute initialize commands
                foreach my $oExecute ($oChild->nodeList('execute', false))
                {
                    $self->execute($oSection, $$hCacheKey{name}, $oExecute, $iDepth + 1, false);
                }

                $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
            }
        }
    }
    # Skip children that have already been processed and error on others
    elsif ($oChild->nameGet() ne 'title')
    {
        confess &log(ASSERT, 'unable to process child type ' . $oChild->nameGet());
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

1;

####################################################################################################################################
# STORAGE MODULE
####################################################################################################################################
package pgBackRest::Storage::Storage;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();
use Fcntl qw(:mode :flock O_RDONLY O_WRONLY O_CREAT);
use File::Basename qw(dirname basename);
use File::Copy qw(cp);
use File::Path qw(make_path remove_tree);
use File::stat;
use IO::Handle;

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Common::Wait;
use pgBackRest::Storage::Posix::StoragePosixCommon;
use pgBackRest::Storage::Posix::StoragePosix;
use pgBackRest::Protocol::Common;
use pgBackRest::Version;

####################################################################################################################################
# PATH Constants
####################################################################################################################################
use constant PATH_REPO                                              => '<REPO>';
    push @EXPORT, qw(PATH_REPO);
use constant PATH_REPO_BACKUP                                       => '<REPO:BACKUP>';
    push @EXPORT, qw(PATH_REPO_BACKUP);
use constant PATH_REPO_BACKUP_TMP                                   => '<REPO:BACKUP:TMP>';
    push @EXPORT, qw(PATH_REPO_BACKUP_TMP);
use constant PATH_REPO_ARCHIVE                                      => '<REPO:ARCHIVE>';
    push @EXPORT, qw(PATH_REPO_ARCHIVE);
use constant PATH_SPOOL_ARCHIVE_OUT                                 => '<SPOOL:ARCHIVE:OUT>';
    push @EXPORT, qw(PATH_SPOOL_ARCHIVE_OUT);

####################################################################################################################################
# STD pipe constants
####################################################################################################################################
use constant PIPE_STDIN                                             => '<STDIN>';
    push @EXPORT, qw(PIPE_STDIN);
use constant PIPE_STDOUT                                            => '<STDOUT>';
    push @EXPORT, qw(PIPE_STDOUT);

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
        $self->{strType},
        $self->{oDriver},
        $self->{strPathBase},
        $self->{oProtocol},
        $self->{bAllowTemp},
        $self->{strDefaultPathMode},
        $self->{strDefaultFileMode},
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strType'},
            {name => 'oDriver'},
            {name => 'strBasePath'},
            {name => 'oProtocol', optional => true},
            {name => 'bAllowTemp', optional => true, default => false},
            {name => 'strDefaultPathMode', optional => true, default => '0750'},
            {name => 'strDefaultFileMode', optional => true, default => '0640'},
        );

    # Default compression extension to gz
    $self->{strCompressExtension} = COMPRESS_EXT;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# pathGet
####################################################################################################################################
sub pathGet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,                                               # File that that needs to be translated to a path
        $bTemp,                                                     # Return the temp file name
    ) =
        logDebugParam
    (
        __PACKAGE__ . '->pathGet', \@_,
        {name => 'strPathExp', trace => true},
        {name => 'bTemp', optional => true, default => false, trace => true},
    );

    # Path to be returned
    my $strPath;

    # Is this an absolute path type?
    my $strType;
    my $strFile;
    my $bAbsolute;

    if (index($strPathExp, qw(/)) == 0)
    {
        $bAbsolute = true;
        $strFile = $strPathExp;
    }
    else
    {
        $bAbsolute = false;

        if (index($strPathExp, qw(<)) == 0)
        {
            my $iPos = index($strPathExp, qw(>));

            if ($iPos == -1)
            {
                confess &log(ASSERT, "found < but not > in '${strPathExp}'");
            }

            $strType = substr($strPathExp, 0, $iPos + 1);

            if ($iPos < length($strPathExp) - 1)
            {
                $strFile = substr($strPathExp, $iPos + 1);
            }
        }
        else
        {
            $strPath = $self->{strPathBase};
            $strFile = "/${strPathExp}";
        }
    }

    # Make sure a temp file is valid for this type and file
    if ($bTemp)
    {
        # Only allow temp files for PATH_REPO_ARCHIVE, PATH_SPOOL_ARCHIVE_OUT, PATH_REPO_BACKUP_TMP and any absolute path
        if (!$self->{bAllowTemp})
        {
            confess &log(ASSERT, "temp file not supported for storage type $self->{strType}");
        }

        # The file must be defined
        if (!defined($strFile))
        {
            confess &log(ASSERT, "file part must be defined when temp file specified for path type ${strType}");
        }
    }

    if (!$bAbsolute && !defined($strPath))
    {
        # Get backup path
        if ($strType eq PATH_REPO)
        {
            $strPath = $self->{strPathBase};
        }
        # Else process path types that require a stanza
        else
        {
            # All paths in this section will be in the base path
            $strPath = $self->{strPathBase};

            # Make sure the stanza is defined since remaining path types require it
            if (!defined($self->{strStanza}))
            {
                confess &log(ASSERT, 'strStanza not defined');
            }

            # Get the backup tmp path
            if ($strType eq PATH_REPO_BACKUP_TMP)
            {
                $strPath .= "/temp/$self->{strStanza}.tmp";
            }
            # Else get archive paths
            elsif ($strType eq PATH_SPOOL_ARCHIVE_OUT || $strType eq PATH_REPO_ARCHIVE)
            {
                $strPath .= "/archive/$self->{strStanza}";

                # Get archive path
                if ($strType eq PATH_REPO_ARCHIVE)
                {
                    # If file is not defined nothing further to do
                    if (defined($strFile))
                    {
                        my $strArchiveId = (split('/', $strFile))[1];

                        # If file is defined after archive id path is split out
                        if (defined((split('/', $strFile))[2]))
                        {
                            $strPath .= "/${strArchiveId}";
                            $strFile = (split('/', $strFile))[2];

                            # If this is a WAL segment then put it into a subdirectory
                            if (substr(basename($strFile), 0, 24) =~ /^([0-F]){24}$/)
                            {
                                $strPath .= '/' . substr($strFile, 0, 16);
                            }

                            $strFile = "/${strFile}";
                        }
                    }
                }
                # Else get archive out path
                else
                {
                    $strPath .= '/out';
                }
            }
            # Else get backup cluster
            elsif ($strType eq PATH_REPO_BACKUP)
            {
                $strPath .= "/backup/$self->{strStanza}";
            }
            # Else error when path type not recognized
            else
            {
                confess &log(ASSERT, "invalid path type ${strType}");
            }
        }
    }

    # Combine path and file
    $strPath .= (defined($strFile) ? $strFile : '');

    # Add temp extension
    $strPath .= $bTemp ? '.' . BACKREST_EXE . '.tmp' : '';

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strPath', value => $strPath, trace => true}
    );
}

####################################################################################################################################
# isRemote
#
# Determine whether the path type is remote
####################################################################################################################################
sub isRemote
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
    ) =
        logDebugParam
    (
        __PACKAGE__ . '->isRemote', \@_,
    );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bRemote', value => $self->{oProtocol}->isRemote(), trace => true}
    );
}

####################################################################################################################################
# openRead - open a file for reading.
####################################################################################################################################
sub openRead
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFileExp,
        $bIgnoreMissing,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->copy', \@_,
            {name => 'strFileExp'},
            {name => 'bIgnoreMissing', optional => true, default => false},
        );

    my $oFileIO;

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        # Open the file
        eval
        {
            $oFileIO = $self->{oDriver}->openRead($self->pathGet($strFileExp));
            return 1;
        }
        # On error check if missing file should be ignored, otherwise error
        or do
        {
            if (exceptionCode($EVAL_ERROR) != ERROR_FILE_MISSING || !$bIgnoreMissing)
            {
                confess $EVAL_ERROR;
            }

            # Return true to indicate that the function was success but no file was opened
            $oFileIO = true;
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'oFileIO', value => $oFileIO, trace => true},
    );
}

####################################################################################################################################
# linkCreate
####################################################################################################################################
sub linkCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strSourcePathExp,
        $strDestinationPathExp,
        $bHard,
        $bRelative,
        $bPathCreate
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->linkCreate', \@_,
            {name => 'strSourcePathExp'},
            {name => 'strDestinationPathExp'},
            {name => 'bHard', default => false},
            {name => 'bRelative', default => false},
            {name => 'bPathCreate', default => true}
        );

    # Generate source and destination files
    my $strSource = $self->pathGet($strSourcePathExp);
    my $strDestination = $self->pathGet($strDestinationPathExp);

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        # If the destination path is backup and does not exist, create it
        # ??? This should only happen when the link create errors
        if ($bPathCreate)
        {
            filePathCreate(dirname($strDestination), undef, true);
        }

        unless (-e $strSource)
        {
            if (-e $strSource . ".$self->{strCompressExtension}")
            {
                $strSource .= ".$self->{strCompressExtension}";
                $strDestination .= ".$self->{strCompressExtension}";
            }
            else
            {
                # Error when a hardlink will be created on a missing file
                if ($bHard)
                {
                    confess &log(ASSERT, "unable to find ${strSource}(.$self->{strCompressExtension}) for link");
                }
            }
        }

        # Generate relative path if requested
        if ($bRelative)
        {
            # Determine how much of the paths are common
            my @strySource = split('/', $strSource);
            my @stryDestination = split('/', $strDestination);

            while (defined($strySource[0]) && defined($stryDestination[0]) && $strySource[0] eq $stryDestination[0])
            {
                shift(@strySource);
                shift(@stryDestination);
            }

            # Add relative path sections
            $strSource = '';

            for (my $iIndex = 0; $iIndex < @stryDestination - 1; $iIndex++)
            {
                $strSource .= '../';
            }

            # Add path to source
            $strSource .= join('/', @strySource);

            logDebugMisc
            (
                $strOperation, 'apply relative path',
                {name => 'strSource', value => $strSource, trace => true}
            );
        }

        if ($bHard)
        {
            link($strSource, $strDestination)
                or confess &log(ERROR, "unable to create hardlink from ${strSource} to ${strDestination}");
        }
        else
        {
            symlink($strSource, $strDestination)
                or confess &log(ERROR, "unable to create symlink from ${strSource} to ${strDestination}");
        }
    }

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# move
#
# Moves a file locally or remotely.
####################################################################################################################################
sub move
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strSourcePathExp,
        $strDestinationPathExp,
        $bDestinationPathCreate,
        $bPathSync,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->move', \@_,
            {name => 'strSourcePathExp'},
            {name => 'strDestinationPathExp'},
            {name => 'bDestinationPathCreate', default => false},
            {name => 'bPathSync', default => false},
        );

    # Set operation variables
    my $strPathSource = $self->pathGet($strSourcePathExp);
    my $strPathDestination = $self->pathGet($strDestinationPathExp);

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        fileMove($strPathSource, $strPathDestination, $bDestinationPathCreate, $bPathSync);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

####################################################################################################################################
# compress
####################################################################################################################################
sub compress
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $bRemoveSource
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->compress', \@_,
            {name => 'strPathExp'},
            {name => 'bRemoveSource', default => true}
        );

    # Set operation variables
    my $strFile = $self->pathGet($strPathExp);

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        # Use copy to compress the file
        $self->copy($strFile, "${strFile}.gz", false, true);

        # Remove the old file
        if ($bRemoveSource)
        {
            fileRemove($strFile);
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

####################################################################################################################################
# pathCreate
#
# Creates a path locally or remotely.
####################################################################################################################################
sub pathCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $strMode,
        $bIgnoreExists,
        $bCreateParent,
        $bPathSync,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->pathCreate', \@_,
            {name => 'strPathExp'},
            {name => 'strMode', optional => true, default => '0750'},
            {name => 'bIgnoreExists', optional => true, default => false},
            {name => 'bCreateParent', optional => true, default => false},
            {name => 'bPathSync', optional => true, default => false},
        );

    # Set operation variables
    my $strPath = $self->pathGet($strPathExp);

    # Run remotely
    if ($self->isRemote())
    {
        $self->{oProtocol}->cmdExecute(
            OP_FILE_PATH_CREATE,
            [$strPath,
                {strMode => $strMode, bIgnoreExists => $bIgnoreExists, bCreateParent => $bCreateParent, bPathSync => $bPathSync}]);
    }
    # Run locally
    else
    {
        filePathCreate($strPath, $strMode, $bIgnoreExists, $bCreateParent, $bPathSync);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

####################################################################################################################################
# pathSync
####################################################################################################################################
sub pathSync
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $bRecursive,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->pathSync', \@_,
            {name => 'strPathExp'},
            {name => 'bRecursive', default => false},
        );

    # Remote not implemented
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }

    # Sync all paths in the tree
    if ($bRecursive)
    {
        my $oManifest = $self->manifest($strPathExp);

        # Iterate all files in the manifest
        foreach my $strFile (sort(keys(%{$oManifest})))
        {
            # Only sync if this is a directory
            if ($oManifest->{$strFile}{type} eq 'd')
            {
                # If current directory
                if ($strFile eq '.')
                {
                    $self->pathSync($strPathExp);
                }
                # Else a subdirectory
                else
                {
                    $self->pathSync("${strPathExp}/${strFile}");
                }
            }
        }
    }
    # Only sync the specified path
    else
    {
        filePathSync($self->pathGet($strPathExp));
    }

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# exists
#
# Checks for the existence of a file, but does not imply that the file is readable/writeable.
#
# Return: true if file exists, false otherwise
####################################################################################################################################
sub exists
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->exists', \@_,
            {name => 'strPathExp'},
        );

    # Set operation variables
    my $strPath = $self->pathGet($strPathExp);
    my $bExists;

    # Run remotely
    if ($self->isRemote())
    {
        $bExists = $self->{oProtocol}->cmdExecute(OP_FILE_EXISTS, [$strPath], true);
    }
    # Run locally
    else
    {
        $bExists = fileExists($strPath);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bExists', value => $bExists}
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
        $strPathExp,
        $bTemp,
        $bIgnoreMissing,
        $bPathSync,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->remove', \@_,
            {name => 'strPathExp'},
            {name => 'bTemp', required => false},
            {name => 'bIgnoreMissing', default => true},
            {name => 'bPathSync', default => false},
        );

    # Set operation variables
    my $strPath = $self->pathGet($strPathExp, {bTemp => $bTemp});
    my $bRemoved = true;

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        $bRemoved = fileRemove($strPath, $bIgnoreMissing, $bPathSync);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bRemoved', value => $bRemoved}
    );
}

####################################################################################################################################
# hash
####################################################################################################################################
sub hash
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $bCompressed,
        $strHashType
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hash', \@_,
            {name => 'strPathExp'},
            {name => 'bCompressed', required => false},
            {name => 'strHashType', required => false}
        );

    my ($strHash) = $self->hashSize($strPathExp, $bCompressed, $strHashType);

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strHash', value => $strHash, trace => true}
    );
}

####################################################################################################################################
# hashSize
####################################################################################################################################
sub hashSize
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $bCompressed,
        $strHashType
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hashSize', \@_,
            {name => 'strPathExp'},
            {name => 'bCompressed', default => false},
            {name => 'strHashType', default => 'sha1'}
        );

    # Set operation variables
    my $strFile = $self->pathGet($strPathExp);
    my $strHash;
    my $iSize = 0;

    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    else
    {
        ($strHash, $iSize) = fileHashSize($strFile, $bCompressed, $strHashType, $self->{oProtocol});
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strHash', value => $strHash},
        {name => 'iSize', value => $iSize}
    );
}

####################################################################################################################################
# owner
####################################################################################################################################
sub owner
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $strUser,
        $strGroup
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->owner', \@_,
            {name => 'strPathExp'},
            {name => 'strUser', required => false},
            {name => 'strGroup', required => false}
        );

    # Set operation variables
    my $strFileOp = $self->pathGet($strPathExp);

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        my $iUserId;
        my $iGroupId;

        # If the user or group is not defined then get it by stat'ing the file.  This is because the chown function requires that
        # both user and group be set.
        if (!(defined($strUser) && defined($strGroup)))
        {
            my $oStat = fileStat($strFileOp);

            if (!defined($strUser))
            {
                $iUserId = $oStat->uid;
            }

            if (!defined($strGroup))
            {
                $iGroupId = $oStat->gid;
            }
        }

        # Lookup user if specified
        if (defined($strUser))
        {
            $iUserId = getpwnam($strUser);

            if (!defined($iUserId))
            {
                confess &log(ERROR, "user '${strUser}' does not exist", ERROR_USER_MISSING);
            }
        }

        # Lookup group if specified
        if (defined($strGroup))
        {
            $iGroupId = getgrnam($strGroup);

            if (!defined($iGroupId))
            {
                confess &log(ERROR, "group '${strGroup}' does not exist", ERROR_GROUP_MISSING);
            }
        }

        # Set ownership on the file
        if (!chown($iUserId, $iGroupId, $strFileOp))
        {
            my $strError = $!;

            if (fileExists($strFileOp))
            {
                confess &log(ERROR,
                    "unable to set ownership for '${strFileOp}'" . (defined($strError) ? ": $strError" : ''), ERROR_FILE_OWNER);
            }

            confess &log(ERROR, "${strFileOp} does not exist", ERROR_FILE_MISSING);
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

####################################################################################################################################
# list
####################################################################################################################################
sub list
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
        $strExpression,
        $strSortOrder,
        $bIgnoreMissing
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->list', \@_,
            {name => 'strPathExp'},
            {name => 'strExpression', optional => true},
            {name => 'strSortOrder', optional => true, default => 'forward'},
            {name => 'bIgnoreMissing', optional => true, default => false}
        );

    # Set operation variables
    my $strPath = $self->pathGet($strPathExp);
    my @stryFileList;

    # Run remotely
    if ($self->isRemote())
    {
        @stryFileList = $self->{oProtocol}->cmdExecute(
            OP_FILE_LIST,
            [$strPath, {strExpression => $strExpression, strSortOrder => $strSortOrder, bIgnoreMissing => $bIgnoreMissing}]);
    }
    # Run locally
    else
    {
        @stryFileList = fileList(
            $strPath, {strExpression => $strExpression, strSortOrder => $strSortOrder, bIgnoreMissing => $bIgnoreMissing});
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'stryFileList', value => \@stryFileList}
    );
}

####################################################################################################################################
# wait
#
# Wait until the next second.  This is done in the file object because it must be performed on whichever side the db is on, local or
# remote.  This function is used to make sure that no files are copied in the same second as the manifest is created.  The reason is
# that the db might modify they file again in the same second as the copy and that change will not be visible to a subsequent
# incremental backup using timestamp/size to determine deltas.
####################################################################################################################################
sub wait
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $bWait
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->wait', \@_,
            {name => 'bWait', default => true}
        );

    # Second when the function was called
    my $lTimeBegin;

    # Run remotely
    if ($self->isRemote())
    {
        $lTimeBegin = $self->{oProtocol}->cmdExecute(OP_FILE_WAIT, [$bWait], true);
    }
    # Run locally
    else
    {
        # Wait the remainder of the current second
        $lTimeBegin = waitRemainder($bWait);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'lTimeBegin', value => $lTimeBegin, trace => true}
    );
}

####################################################################################################################################
# manifest
#
# Builds a path/file manifest starting with the base path and including all subpaths.  The manifest contains all the information
# needed to perform a backup or a delta with a previous backup.
####################################################################################################################################
sub manifest
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strPathExp,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->manifest', \@_,
            {name => 'strPathEpr'},
        );

    # Set operation variables
    my $strPath = $self->pathGet($strPathExp);
    my $hManifest;

    # Run remotely
    if ($self->isRemote())
    {
        $hManifest = $self->{oProtocol}->cmdExecute(OP_FILE_MANIFEST, [$strPath], true);
    }
    # Run locally
    else
    {
        $hManifest = fileManifest($strPath);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hManifest', value => $hManifest, trace => true}
    );
}

####################################################################################################################################
# put
#
# Writes a buffer out to storage all at once.  Useful for configuration files or other smallish data.
####################################################################################################################################
sub put
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFileExp,
        $xContent,
        $bSync,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->put', \@_,
            {name => 'strFileExp'},
            {name => 'xContent', optional => true},
            {name => 'bSync', optional => true, default => true},
        );

    # Set operation variables
    my $strFile = $self->pathGet($strFileExp);

    # Run remotely
    if ($self->isRemote())
    {
        confess &log(ASSERT, "${strOperation}: remote operation not supported");
    }
    # Run locally
    else
    {
        fileStringWrite($strFile, ref($xContent) ? $$xContent : $xContent, $bSync);
    }

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# copy
#
# Copies a file from one location to another:
#
# * source and destination can be local or remote
# * wire and output compression/decompression are supported
# * intermediate temp files are used to prevent partial copies
# * modification time, mode, and ownership can be set on destination file
# * destination path can optionally be created
####################################################################################################################################
sub copy
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strSourcePathExp,
        $strDestinationPathExp,
        $bSourceCompressed,
        $bDestinationCompress,
        $bIgnoreMissingSource,
        $lModificationTime,
        $strMode,
        $bDestinationPathCreate,
        $strUser,
        $strGroup,
        $bAppendChecksum,
        $bPathSync,
        $strExtraFunction,
        $rExtraParam,
        $bAtomic,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->copy', \@_,
            {name => 'strSourcePathExp'},
            {name => 'strDestinationPathExp'},
            {name => 'bSourceCompressed', optional => true, default => false},
            {name => 'bDestinationCompress', optional => true, default => false},
            {name => 'bIgnoreMissingSource', optional => true, default => false},
            {name => 'lModificationTime', optional => true},
            {name => 'strMode', optional => true, default => fileModeDefaultGet()},
            {name => 'bDestinationPathCreate', optional => true, default => false},
            {name => 'strUser', optional => true},
            {name => 'strGroup', optional => true},
            {name => 'bAppendChecksum', optional => true, default => false},
            {name => 'bPathSync', optional => true, default => false},
            {name => 'strExtraFunction', optional => true},
            {name => 'rExtraParam', optional => true},
            {name => 'bAtomic', optional => true, default => true},
        );

    # Temp file is required if checksum will be appended
    if ($bAppendChecksum && !$bAtomic)
    {
        confess &log(ASSERT, 'bAtomic must be true when bAppendChecksum is true');
    }

    # Create/get source IO
    my $oSourceIO;
    my $bSourceRemote = false;
    my $strSourceFile;

    if (ref($strSourcePathExp))
    {
        $oSourceIO = $strSourcePathExp;
    }
    elsif ($strSourcePathExp eq PIPE_STDIN || $self->isRemote())
    {
        # $oSourceIO = new pgBackRest::Protocol::IO::IO(*STDIN, undef, undef, 30, 4 * 1024 * 1024);
        $bSourceRemote = true;
    }
    else
    {
        my $hSourceFile;
        $strSourceFile = $self->pathGet($strSourcePathExp);

        if (!sysopen($hSourceFile, $strSourceFile, O_RDONLY))
        {
            my $strError = $!;
            my $iErrorCode = ERROR_FILE_READ;

            if ($!{ENOENT})
            {
                # $strError = 'file is missing';
                $iErrorCode = ERROR_FILE_MISSING;

                if ($bIgnoreMissingSource && $strDestinationPathExp ne PIPE_STDOUT)
                {
                    return false, undef, undef;
                }
            }

            $strError = "cannot open source file ${strSourceFile}: " . $strError;

            # if ($strSourcePathType eq PATH_ABSOLUTE)
            # {
                if ($strDestinationPathExp eq PIPE_STDOUT)
                {
                    $self->{oProtocol}->binaryXferAbort();
                }
            # }

            confess &log(ERROR, $strError, $iErrorCode);
        }

        $oSourceIO = new pgBackRest::Protocol::IO::IO($hSourceFile, undef, undef, 30, 4 * 1024 * 1024);
    }

    # Create/get destination IO
    my $oDestinationIO;
    my $bDestinationRemote = false;
    my $strDestinationFile;
    my $strDestinationFileTmp;

    if (ref($strDestinationPathExp))
    {
        $oDestinationIO = $strDestinationPathExp;
    }
    elsif ($strDestinationPathExp eq PIPE_STDIN || $self->isRemote())
    {
        $bDestinationRemote = true;
    }
    else
    {
        my $hDestinationFile;
        $strDestinationFile = $self->pathGet($strDestinationPathExp);
        $strDestinationFileTmp = $bAtomic ? $self->pathGet($strDestinationPathExp, {bTemp => true}) : $strDestinationFile;

        my $iCreateFlag = O_WRONLY | O_CREAT;

        # Open the destination temp file
        if (!sysopen($hDestinationFile, $strDestinationFileTmp, $iCreateFlag, oct($strMode)))
        {
            if ($bDestinationPathCreate)
            {
                filePathCreate(dirname($strDestinationFileTmp), undef, true, true);
            }

            if (!$bDestinationPathCreate || !sysopen($hDestinationFile, $strDestinationFileTmp, $iCreateFlag, oct($strMode)))
            {
                my $strError = "unable to open ${strDestinationFileTmp}: " . $!;
                my $iErrorCode = ERROR_FILE_READ;

                if (!fileExists(dirname($strDestinationFileTmp)))
                {
                    $strError = dirname($strDestinationFileTmp) . ' destination path does not exist';
                    $iErrorCode = ERROR_FILE_MISSING;
                }

                if (!($bDestinationPathCreate && $iErrorCode == ERROR_FILE_MISSING))
                {
                    confess &log(ERROR, $strError, $iErrorCode);
                }
            }
        }

        # Now lock the file to be sure nobody else is operating on it
        if (!flock($hDestinationFile, LOCK_EX | LOCK_NB))
        {
            confess &log(ERROR, "unable to acquire exclusive lock on ${strDestinationFileTmp}", ERROR_LOCK_ACQUIRE);
        }

        # Set user and/or group if required
        if (defined($strUser) || defined($strGroup))
        {
            $self->owner($strDestinationFileTmp, $strUser, $strGroup);
        }

        $oDestinationIO = new pgBackRest::Protocol::IO::IO(undef, $hDestinationFile, undef, 30, 4 * 1024 * 1024);
    }

    # Convert function name to a function reference
    my $fnExtra =
        defined($strExtraFunction) ? eval("\\&${strExtraFunction}") : undef;    ## no critic (BuiltinFunctions::ProhibitStringyEval)

    # Checksum and size variables
    my $strChecksum = undef;
    my $iFileSize = undef;
    my $rExtra = undef;
    my $bResult = true;

    # If source or destination are remote
    if ($bSourceRemote || $bDestinationRemote)
    {
        # Build the command and open the local file
        # my $hIn,
        # my $hOut;
        my $strRemote;
        my $strRemoteOp;
        my $bController = false;

        # If source is remote and destination is local
        if ($bSourceRemote && !$bDestinationRemote)
        {
            # $hOut = $hDestinationFile;
            $strRemoteOp = OP_FILE_COPY_OUT;
            $strRemote = 'in';

            if ($strSourcePathExp ne PIPE_STDIN)
            {
                $self->{oProtocol}->cmdWrite($strRemoteOp,
                    [$strSourceFile, $bSourceCompressed, $bDestinationCompress, undef, undef, undef, undef, undef, undef, undef,
                        undef, $strExtraFunction, $rExtraParam, $bAtomic]);

                $bController = true;
            }
        }
        # Else if source is local and destination is remote
        elsif (!$bSourceRemote && $bDestinationRemote)
        {
            # $hIn = $hSourceFile;
            $strRemoteOp = OP_FILE_COPY_IN;
            $strRemote = 'out';

            if ($strDestinationPathExp ne PIPE_STDOUT)
            {
                $self->{oProtocol}->cmdWrite(
                    $strRemoteOp,
                    [$strDestinationFile, $bSourceCompressed, $bDestinationCompress, undef, undef, $strMode,
                        $bDestinationPathCreate, $strUser, $strGroup, $bAppendChecksum, $bPathSync, $strExtraFunction,
                        $rExtraParam, $bAtomic]);

                $bController = true;
            }
        }
        # Else source and destination are remote
        else
        {
            $strRemoteOp = OP_FILE_COPY;

            $self->{oProtocol}->cmdWrite(
                $strRemoteOp,
                [defined($strSourceFile) ? $strSourceFile : $strSourcePathExp,
                    defined($strDestinationFile) ? $strDestinationFile : $strDestinationPathExp, $bSourceCompressed,
                    $bDestinationCompress, $bIgnoreMissingSource, undef, $strMode, $bDestinationPathCreate, $strUser, $strGroup,
                    $bAppendChecksum, $bPathSync, $strExtraFunction, $rExtraParam, $bAtomic]);

            $bController = true;
        }

        # Transfer the file (skip this for copies where both sides are remote)
        if ($strRemoteOp ne OP_FILE_COPY)
        {
            ($strChecksum, $iFileSize, $rExtra) =
                $self->{oProtocol}->binaryXfer(
                    $oSourceIO, $oDestinationIO, $strRemote, $bSourceCompressed, $bDestinationCompress, undef, $fnExtra,
                    $rExtraParam);
        }

        # If this is the controlling process then wait for OK from remote
        if ($bController)
        {
            # Test for an error when reading output
            eval
            {
                ($bResult, my $strResultChecksum, my $iResultFileSize, my $rResultExtra) =
                    $self->{oProtocol}->outputRead(true, $bIgnoreMissingSource);

                # Check the result of the remote call
                if ($bResult)
                {
                    # If the operation was purely remote, get checksum/size
                    if ($strRemoteOp eq OP_FILE_COPY ||
                        $strRemoteOp eq OP_FILE_COPY_IN && $bSourceCompressed && !$bDestinationCompress)
                    {
                        # Checksum shouldn't already be set
                        if (defined($strChecksum) || defined($iFileSize))
                        {
                            confess &log(ASSERT, "checksum and size are already defined, but shouldn't be");
                        }

                        $strChecksum = $strResultChecksum;
                        $iFileSize = $iResultFileSize;
                        $rExtra = $rResultExtra;
                    }
                }

                return true;
            }
            # If there is an error then evaluate
            or do
            {
                my $oException = $EVAL_ERROR;

                # Ignore error if source file was missing and missing file exception was returned and bIgnoreMissingSource is set
                if ($bIgnoreMissingSource && $strRemote eq 'in' && exceptionCode($oException) == ERROR_FILE_MISSING)
                {
                    close($oDestinationIO->outputHandle())
                        or confess &log(ERROR, "cannot close file ${strDestinationFileTmp}");
                    fileRemove($strDestinationFileTmp);

                    $bResult = false;
                }
                else
                {
                    confess $oException;
                }
            };
        }
    }
    # Else this is a local operation
    else
    {
        # If the source is not compressed and the destination is then compress
        if (!$bSourceCompressed && $bDestinationCompress)
        {
            ($strChecksum, $iFileSize, $rExtra) =
                $self->{oProtocol}->binaryXfer($oSourceIO, $oDestinationIO, 'out', false, true, false, $fnExtra, $rExtraParam);
        }
        # If the source is compressed and the destination is not then decompress
        elsif ($bSourceCompressed && !$bDestinationCompress)
        {
            ($strChecksum, $iFileSize, $rExtra) =
                $self->{oProtocol}->binaryXfer($oSourceIO, $oDestinationIO, 'in', true, false, false, $fnExtra, $rExtraParam);
        }
        # Else both sides are compressed, so copy capturing checksum
        elsif ($bSourceCompressed)
        {
            ($strChecksum, $iFileSize, $rExtra) =
                $self->{oProtocol}->binaryXfer($oSourceIO, $oDestinationIO, 'out', true, true, false, $fnExtra, $rExtraParam);
        }
        else
        {
            ($strChecksum, $iFileSize, $rExtra) =
                $self->{oProtocol}->binaryXfer($oSourceIO, $oDestinationIO, 'in', false, true, false, $fnExtra, $rExtraParam);
        }
    }

    if ($bResult)
    {
        # Close the source file (if local)
        if (defined($oSourceIO))
        {
            close($oSourceIO->inputHandle()) or confess &log(ERROR, "cannot close file ${strSourceFile}");
        }

        # Sync and close the destination file (if local)
        if (defined($oDestinationIO))
        {
            $oDestinationIO->outputHandle()->sync()
                or confess &log(ERROR, "unable to sync ${strDestinationFileTmp}", ERROR_FILE_SYNC);

            close($oDestinationIO->outputHandle())
                or confess &log(ERROR, "cannot close file ${strDestinationFileTmp}");
        }

        # Checksum and file size should be set if the destination is not remote
        if (!(!$bSourceRemote && $bDestinationRemote && $bSourceCompressed) &&
            (!defined($strChecksum) || !defined($iFileSize)))
        {
            confess &log(ASSERT, 'checksum or file size not set');
        }

        # Where the destination is local, set mode, modification time, and perform move to final location
        if (!$bDestinationRemote)
        {
            # Set the file modification time if required
            if (defined($lModificationTime))
            {
                utime($lModificationTime, $lModificationTime, $strDestinationFileTmp)
                    or confess &log(ERROR, "unable to set time for local ${strDestinationFileTmp}");
            }

            # Replace checksum in destination filename (if exists)
            if ($bAppendChecksum)
            {
                # Replace destination filename
                if ($bDestinationCompress)
                {
                    $strDestinationFile =
                        substr($strDestinationFile, 0, length($strDestinationFile) - length($self->{strCompressExtension}) - 1) .
                        '-' . $strChecksum . '.' . $self->{strCompressExtension};
                }
                else
                {
                    $strDestinationFile .= '-' . $strChecksum;
                }
            }

            # Move the file from tmp to final destination
            if ($bAtomic)
            {
                fileMove($strDestinationFileTmp, $strDestinationFile, $bDestinationPathCreate, $bPathSync);
            }
            # Else sync path if requested
            elsif ($bPathSync)
            {
                filePathSync(dirname($strDestinationFile));
            }
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bResult', value => $bResult, trace => true},
        {name => 'strChecksum', value => $strChecksum, trace => true},
        {name => 'iFileSize', value => $iFileSize, trace => true},
        {name => '$rExtra', value => $rExtra, trace => true},
    );
}

####################################################################################################################################
# Getters
####################################################################################################################################
sub pathBase {shift->{strPathBase}}

1;

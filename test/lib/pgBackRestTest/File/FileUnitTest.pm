####################################################################################################################################
# FileUnitTest.pm - Unit tests for File module.
####################################################################################################################################
package pgBackRestTest::File::FileUnitTest;
use parent 'pgBackRestTest::File::FileCommonTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Storage::Storage;

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Setup test directory and get file object
    my $oLocalFile = $self->setup(false, false);

    # Test File->pathGet()
    #---------------------------------------------------------------------------------------------------------------------------
    if ($self->begin("Storage->pathGet()"))
    {
        # Test temp file errors
        $self->testException(
            sub {$oLocalFile->pathGet(PATH_REPO . '/test', {bTemp => true})},
            ERROR_ASSERT, "temp file not supported for path type <REPO>");
        $self->testException(
            sub {$oLocalFile->pathGet()},
            ERROR_ASSERT, "strPathExp is required in Storage::Storage->pathGet");
        $self->testException(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE, {bTemp => true})},
            ERROR_ASSERT, "file part must be defined when temp file specified for path type <REPO:ARCHIVE>");
        $self->testException(
            sub {$oLocalFile->pathGet(PATH_SPOOL_ARCHIVE_OUT, {bTemp => true})},
            ERROR_ASSERT, "file part must be defined when temp file specified for path type <SPOOL:ARCHIVE:OUT>");
        $self->testException(
            sub {$oLocalFile->pathGet(PATH_REPO_BACKUP_TMP, {bTemp => true})},
            ERROR_ASSERT, "file part must be defined when temp file specified for path type <REPO:BACKUP:TMP>");

        # Test absolute path
        # $self->testException(
        #     sub {$oLocalFile->pathGet()}, ERROR_ASSERT, "strFile must be defined for absolute path");
        $self->testException(
            sub {$oLocalFile->pathGet('file')}, ERROR_ASSERT, 'relative files not supported');
        $self->testResult(sub {$oLocalFile->pathGet('/file', {bTemp => true})}, "/file.pgbackrest.tmp", 'absolute path temp');
        $self->testResult(sub {$oLocalFile->pathGet('/file')}, "/file", 'absolute path file');

        # Test backup path
        $self->testResult(sub {$oLocalFile->pathGet(PATH_REPO . '/file')}, $self->testPath() . '/file', 'backup path file');
        $self->testResult(sub {$oLocalFile->pathGet(PATH_REPO)}, $self->testPath(), 'backup path');

        # Error when stanza not defined
        $self->testException(
            sub {(new pgBackRest::Storage::Storage(undef, $self->testPath(), $self->local()))->pathGet(PATH_REPO_BACKUP_TMP)},
            ERROR_ASSERT, "strStanza not defined");

        # Test backup tmp path
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_BACKUP_TMP . '/file', {bTemp => true})},
            $self->testPath() . '/temp/db.tmp/file.pgbackrest.tmp',
            'backup temp path temp file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_BACKUP_TMP . '/file')}, $self->testPath() . '/temp/db.tmp/file', 'backup temp path file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_BACKUP_TMP)}, $self->testPath() . '/temp/db.tmp', 'backup temp path');

        # Test archive path
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE, undef)}, $self->testPath() . '/archive/db', 'archive path');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE . '/9.3-1')}, $self->testPath() . '/archive/db/9.3-1', 'archive id path');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/000000010000000100000001')},
            $self->testPath() . '/archive/db/9.3-1/0000000100000001/000000010000000100000001',
            'archive path file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/000000010000000100000001', {bTemp => true})},
            $self->testPath() . '/archive/db/9.3-1/0000000100000001/000000010000000100000001.pgbackrest.tmp',
            'archive path temp file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/00000001.history')},
            $self->testPath() . '/archive/db/9.3-1/00000001.history',
            'archive path history file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_ARCHIVE . '/9.3-1/00000001.history', {bTemp => true})},
            $self->testPath() . '/archive/db/9.3-1/00000001.history.pgbackrest.tmp',
            'archive path history temp file');

        # Test archive out path
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_SPOOL_ARCHIVE_OUT . '/000000010000000100000001')},
            $self->testPath() . '/archive/db/out/000000010000000100000001',
            'archive out path file');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_SPOOL_ARCHIVE_OUT)}, $self->testPath() . '/archive/db/out', 'archive out path');
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_SPOOL_ARCHIVE_OUT . '/000000010000000100000001', {bTemp => true})},
            $self->testPath() . '/archive/db/out/000000010000000100000001.pgbackrest.tmp',
            'archive out path temp file');

        # Test backup cluster path
        $self->testResult(
            sub {$oLocalFile->pathGet(PATH_REPO_BACKUP . '/file')}, $self->testPath() . '/backup/db/file', 'cluster path file');
        $self->testResult(sub {$oLocalFile->pathGet(PATH_REPO_BACKUP)}, $self->testPath() . '/backup/db', 'cluster path');

        # Test invalid path type
        $self->testException(sub {$oLocalFile->pathGet('<bogus>')}, ERROR_ASSERT, "invalid path type <bogus>");
    }
}

1;

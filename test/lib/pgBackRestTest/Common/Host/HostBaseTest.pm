####################################################################################################################################
# HostBackupTest.pm - Backup host
####################################################################################################################################
package pgBackRestTest::Common::Host::HostBaseTest;
use parent 'pgBackRestTest::Common::HostTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Cwd qw(abs_path);
use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);

use pgBackRest::Common::Log;
use pgBackRest::Storage::Posix::StoragePosixCommon;
use pgBackRest::Version;

use pgBackRestTest::Common::ContainerTest;
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::RunTest;
use pgBackRestTest::Common::VmTest;

####################################################################################################################################
# Host constants
####################################################################################################################################
use constant HOST_BASE                                              => 'base';
    push @EXPORT, qw(HOST_BASE);
use constant HOST_DB_MASTER                                         => 'db-master';
    push @EXPORT, qw(HOST_DB_MASTER);
use constant HOST_DB_STANDBY                                        => 'db-standby';
    push @EXPORT, qw(HOST_DB_STANDBY);
use constant HOST_BACKUP                                            => 'backup';
    push @EXPORT, qw(HOST_BACKUP);

####################################################################################################################################
# new
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strName,
        $oParam,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strName', default => HOST_BASE, trace => true},
            {name => 'oParam', required => false, trace => true},
        );

    my $strTestPath = testRunGet()->testPath() . ($strName eq HOST_BASE ? '' : "/${strName}");
    filePathCreate($strTestPath, '0770');

    # Create the host
    my $strProjectPath = dirname(dirname(abs_path($0)));
    my $strContainer = 'test-' . testRunGet()->vmId() . "-$strName";

    my $self = $class->SUPER::new(
        $strName, $strContainer, $$oParam{strImage}, $$oParam{strUser}, testRunGet()->vm(),
        ["${strProjectPath}:${strProjectPath}", "${strTestPath}:${strTestPath}"
        ,dirname(dirname($strTestPath)) . '/cover_db:' . dirname(dirname($strTestPath)) . '/cover_db']);
    bless $self, $class;

    # Set test path
    $self->{strTestPath} = $strTestPath;

    # Set permissions on the test path
    $self->executeSimple('chown -R ' . $self->userGet() . ':'. TEST_GROUP . ' ' . $self->testPath(), undef, 'root');

    # Install Perl C Library
    my $oVm = vmGet();
    my $strBuildPath = testRunGet()->basePath() . "/test/.vagrant/libc/$self->{strOS}";
    my $strPerlAutoPath = $$oVm{$self->{strOS}}{&VMDEF_PERL_ARCH_PATH} . '/auto/pgBackRest/LibC';
    my $strPerlModulePath = $$oVm{$self->{strOS}}{&VMDEF_PERL_ARCH_PATH} . '/pgBackRest';

    $self->executeSimple(
        "mkdir -p -m 755 ${strPerlAutoPath} && " .
        # "cp ${strBuildPath}/blib/arch/auto/pgBackRest/LibC/LibC.bs ${strPerlAutoPath} && " .
        "cp ${strBuildPath}/blib/arch/auto/pgBackRest/LibC/LibC.so ${strPerlAutoPath} && " .
        "cp ${strBuildPath}/blib/lib/auto/pgBackRest/LibC/autosplit.ix ${strPerlAutoPath} && " .
        "mkdir -p -m 755 ${strPerlModulePath} && " .
        "cp ${strBuildPath}/blib/lib/pgBackRest/LibC.pm ${strPerlModulePath}",
        undef, 'root');

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self, trace => true}
    );
}

####################################################################################################################################
# Getters
####################################################################################################################################
sub testPath {return shift->{strTestPath}}

1;

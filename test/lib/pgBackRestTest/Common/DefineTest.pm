####################################################################################################################################
# DefineTest.pm - Defines all tests that can be run
####################################################################################################################################
package pgBackRestTest::Common::DefineTest;

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();

use pgBackRest::Common::Log;
use pgBackRest::Common::String;

################################################################################################################################
# Test definition constants
################################################################################################################################
use constant TESTDEF_MODULE                                         => 'module';
    push @EXPORT, qw(TESTDEF_MODULE);
use constant TESTDEF_NAME                                           => 'name';
    push @EXPORT, qw(TESTDEF_NAME);
use constant TESTDEF_TEST                                           => 'test';
    push @EXPORT, qw(TESTDEF_TEST);

# Determines if the test will be run against multiple db versions
use constant TESTDEF_DB                                             => 'db';
    push @EXPORT, qw(TESTDEF_DB);
# Determines if the test will be run in a container or will create containers itself
use constant TESTDEF_CONTAINER                                      => 'container';
    push @EXPORT, qw(TESTDEF_CONTAINER);
# Determines coverage for the test
use constant TESTDEF_COVERAGE                                       => 'coverage';
    push @EXPORT, qw(TESTDEF_COVERAGE);
# Should expect log tests be run
use constant TESTDEF_EXPECT                                         => 'expect';
    push @EXPORT, qw(TESTDEF_EXPECT);
# Determines if each run in a test will be run in a new container
use constant TESTDEF_INDIVIDUAL                                     => 'individual';
    push @EXPORT, qw(TESTDEF_INDIVIDUAL);
# Determines if the test will be run with multiple processes
use constant TESTDEF_PROCESS                                        => 'process';
    push @EXPORT, qw(TESTDEF_PROCESS);
# Total runs in the test
use constant TESTDEF_TOTAL                                          => 'total';
    push @EXPORT, qw(TESTDEF_TOTAL);

# The test provides full coverage for the module
use constant TESTDEF_COVERAGE_FULL                                  => true;
    push @EXPORT, qw(TESTDEF_COVERAGE_FULL);
# The test provides partial coverage for the module
use constant TESTDEF_COVERAGE_PARTIAL                               => false;
    push @EXPORT, qw(TESTDEF_COVERAGE_PARTIAL);

################################################################################################################################
# Code modules
################################################################################################################################
use constant TESTDEF_MODULE_FILE                                    => 'File';
    push @EXPORT, qw(TESTDEF_MODULE_FILE);
use constant TESTDEF_MODULE_FILE_COMMON                             => TESTDEF_MODULE_FILE . 'Common';
    push @EXPORT, qw(TESTDEF_MODULE_FILE_COMMON);

use constant TESTDEF_MODULE_ARCHIVE                                 => 'Archive';
    push @EXPORT, qw(TESTDEF_MODULE_ARCHIVE);
use constant TESTDEF_MODULE_ARCHIVE_COMMON                          => TESTDEF_MODULE_ARCHIVE . '/ArchiveCommon';
    push @EXPORT, qw(TESTDEF_MODULE_ARCHIVE_COMMON);
use constant TESTDEF_MODULE_ARCHIVE_PUSH                            => TESTDEF_MODULE_ARCHIVE . '/ArchivePush';
    push @EXPORT, qw(TESTDEF_MODULE_ARCHIVE_PUSH);
use constant TESTDEF_MODULE_ARCHIVE_PUSH_ASYNC                      => TESTDEF_MODULE_ARCHIVE_PUSH . 'Async';
    push @EXPORT, qw(TESTDEF_MODULE_ARCHIVE_PUSH_ASYNC);
use constant TESTDEF_MODULE_ARCHIVE_PUSH_FILE                       => TESTDEF_MODULE_ARCHIVE_PUSH . 'File';
    push @EXPORT, qw(TESTDEF_MODULE_ARCHIVE_PUSH_FILE);

use constant TESTDEF_MODULE_BACKUP_COMMON                           => 'BackupCommon';
    push @EXPORT, qw(TESTDEF_MODULE_BACKUP_COMMON);

use constant TESTDEF_MODULE_COMMON                                  => 'Common';
    push @EXPORT, qw(TESTDEF_MODULE_COMMON);
use constant TESTDEF_MODULE_COMMON_INI                              => TESTDEF_MODULE_COMMON . '/Ini';
    push @EXPORT, qw(TESTDEF_MODULE_COMMON_INI);

use constant TESTDEF_MODULE_INFO                                    => 'Info';
    push @EXPORT, qw(TESTDEF_MODULE_INFO);

use constant TESTDEF_MODULE_STANZA                                  => 'Stanza';
    push @EXPORT, qw(TESTDEF_MODULE_STANZA);

use constant TESTDEF_MODULE_STORAGE                                 => 'Storage';
    push @EXPORT, qw(TESTDEF_MODULE_STORAGE);
use constant TESTDEF_MODULE_STORAGE_STORAGES3                       => TESTDEF_MODULE_STORAGE . '/StorageS3';
    push @EXPORT, qw(TESTDEF_MODULE_STORAGE_STORAGES3);
use constant TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3             => TESTDEF_MODULE_STORAGE_STORAGES3 . '/StorageS3';
    push @EXPORT, qw(TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3);
use constant TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3AUTH         => TESTDEF_MODULE_STORAGE_STORAGES3 . '/StorageS3Auth';
    push @EXPORT, qw(TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3AUTH);

use constant TESTDEF_MODULE_EXPIRE                                  => 'Expire';
    push @EXPORT, qw(TESTDEF_MODULE_EXPIRE);

################################################################################################################################
# Define tests
################################################################################################################################
my $oTestDef =
{
    &TESTDEF_MODULE =>
    [
        # Help tests
        {
            &TESTDEF_NAME => 'help',
            &TESTDEF_CONTAINER => true,
            &TESTDEF_EXPECT => true,

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'help',
                    &TESTDEF_TOTAL => 1,
                }
            ]
        },
        # Config tests
        {
            &TESTDEF_NAME => 'config',
            &TESTDEF_CONTAINER => true,

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 7,
                },
                {
                    &TESTDEF_NAME => 'option',
                    &TESTDEF_TOTAL => 34,
                },
                {
                    &TESTDEF_NAME => 'config',
                    &TESTDEF_TOTAL => 25,
                }
            ]
        },
        # File tests
        {
            &TESTDEF_NAME => 'file',
            &TESTDEF_CONTAINER => true,

            &TESTDEF_COVERAGE =>
            {
                &TESTDEF_MODULE_FILE => TESTDEF_COVERAGE_PARTIAL,
                &TESTDEF_MODULE_FILE_COMMON => TESTDEF_COVERAGE_PARTIAL,
            },

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 1,
                },
                {
                    &TESTDEF_NAME => 'owner',
                    &TESTDEF_TOTAL => 8,
                },
                {
                    &TESTDEF_NAME => 'path-create',
                    &TESTDEF_TOTAL => 8,
                },
                {
                    &TESTDEF_NAME => 'move',
                    &TESTDEF_TOTAL => 24,
                },
                {
                    &TESTDEF_NAME => 'compress',
                    &TESTDEF_TOTAL => 4,
                },
                {
                    &TESTDEF_NAME => 'wait',
                    &TESTDEF_TOTAL => 2,
                },
                {
                    &TESTDEF_NAME => 'link',
                    &TESTDEF_TOTAL => 1,
                },
                {
                    &TESTDEF_NAME => 'stat',
                    &TESTDEF_TOTAL => 1,
                },
                {
                    &TESTDEF_NAME => 'manifest',
                    &TESTDEF_TOTAL => 5,
                },
                {
                    &TESTDEF_NAME => 'list',
                    &TESTDEF_TOTAL => 72,
                },
                {
                    &TESTDEF_NAME => 'remove',
                    &TESTDEF_TOTAL => 32,
                },
                {
                    &TESTDEF_NAME => 'hash',
                    &TESTDEF_TOTAL => 16,
                },
                {
                    &TESTDEF_NAME => 'exists',
                    &TESTDEF_TOTAL => 6,
                },
                {
                    &TESTDEF_NAME => 'copy',
                    &TESTDEF_TOTAL => 144,
                }
            ]
        },
        # Storage tests
        {
            &TESTDEF_NAME => 'storage',
            &TESTDEF_CONTAINER => true,

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 's3',
                    &TESTDEF_TOTAL => 1,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3 => TESTDEF_COVERAGE_PARTIAL,
                    },
                },
                {
                    &TESTDEF_NAME => 's3-auth',
                    &TESTDEF_TOTAL => 5,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_STORAGE_STORAGES3_STORAGES3AUTH => TESTDEF_COVERAGE_FULL,
                    },
                },
            ]
        },
        # Info tests
        {
            &TESTDEF_NAME => 'info',
            &TESTDEF_CONTAINER => true,

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'ini-unit',
                    &TESTDEF_TOTAL => 10,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_COMMON_INI => TESTDEF_COVERAGE_FULL,
                    },
                },
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 1,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_INFO => TESTDEF_COVERAGE_PARTIAL,
                    },
                },
            ]
        },
        # Stanza tests
        {
            &TESTDEF_NAME => 'stanza',

            &TESTDEF_COVERAGE =>
            {
                &TESTDEF_MODULE_STANZA => TESTDEF_COVERAGE_PARTIAL,
            },

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 2,
                    &TESTDEF_CONTAINER => true,
                },
                {
                    &TESTDEF_NAME => 'create',
                    &TESTDEF_TOTAL => 2,
                    &TESTDEF_EXPECT => true,
                },
                {
                    &TESTDEF_NAME => 'upgrade',
                    &TESTDEF_TOTAL => 2,
                    &TESTDEF_EXPECT => true,
                },
            ]
        },
        # Archive tests
        {
            &TESTDEF_NAME => 'archive',

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 4,
                    &TESTDEF_CONTAINER => true,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_ARCHIVE_COMMON => TESTDEF_COVERAGE_PARTIAL,
                    },
                },
                {
                    &TESTDEF_NAME => 'push-unit',
                    &TESTDEF_TOTAL => 7,
                    &TESTDEF_CONTAINER => true,

                    &TESTDEF_COVERAGE =>
                    {
                        &TESTDEF_MODULE_ARCHIVE_PUSH => TESTDEF_COVERAGE_FULL,
                        &TESTDEF_MODULE_ARCHIVE_PUSH_ASYNC => TESTDEF_COVERAGE_FULL,
                        &TESTDEF_MODULE_ARCHIVE_PUSH_FILE => TESTDEF_COVERAGE_FULL,
                    },
                },
                {
                    &TESTDEF_NAME => 'push',
                    &TESTDEF_TOTAL => 8,
                    &TESTDEF_PROCESS => true,
                    &TESTDEF_INDIVIDUAL => true,
                    &TESTDEF_EXPECT => true,
                },
                {
                    &TESTDEF_NAME => 'stop',
                    &TESTDEF_TOTAL => 6,
                    &TESTDEF_INDIVIDUAL => true,
                    &TESTDEF_EXPECT => true,
                },
                {
                    &TESTDEF_NAME => 'get',
                    &TESTDEF_TOTAL => 8,
                    &TESTDEF_INDIVIDUAL => true,
                    &TESTDEF_EXPECT => true,
                },
            ]
        },
        # Backup tests
        {
            &TESTDEF_NAME => 'backup',
            &TESTDEF_CONTAINER => true,

            &TESTDEF_COVERAGE =>
            {
                &TESTDEF_MODULE_BACKUP_COMMON => TESTDEF_COVERAGE_FULL,
            },

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'unit',
                    &TESTDEF_TOTAL => 3,
                },
                {
                    &TESTDEF_NAME => 'info-unit',
                    &TESTDEF_TOTAL => 1,
                },
            ]
        },
        # Expire tests
        {
            &TESTDEF_NAME => 'expire',
            &TESTDEF_EXPECT => true,
            &TESTDEF_INDIVIDUAL => true,

            &TESTDEF_COVERAGE =>
            {
                &TESTDEF_MODULE_EXPIRE => TESTDEF_COVERAGE_PARTIAL,
            },

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'expire',
                    &TESTDEF_TOTAL => 2,
                },
            ]
        },
        # Full tests
        {
            &TESTDEF_NAME => 'full',
            &TESTDEF_EXPECT => true,
            &TESTDEF_INDIVIDUAL => true,
            &TESTDEF_PROCESS => true,

            &TESTDEF_TEST =>
            [
                {
                    &TESTDEF_NAME => 'synthetic',
                    &TESTDEF_TOTAL => 8,
                },
                {
                    &TESTDEF_NAME => 'real',
                    &TESTDEF_TOTAL => 11,
                    &TESTDEF_DB => true,
                }
            ]
        },
    ]
};

####################################################################################################################################
# Process normalized data into a more queryable form
####################################################################################################################################
my $hTestDefHash;                                                   # An easier way to query hash version of the above
my @stryModule;                                                     # Ordered list of modules
my $hModuleTest;                                                    # Ordered list of tests for each module
my $hCoverageType;                                                  # Coverage type for each code module (full/partial)
my $hCoverageList;                                                  # Tests required for full code module coverage (if type full)

# Iterate each module
foreach my $hModule (@{$oTestDef->{&TESTDEF_MODULE}})
{
    # Push the module onto the ordered list
    my $strModule = $hModule->{&TESTDEF_NAME};
    push(@stryModule, $strModule);

    # Iterate each test
    my @stryModuleTest;

    foreach my $hModuleTest (@{$hModule->{&TESTDEF_TEST}})
    {
        # Push the test on the order list
        my $strTest = $hModuleTest->{&TESTDEF_NAME};
        push(@stryModuleTest, $strTest);

        # Resolve variables that can be set in the module or the test
        foreach my $strVar (
            TESTDEF_CONTAINER, TESTDEF_EXPECT, TESTDEF_PROCESS, TESTDEF_DB, TESTDEF_INDIVIDUAL)
        {
            $hTestDefHash->{$strModule}{$strTest}{$strVar} = coalesce(
                $hModuleTest->{$strVar}, coalesce($hModule->{$strVar}, false));
        }

        # Set test count
        $hTestDefHash->{$strModule}{$strTest}{&TESTDEF_TOTAL} = $hModuleTest->{&TESTDEF_TOTAL};

        # Concatenate coverage for modules and tests
        foreach my $hCoverage ($hModule->{&TESTDEF_COVERAGE}, $hModuleTest->{&TESTDEF_COVERAGE})
        {
            foreach my $strCodeModule (sort(keys(%{$hCoverage})))
            {
                if (defined($hTestDefHash->{$strModule}{$strTest}{&TESTDEF_COVERAGE}{$strCodeModule}))
                {
                    confess &log(ASSERT,
                        "${strCodeModule} is defined for coverage in both module ${strModule} and test ${strTest}");
                }

                $hTestDefHash->{$strModule}{$strTest}{&TESTDEF_COVERAGE}{$strCodeModule} = $hCoverage->{$strCodeModule};

                # Build coverage type hash and make sure coverage type does not change
                if (!defined($hCoverageType->{$strCodeModule}))
                {
                    $hCoverageType->{$strCodeModule} = $hCoverage->{$strCodeModule};
                }
                elsif ($hCoverageType->{$strCodeModule} != $hCoverage->{$strCodeModule})
                {
                    confess &log(ASSERT, "cannot mix full/partial coverage for ${strCodeModule}");
                }

                # Add to coverage list
                push(@{$hCoverageList->{$strCodeModule}}, {strModule=> $strModule, strTest => $strTest});
            }
        }
    }

    $hModuleTest->{$strModule} = \@stryModuleTest;
}

####################################################################################################################################
# testDefModuleList
####################################################################################################################################
sub testDefModuleList
{
    return @stryModule;
}

push @EXPORT, qw(testDefModuleList);

####################################################################################################################################
# testDefModule
####################################################################################################################################
sub testDefModule
{
    my $strModule = shift;

    if (!defined($hTestDefHash->{$strModule}))
    {
        confess &log(ASSERT, "unable to find module ${strModule}");
    }

    return $hTestDefHash->{$strModule};
}

push @EXPORT, qw(testDefModule);


####################################################################################################################################
# testDefModuleTestList
####################################################################################################################################
sub testDefModuleTestList
{
    my $strModule = shift;

    if (!defined($hModuleTest->{$strModule}))
    {
        confess &log(ASSERT, "unable to find module ${strModule}");
    }

    return @{$hModuleTest->{$strModule}};
}

push @EXPORT, qw(testDefModuleTestList);

####################################################################################################################################
# testDefModuleTest
####################################################################################################################################
sub testDefModuleTest
{
    my $strModule = shift;
    my $strModuleTest = shift;

    if (!defined($hTestDefHash->{$strModule}{$strModuleTest}))
    {
        confess &log(ASSERT, "unable to find module ${strModule}, test ${strModuleTest}");
    }

    return $hTestDefHash->{$strModule}{$strModuleTest};
}

push @EXPORT, qw(testDefModuleTest);

####################################################################################################################################
# testDefCoverageType
####################################################################################################################################
sub testDefCoverageType
{
    return $hCoverageType;
}

push @EXPORT, qw(testDefCoverageType);

####################################################################################################################################
# testDefCoverageList
####################################################################################################################################
sub testDefCoverageList
{
    return $hCoverageList;
}

push @EXPORT, qw(testDefCoverageList);

1;

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
    A registry key as lines of text for the diagnostic package. The keys are made in Pester's
    TestRegistry drive, which Pester removes after the file.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    if (-not (Get-Module -Name IntuneScriptLab)) {
        Import-Module (Join-Path $script:ModuleRoot 'IntuneScriptLab.psd1')
    }

    function script:Get-Text {
        param([string]$Key, [int]$Depth)
        InModuleScope IntuneScriptLab -Parameters @{ Key = $Key; Depth = $Depth } {
            @(Get-IslRegistryText -Key $Key -Depth $Depth)
        }
    }

    $script:Key = 'TestRegistry:\Policies'
    $null = New-Item -Path $script:Key
    $null = New-ItemProperty -Path $script:Key -Name 'Name' -Value 'Widget'
    $null = New-ItemProperty -Path $script:Key -Name 'Blob' -PropertyType Binary -Value ([byte[]](1, 2, 3))
    $null = New-ItemProperty -Path $script:Key -Name 'Long' -Value ('x' * 450)
    $null = New-ItemProperty -Path $script:Key -Name 'PSVersion' -Value '5.1'
    $null = New-Item -Path "$($script:Key)\Child"
    $null = New-ItemProperty -Path "$($script:Key)\Child" -Name 'Inner' -Value 1
    $null = New-Item -Path "$($script:Key)\Child\Grandchild"
}

Describe 'Get-IslRegistryText' -Tag 'Unit', 'Private' {

    It 'writes each key and each of its values, and leaves out the provider''s own properties' {
        $lines = Get-Text -Key $script:Key -Depth 3

        $lines[0] | Should-BeLikeString '`[*\Policies`]'
        $lines | Should-ContainCollection '  Name = Widget'
        $providerPattern = '^  PS(Path|ParentPath|ChildName|Drive|Provider) = '
        $providerLines = @($lines | Where-Object { $_ -match $providerPattern })
        $providerLines | Should-BeCollection @()
    }

    It 'keeps a value of the key whose name starts with PS' {
        $lines = Get-Text -Key $script:Key -Depth 0

        $lines | Should-ContainCollection '  PSVersion = 5.1'
        @($lines | Where-Object { $_ -like '`[*\Child`]' }) | Should-BeCollection -Count 1
        $lines | Should-ContainCollection '  Inner = 1'
    }

    It 'shows a binary value by its length and cuts a long value at 400 characters' {
        $lines = Get-Text -Key $script:Key -Depth 0

        $lines | Should-ContainCollection '  Blob = byte[3]'
        $long = @($lines | Where-Object { $_ -like '  Long = *' })
        $long | Should-BeCollection -Count 1
        $long[0] | Should-Be ('  Long = ' + ('x' * 400) + '...')
    }

    It 'gives Depth + 1 levels of subkeys below the key' {
        $shallow = Get-Text -Key $script:Key -Depth 0
        $deep = Get-Text -Key $script:Key -Depth 1

        # Depth 0: the key and its subkeys, without the grandchild
        $shallowKeys = @($shallow | Where-Object { $_ -like '`[*' })
        $shallowKeys | Should-BeCollection -Count 2
        @($shallowKeys | Where-Object { $_ -like '`[*Grandchild`]' }) | Should-BeCollection @()
        @($deep | Where-Object { $_ -like '`[*Grandchild`]' }) | Should-BeCollection -Count 1
    }

    It 'passes over a key that is there but cannot be read, without an error' {
        # A key in the test registry that the current user may not read; Test-Path still finds it
        $null = New-Item -Path 'TestRegistry:\Denied\Child' -Force
        $root = (Get-PSDrive -Name TestRegistry).Root -replace '^HKEY_CURRENT_USER\\', ''
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $rights = [System.Security.AccessControl.RegistryRights]::ReadKey
        $deny = [System.Security.AccessControl.RegistryAccessRule]::new($user, $rights, 'Deny')
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            "$root\Denied", [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $sections = [System.Security.AccessControl.AccessControlSections]::Access
        $acl = $key.GetAccessControl($sections)
        $acl.AddAccessRule($deny)
        $key.SetAccessControl($acl)
        try {
            $output = InModuleScope IntuneScriptLab {
                Get-IslRegistryText -Key 'TestRegistry:\Denied' -Depth 1 -ErrorAction Continue 2>&1
            }
        } finally {
            # Pester removes the test registry after the file, which the rule would stop
            $acl = $key.GetAccessControl($sections)
            $null = $acl.RemoveAccessRule($deny)
            $key.SetAccessControl($acl)
            $key.Dispose()
        }

        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should-BeCollection @()
        @($output) | Should-BeCollection @()
    }

    It 'gives one line for a key that is not there' {
        $missing = 'TestRegistry:\NotThere'
        Get-Text -Key $missing -Depth 1 | Should-BeCollection @("$missing : not present")
    }
}

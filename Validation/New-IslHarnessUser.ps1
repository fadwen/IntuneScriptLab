#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
    .SYNOPSIS
        Creates the standard local account the user-context harness runs scripts as, on a lab device.

    .DESCRIPTION
        Run on the device itself (through the guest agent as SYSTEM, or in an elevated session). The
        password is generated here and never printed: it is stored as a DPAPI-protected PSCredential
        for the identity running this script, at -CredentialPath, which is what the harness tests
        read (ISL_TEST_CREDENTIAL) and what Invoke-Intune*Test -Credential takes.

        With -AutoLogon the account also becomes the console user at the next boot, through the LSA
        DefaultPassword secret (not the plaintext registry value), so the harness can use an
        interactive scheduled task in that session, the way the agent runs user-context scripts in
        the signed-in user's session (Findings.md, REM-PROBE-USER64). A registry DefaultPassword
        that would take precedence is renamed, unread, to DefaultPassword.isl-parked.

    .PARAMETER UserName
        The local account name. Default isl-user.

    .PARAMETER OutputPath
        Where the PSCredential is exported. Default C:\ProgramData\IntuneScriptLab\<UserName>.cred.xml.

    .PARAMETER AutoLogon
        Make the account the console user at the next boot (the script does not reboot).

    .EXAMPLE
        .\New-IslHarnessUser.ps1 -AutoLogon; Restart-Computer

        Creates isl-user, stores its credential for SYSTEM and logs it on at the next boot.

    .EXAMPLE
        $cred = Import-Clixml C:\ProgramData\IntuneScriptLab\isl-user.cred.xml
        Invoke-IntunePlatformScriptTest -Path .\who.ps1 -Context User -Credential $cred

        The harness running the script as that account, from the same identity that ran this script.

    .EXAMPLE
        $env:ISL_TEST_CREDENTIAL = 'C:\ProgramData\IntuneScriptLab\isl-user.cred.xml'
        Invoke-Pester .\Tests\Integration\UserContext.Tests.ps1

        The module's user-context integration test against the account.

    .INPUTS
        None.

    .OUTPUTS
        None. Progress lines only; the password is never written to the output.

    .NOTES
        Author: Jeffrey Stuhr. Export-Clixml protects the password with DPAPI for the current
        identity: a credential written as SYSTEM can be read back as SYSTEM only.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$UserName = 'isl-user',

    [string]$OutputPath = "C:\ProgramData\IntuneScriptLab\$UserName.cred.xml",

    [switch]$AutoLogon
)

$ErrorActionPreference = 'Stop'
$folder = Split-Path -Path $OutputPath -Parent
New-Item -ItemType Directory -Path $folder -Force | Out-Null

$bytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$plain = ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'x') + 'Aa1!'
$secure = New-Object System.Security.SecureString
foreach ($char in $plain.ToCharArray()) { $secure.AppendChar($char) }
$secure.MakeReadOnly()

if (-not $PSCmdlet.ShouldProcess($UserName, 'Create the account and store its credential')) { return }
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $UserName -Password $secure
    Write-Information -InformationAction Continue -MessageData "$UserName existed; password rotated"
}
else {
    $newUserSplat = @{
        Name                 = $UserName
        Password             = $secure
        PasswordNeverExpires = $true
        AccountNeverExpires  = $true
        # New-LocalUser caps the description at 48 characters
        Description          = 'IntuneScriptLab harness account (standard user)'
    }
    New-LocalUser @newUserSplat | Out-Null
    Add-LocalGroupMember -Group 'Users' -Member $UserName
    Write-Information -InformationAction Continue -MessageData "$UserName created as a standard user"
}
[pscredential]::new("$env:COMPUTERNAME\$UserName", $secure) | Export-Clixml -Path $OutputPath
Write-Information -InformationAction Continue -MessageData "Credential stored at $OutputPath"

if (-not $AutoLogon) { return }

$lsaSource = @'
using System;
using System.Runtime.InteropServices;
public class IslLsa {
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES {
        public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes;
        public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
    }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName,
        ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr PolicyHandle,
        ref LSA_UNICODE_STRING KeyName, ref LSA_UNICODE_STRING PrivateData);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr ObjectHandle);
    [DllImport("advapi32.dll")] static extern uint LsaNtStatusToWinError(uint Status);
    static LSA_UNICODE_STRING Str(string s) {
        var u = new LSA_UNICODE_STRING();
        u.Buffer = Marshal.StringToHGlobalUni(s);
        u.Length = (ushort)(s.Length * 2);
        u.MaximumLength = (ushort)((s.Length + 1) * 2);
        return u;
    }
    public static void SetSecret(string key, string value) {
        var system = new LSA_UNICODE_STRING();
        var attributes = new LSA_OBJECT_ATTRIBUTES();
        attributes.Length = Marshal.SizeOf(attributes);
        IntPtr handle;
        uint status = LsaOpenPolicy(ref system, ref attributes, 0x000F0FFF, out handle);
        if (status != 0) throw new Exception("LsaOpenPolicy failed: " + LsaNtStatusToWinError(status));
        var k = Str(key);
        var v = Str(value);
        status = LsaStorePrivateData(handle, ref k, ref v);
        LsaClose(handle);
        if (status != 0) throw new Exception("LsaStorePrivateData failed: " + LsaNtStatusToWinError(status));
    }
}
'@
if (-not ('IslLsa' -as [type])) { Add-Type -TypeDefinition $lsaSource }
[IslLsa]::SetSecret('DefaultPassword', $plain)

$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ((Get-Item -Path $winlogon).GetValueNames() -contains 'DefaultPassword') {
    Rename-ItemProperty -Path $winlogon -Name 'DefaultPassword' -NewName 'DefaultPassword.isl-parked'
    Write-Information -InformationAction Continue -MessageData 'Registry DefaultPassword parked (unread)'
}
Set-ItemProperty -Path $winlogon -Name 'DefaultUserName' -Value $UserName
Set-ItemProperty -Path $winlogon -Name 'DefaultDomainName' -Value $env:COMPUTERNAME
Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '1'
Write-Information -InformationAction Continue -MessageData "Autologon set for $UserName; reboot to sign it in"

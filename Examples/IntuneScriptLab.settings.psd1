@{
    # IntuneScriptLab.settings.psd1: put it in the folder that holds the scripts, or any folder
    # above them; the nearest one applies to every script below it. Every key is optional.
    # Explicit parameters to Test-IntuneScript win over these; a '# IntuneScriptLab:' directive in
    # a script wins over the type, context, architecture and signature entries.

    # Rules to skip everywhere (wildcards allowed). The context note is the usual one to drop once
    # the folder layout or the entries below settle every script's type.
    ExcludeRule = @('IslAssumedContext')

    # Rules to run, everything else skipped; empty means all
    IncludeRule = @()

    # The lowest severity to report: Information, Warning or Error
    MinimumSeverity = 'Information'

    # Severity overrides per rule, for a rule the team wants to hear about but not fail on
    Severity = @{
        # IslLongSleep = 'Information'
    }

    # What every script under here is, when its directive says nothing: Detection, Remediation,
    # PlatformScript, Win32Detection or Win32Requirement
    # ScriptType = 'Remediation'

    # How they run when the directive says nothing: System or User; x86, x64 or arm64
    # Context = 'System'
    # Architecture = 'x64'

    # The Win32 rule's "Enforce script signature check", when the directive says nothing
    # EnforceSignatureCheck = $false
}

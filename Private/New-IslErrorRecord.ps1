function New-IslErrorRecord {
    <#
    .SYNOPSIS
    Builds the error record a function ends with.

    .DESCRIPTION
    A failure the module detects itself is raised with $PSCmdlet.ThrowTerminatingError() and an
    error record that has an ID and a category of its own, so that a caller can tell one failure
    from another without matching the message. This function builds that record: the exception is
    of the type named, carries the message, and wraps the error that caused it when there is one.

    The record is returned, not raised. The function that detected the failure raises it, so that
    the error names that function.

    The function does not fail for any message, ID or type. It is called in the argument of
    ThrowTerminatingError, and an error raised here would end only that statement: the calling
    function would go on as if it had detected nothing. An exception type that cannot be built
    from a message and an inner exception is therefore replaced by InvalidOperationException.

    .PARAMETER Message
    What failed and, where the caller can act on it, what to do.

    .PARAMETER ErrorId
    The ID of this failure, in PascalCase and without spaces. It is the first part of the
    FullyQualifiedErrorId; PowerShell adds the name of the function that raises the record.

    .PARAMETER Category
    The category of the error.

    .PARAMETER TargetObject
    What the function was working on when it failed, such as a path or a name.

    .PARAMETER ExceptionType
    The type of the exception, one that has a constructor taking a message and an inner
    exception. The default is System.InvalidOperationException.

    .PARAMETER InnerException
    The exception that caused the failure, kept as the inner exception.

    .EXAMPLE
    $record = New-IslErrorRecord -Message "$Path exists; use -Force" -ErrorId 'PathExists' -Category ResourceExists
    $PSCmdlet.ThrowTerminatingError($record)

    Ends the calling function with an error whose ID starts with PathExists.

    .EXAMPLE
    $recordSplat = @{ Message = 'No such event'; ErrorId = 'UnknownEvent'; Category = 'InvalidArgument' }
    # The value of the bad argument is the target, and the exception says that it was an argument
    New-IslErrorRecord @recordSplat -TargetObject $name -ExceptionType ([System.ArgumentException])

    A record for a bad argument.

    .INPUTS
    None.

    .OUTPUTS
    System.Management.Automation.ErrorRecord.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an error record and changes nothing.')]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$ErrorId,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory]$Category,

        [Parameter()]
        [AllowNull()]
        [object]$TargetObject,

        [Parameter()]
        [type]$ExceptionType = [System.InvalidOperationException],

        [Parameter()]
        [System.Exception]$InnerException
    )

    $exception = $null
    try {
        $exception = $ExceptionType::new($Message, $InnerException) -as [System.Exception]
    } catch {
        # The type has no such constructor. The record is still built: see the description
        Write-Debug "No $($ExceptionType.FullName) could be built for error $ErrorId."
    }
    if ($null -eq $exception) {
        $exception = [System.InvalidOperationException]::new($Message, $InnerException)
    }

    [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, $Category, $TargetObject)
}

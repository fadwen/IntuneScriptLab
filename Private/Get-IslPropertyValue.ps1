function Get-IslPropertyValue {
    <#
    .SYNOPSIS
    Gets a named value from a dictionary or an object, or nothing when it has none.

    .DESCRIPTION
    Data that reaches the module from outside has optional members and comes in two shapes: a
    Graph reply is a dictionary or an object depending on how it was read, a rule or a settings
    table is a hashtable the caller wrote, and a CIM call that fails returns nothing at all.
    Under strict mode a read of a member that is not there is an error, so every such read goes
    through this function, which returns nothing for a missing input, a missing key and a
    missing property alike.

    A collection is unrolled on the way out, like the output of any function. Wrap the call in
    @() where the value is a list.

    .PARAMETER InputObject
    The dictionary or object to read from. Nothing is returned when it is $null.

    .PARAMETER Name
    The key or property name.

    .EXAMPLE
    Get-IslPropertyValue -InputObject $page -Name '@odata.nextLink'

    The address of the next page of a Graph reply, or nothing on the last page.

    .EXAMPLE
    @(Get-IslPropertyValue -InputObject $policy -Name 'assignments')

    The assignments of a policy as an array, empty when the reply has none.

    .INPUTS
    None.

    .OUTPUTS
    System.Object. The value, or nothing when the input has no such member.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        # Called through the interface: a generic dictionary implements this method explicitly,
        # and PowerShell does not find it on the object itself
        if (([System.Collections.IDictionary]$InputObject).Contains($Name)) {
            return $InputObject[$Name]
        }
        return
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
}

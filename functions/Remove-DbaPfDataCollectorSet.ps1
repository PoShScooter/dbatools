﻿function Remove-DbaPfDataCollectorSet {
    <#
        .SYNOPSIS
            Removes a Performance Monitor Data Collector Set

        .DESCRIPTION
            Removes a Performance Monitor Data Collector Set

        .PARAMETER ComputerName
            The target computer.

        .PARAMETER Credential
            Allows you to login to $ComputerName using alternative credentials.

        .PARAMETER CollectorSet
            The Collector Set name
    
        .PARAMETER InputObject
            Enables piped results from Get-DbaPfDataCollectorSet

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
        .NOTES
            Tags: PerfMon
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    
        .LINK
            https://dbatools.io/Remove-DbaPfDataCollectorSet

        .EXAMPLE
            Remove-DbaPfDataCollectorSet
    
            Attempts to remove all ready Collectors on localhost

        .EXAMPLE
            Remove-DbaPfDataCollectorSet -ComputerName sql2017
    
            Attempts to remove all ready Collectors on localhost
    
        .EXAMPLE
            Remove-DbaPfDataCollectorSet -ComputerName sql2017, sql2016 -Credential (Get-Credential) -CollectorSet 'System Correlation'
    
            Removes the 'System Correlation' Collector on sql2017 and sql2016 using alternative credentials
    
        .EXAMPLE
            Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Remove-DbaPfDataCollectorSet
    
            Removes 'System Correlation' Collector
    
        .EXAMPLE
            Get-DbaPfDataCollectorSet -CollectorSet 'System Correlation' | Stop-DbaPfDataCollectorSet | Remove-DbaPfDataCollectorSet
    
            Stops and removes 'System Correlation' Collector
    #>
    [CmdletBinding()]
    param (
        [DbaInstance[]]$ComputerName,
        [PSCredential]$Credential,
        [Alias("DataCollectorSet")]
        [string[]]$CollectorSet,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $setscript = {
            $setname = $args
            $collectorset = New-Object -ComObject Pla.DataCollectorSet
            $collectorset.Query($setname, $null)
            if ($collectorset.name -eq $setname) {
                $null = $collectorset.Delete()
            }
            else {
                Write-Warning "Data Collector Set $setname does not exist on $env:COMPUTERNAME"
            }
        }
    }
    process {
        if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName))) {
            foreach ($computer in $ComputerName) {
                $InputObject += Get-DbaPfDataCollectorSet -ComputerName $computer -Credential $Credential -CollectorSet $CollectorSet
            }
        }
        
        if ($InputObject) {
            if (-not $InputObject.DataCollectorSetObject) {
                Stop-Function -Message "InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet"
                return
            }
        }
        
        # Check to see if its running first
        foreach ($set in $InputObject) {
            $setname = $set.Name
            $computer = $set.ComputerName
            $status = $set.State
            
            $null = Test-ElevationRequirement -ComputerName $instance -Continue
            
            Write-Message -Level Verbose -Message "$setname on $ComputerName is $status"
            
            if ($status -eq "Running") {
                Stop-Function -Message "$setname on $computer is running. Use Stop-DbaPfDataCollectorSet to stop first." -Continue
            }
            
            Write-Message -Level Verbose -Message "Connecting to $computer using Invoke-Command"
            try {
                Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock $setscript -ArgumentList $setname -ErrorAction Stop
                [pscustomobject]@{
                    ComputerName       = $computer
                    Name               = $setname
                    Status             = "Successful"
                }
            }
            catch {
                Stop-Function -Message "Failure Removing $setname on $computer" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}
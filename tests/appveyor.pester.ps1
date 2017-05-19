<# 
.SYNOPSIS 
This script will invoke Pester tests, then serialize XML results and pull them in appveyor.yml

.DESCRIPTION
Internal function that creates SMO server object.

.PARAMETER Finalize
If Finalize is specified, we collect XML output, upload tests, and indicate build errors

.PARAMETER PSVersion
The version of PS

.PARAMETER TestFile
The output file

.PARAMETER ProjectRoot
The appveyor project root 

.PARAMETER ModuleBase
The location of the module

.EXAMPLE
.\appveyor.pester.ps1
Executes the test

.EXAMPLE
.\appveyor.pester.ps1 -Finalize
Finalizes the tests
#>
param (
	[switch]$Finalize,
	$PSVersion = $PSVersionTable.PSVersion.Major,
	$TestFile = "TestResultsPS$PSVersion.xml",
	$ProjectRoot = $ENV:APPVEYOR_BUILD_FOLDER,
	$ModuleBase = $ProjectRoot
)

# Move to the project root
Set-Location $ProjectRoot
Import-Module "$ProjectRoot\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

#Run a test with the current version of PowerShell
#Make things faster by removing most output
if (-not $Finalize) {
	Write-Output "Testing with PowerShell $PSVersion"
	Import-Module Pester
	Set-Variable ProgressPreference -Value SilentlyContinue
	Invoke-Pester -Quiet -Script "$ProjectRoot\Tests" -OutputFormat NUnitXml -OutputFile "$ProjectRoot\$TestFile" -PassThru |
	Export-Clixml -Path "$ProjectRoot\PesterResults$PSVersion.xml"
}
else {
	#If finalize is specified, check for failures and  show status
	$allfiles = Get-ChildItem -Path $ProjectRoot\*Results*.xml | Select-Object -ExpandProperty FullName
	Write-Output "Finalizing results and collating the following files:"
	Write-Output ($allfiles | Out-String)
	
	#Upload results for test page
	Get-ChildItem -Path "$ProjectRoot\TestResultsPS*.xml" | Foreach-Object {
		
		$Address = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
		$Source = $_.FullName
		
		Write-Output "Uploading files: $Address $Source"
		
		(New-Object System.Net.WebClient).UploadFile($Address, $Source)
	}
	
	#What failed?
	$results = @(Get-ChildItem -Path "$ProjectRoot\PesterResults*.xml" | Import-Clixml)
	$failedcount = $results | Select-Object -ExpandProperty FailedCount | Measure-Object -Sum | Select-Object -ExpandProperty Sum
	
	if ($failedcount -gt 0) {
		$faileditems = $results | Select-Object -ExpandProperty TestResult | Where-Object { $_.Passed -notlike $True }
		
		if ($faileditems) {
			Write-Warning "Failed tests summary:"
			$faileditems | ForEach-Object {
				$name = $_.Name
				[pscustomobject]@{
					Describe = $_.Describe
					Context = $_.Context
					Name = "It $name"
					Result = $_.Result
				}
			} | Sort-Object Describe, Context, Name, Result | Format-List
			
			throw "$failedcount tests failed."
		}
	}
}
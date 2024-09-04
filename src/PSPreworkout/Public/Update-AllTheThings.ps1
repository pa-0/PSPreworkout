<#PSScriptInfo
.DESCRIPTION A script to automatically update all PowerShell modules, PowerShell Help, and packages (apt, brew, chocolately, winget).
.VERSION 0.4.5
.GUID 3a1a1ec9-0ef6-4f84-963d-be1505dab6a8
.AUTHOR Sam Erde
.COPYRIGHT (c) 2024 Sam Erde. All rights reserved.
.TAGS Update PowerShell Windows macOS Linux Ubuntu
.LICENSEURI https://github.com/SamErde/PSPreWorkout/blob/main/LICENSE
.PROJECTURI https://github.com/SamErde/PSPreWorkout/
.ICONURI
#>

function Update-AllTheThings {
    <#
    .SYNOPSIS
    Update all the things!

    .DESCRIPTION
    A script to automatically update all PowerShell modules, PowerShell Help, and packages (apt, brew, chocolately, winget).

    .EXAMPLE
    PS> Update-AllTheThings

    Updates all of the things it can!
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Update-AllTheThings', Justification = 'This is what we do.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive Use')]
    [Alias('uatt')]
    param (
        # Allow updates to pre-release PowerShell modules
        #[Parameter()]
        #[switch]
        #$AllowPrerelease
    )

    begin {
        # Spacing to get host output from script, winget, and choco all below the progress bar.
        $Banner = @"
  __  __        __     __         ___   ____
 / / / /__  ___/ /__ _/ /____    / _ | / / /
/ /_/ / _ \/ _  / _ `/ __/ -_)  / __ |/ / /
\____/ .__/\_,_/\_,_/\__/\__/  /_/ |_/_/_/
 ___/_/__         ________   _
/_  __/ /  ___   /_  __/ /  (_)__  ___ ____
 / / / _ \/ -_)   / / / _ \/ / _ \/ _ `(_-<
/_/ /_//_/\__/   /_/ /_//_/_/_//_/\_, /___/
                                 /___/ v0.4.5

"@
        Write-Host $Banner
    } # end begin block

    process {
        Write-Verbose 'Set the PowerShell Gallery as a trusted installation source.'
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        if (Get-Command -Name Set-PSResourceRepository -ErrorAction SilentlyContinue) {
            Set-PSResourceRepository -Name 'PSGallery' -Trusted
        }

        #region UpdatePowerShell
        # Get all installed PowerShell modules
        Write-Host '[1] Getting Installed PowerShell Modules'
        # Update the outer progress bar
        $PercentCompleteOuter = 1
        $ProgressParamOuter = @{
            Id               = 0
            Activity         = 'Update Everything'
            CurrentOperation = 'Getting Installed PowerShell Modules'
            Status           = "Progress: $PercentCompleteOuter`% Complete"
            PercentComplete  = $PercentCompleteOuter
        }
        Write-Progress @ProgressParamOuter
        $Modules = (Get-InstalledModule)
        $ModuleCount = $Modules.Count


        # Update all PowerShell modules
        Write-Host "[2] Updating $ModuleCount PowerShell Modules"
        # Estimate 10% progress so far and 70% at the next step
        $PercentCompleteOuter_Modules = 10
        [int]$Module_i = 0

        foreach ($module in $Modules) {
            # Update the module loop counter and percent complete for both progress bars
            ++$Module_i
            [double]$PercentCompleteInner = [math]::ceiling( (($Module_i / $ModuleCount) * 100) )
            [double]$PercentCompleteOuter = [math]::ceiling( $PercentCompleteOuter_Modules + (60 * ($PercentCompleteInner / 100)) )

            # Update the outer progress bar
            $ProgressParamOuter = @{
                Id              = 0
                Activity        = 'Update Everything'
                Status          = "Progress: $PercentCompleteOuter`% Complete"
                PercentComplete = $PercentCompleteOuter
            }
            Write-Progress @ProgressParamOuter

            # Update the child progress bar
            $ProgressParam1 = @{
                Id               = 1
                ParentId         = 0
                Activity         = 'Updating PowerShell Modules'
                CurrentOperation = "$($module.Name)"
                Status           = "Progress: $PercentCompleteInner`% Complete"
                PercentComplete  = $PercentCompleteInner
            }
            Write-Progress @ProgressParam1

            # Update the current module
            try {
                Update-Module $module.Name
                <# Test targeted prerelease updates
                if ($module.Version -match 'alpha|beta|prelease|preview') {
                    Update-Module $module.Name -AllowPrerelease -ErrorAction SilentlyContinue
                } else {
                    Update-Module $module.Name -ErrorAction SilentlyContinue
                }
                #>
            } catch [Microsoft.PowerShell.Commands.WriteErrorException] {
                Write-Verbose $_
            }
        }
        # Complete the child progress bar
        Write-Progress -Id 1 -Activity 'Updating PowerShell Modules' -Completed


        # Update PowerShell Help
        Write-Host '[3] Updating PowerShell Help'
        # Update the outer progress bar
        $PercentCompleteOuter = 70
        $ProgressParamOuter = @{
            Id               = 0
            Activity         = 'Update Everything'
            CurrentOperation = 'Updating PowerShell Help'
            Status           = "Progress: $PercentCompleteOuter`% Complete"
            PercentComplete  = $PercentCompleteOuter
        }
        Write-Progress @ProgressParamOuter
        # Fixes error with culture ID 127 (Invariant Country), which is not associated with any language
        if ((Get-Culture).LCID -eq 127) {
            Update-Help -UICulture en-US -ErrorAction SilentlyContinue
        } else {
            Update-Help -ErrorAction SilentlyContinue
        }
        #endregion UpdatePowerShell

        #region UpdateWinget
        if ($IsWindows -or ($PSVersionTable.PSVersion -ge [version]'5.1')) {

            if ((Get-CimInstance -ClassName CIM_OperatingSystem).Caption -match 'Server') {
                # If on Windows Server, prompt to continue before automatically updating packages.
                Write-Warning -Message 'This is a server and updates could affect production systems. Do you want to continue with updating packages?'

                $Yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Description.'
                $No = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Description.'
                $Options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)

                $Title = 'Windows Server OS Found'
                $Message = "Do you want to run 'winget update' on your server?"
                $Result = $Host.UI.PromptForChoice($Title, $Message, $Options, 1)
                switch ($Result) {
                    0 {
                        $SkipServer = $false
                    }
                    1 {
                        $SkipServer = $true
                    }
                }
            }

            # Update all winget packages
            Write-Host '[4] Updating Winget Packages'
            # Update the outer progress bar
            $PercentCompleteOuter = 80
            $ProgressParamOuter = @{
                Id               = 0
                Activity         = 'Update Everything'
                CurrentOperation = 'Updating Winget Packages'
                Status           = "Progress: $PercentCompleteOuter`% Complete"
                PercentComplete  = $PercentCompleteOuter
            }
            Write-Progress @ProgressParamOuter
            if (Get-Command winget -and -not $SkipServer) {
                winget upgrade --silent --scope user --accept-package-agreements --accept-source-agreements --all
            } else {
                Write-Host '[4] WinGet was not found or this is a server. Skipping winget update.'
            }
        } else {
            Write-Verbose '[4] Not Windows. Skipping WinGet.'
        }
        #endregion UpdateWinget

        #region UpdateLinuxPackages
        # Early testing. No progress bar yet. Need to check for admin, different distros, and different package managers.
        if ($IsLinux) {
            if (Get-Command apt -ErrorAction SilentlyContinue) {
                Write-Host '[5] Updating apt packages.'
                sudo apt update
                sudo apt upgrade
            }
        } else {
            Write-Verbose '[5] Not Linux. Skipping section.'
        }
        #endregion UpdateLinuxPackages

        #region UpdateMacOS
        # Early testing. No progress bar yet. Need to check for admin and different package managers.
        if ($IsMacOS) {
            softwareupdate -l
            if (Get-Command brew -ErrorAction SilentlyContinue) {
                Write-Host '[6] Updating brew packages.'
                brew update
                brew upgrade
            }
        } else {
            Write-Verbose '[6] Not macOS. Skipping section.'
        }
        #endregion UpdateMacOS

        #region UpdateChocolatey
        # Upgrade Chocolatey packages. Need to check for admin to avoid errors/warnings.
        if (Get-Command choco -ErrorAction SilentlyContinue -and -not $SkipServer) {
            # Update the outer progress bar
            $PercentCompleteOuter = 90
            $ProgressParamOuter = @{
                Id               = 0
                Activity         = 'Update Everything'
                CurrentOperation = 'Updating Chocolatey Packages'
                Status           = "Progress: $PercentCompleteOuter`% Complete"
                PercentComplete  = $PercentCompleteOuter
            }
            Write-Progress @ProgressParamOuter
            Write-Host '[7] Updating Chocolatey Packages'
            # Add a function/parameter to run these two feature configuration options, which requires admin to set.
            if (Test-IsElevated) {
                choco feature enable -n=allowGlobalConfirmation
                choco feature disable --name=showNonElevatedWarnings
            } else {
                Write-Verbose "Run once as an administrator to disable Chocoately's showNonElevatedWarnings." -Verbose
            }
            choco upgrade chocolatey -y --limit-output --accept-license --no-color
            choco upgrade all -y --limit-output --accept-license --no-color
            # Padding to reset host before updating the progress bar.
            Write-Host ' '
        } else {
            Write-Host '[7] Chocolatey is not installed. Skipping choco update.'
        }
        #endregion UpdateChocolatey

    } # end process block

    end {
        # Update the outer progress bar
        $PercentCompleteOuter = 100
        $ProgressParamOuter = @{
            Id               = 0
            Activity         = 'Update Everything'
            CurrentOperation = 'Finished'
            Status           = "Progress: $PercentCompleteOuter`% Complete"
            PercentComplete  = $PercentCompleteOuter
        }
        Write-Progress @ProgressParamOuter
        # Complete the outer progress bar
        Write-Progress -Id 0 -Activity 'Update Everything' -Completed
    }

}

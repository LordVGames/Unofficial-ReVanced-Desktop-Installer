$IsDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
$DefaultTextColor = (Get-Host).UI.RawUI.ForegroundColor
Set-Location $PSScriptRoot

#region General-use functions
function Set-Title([string]$Title)
{
    $Host.UI.RawUI.WindowTitle = $Title
}

function Exit-WithMessageAndPause()
{
    Write-Host "The script will now exit."
    pause
    if ($IsDotSourced)
    {
        return
    }
    exit
}

function Test-RequiredModule([string]$Module)
{
    if (Get-Module -ListAvailable -Name $Module)
    {
        return
    }

    Write-Host "The module " -NoNewline
    Write-Host "$Module" -ForegroundColor Green -NoNewline 
    Write-Host " does not exist!"
    Write-Host "This is needed for the script to run. Do you want to install it?"
    Write-Host "Type " -NoNewline
    Write-Host "Y " -ForegroundColor Yellow -NoNewline
    Write-Host "or " -NoNewline
    Write-Host "N" -ForegroundColor Yellow -NoNewline
    Write-Host ", then press " -NoNewline
    Write-Host "ENTER" -ForegroundColor Cyan -NoNewline
    Write-Host ": " -NoNewline
    $Prompt = Read-Host
    if ($Prompt -ne "y")
    {
        Exit-WithMessageAndPause
    }
    $OldErrorActionPreference = $ErrorActionPreference
    Install-Module $Module -Scope CurrentUser
    if (!$?)
    {
        Write-Host "An error occurred! " -ForegroundColor Red -NoNewline
        Write-Host " You may need to run PowerShell in administrator mode to install the module ""$Module""."
        pause
        exit
    }
    else
    {
        Write-Host "Done! Module """ -NoNewline
        Write-Host "$Module" -ForegroundColor Green -NoNewline
        Write-Host """ should have been installed for the current user!"
        pause
    }
    $ErrorActionPreference = $OldErrorActionPreference
    Clear-Host
}

function Read-DeviceNamesForIdsFromConfig()
{
    $FileName = $PSCommandPath.Split("\")[-1]
    $FileNameNoext = $FileName.SubString(0, $FileName.Length - 4)
	foreach ($Line in (Get-Content "$FileNameNoExt-device-names.conf"))
	{
		$LineSplit = $Line.Split("=")
		$DeviceSerial = $LineSplit[0]
		$DeviceName = $LineSplit[1]
		Set-Variable "DeviceNameForId-$DeviceSerial" $DeviceName -Scope Global
	}
}

function Get-AppApkFileName([string]$AppName)
{
    switch ($AppName)
    {
        "revanced-manager"
        {
            $FileList = Get-ChildItem -File -Name -Filter "revanced-manager*"
        }
        "YouTube"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*youtube*apk*" -Exclude "*music*"
        }
        "YouTube Music"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*youtube*music*apk*"
        }
        "Reddit"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*reddit*frontpage*"
        }
    }
    if ($FileList.Count -gt 1)
    {
        Write-Color "Multiple APK files for ",$AppName," have been found." $DefaultTextColor,Cyan,$DefaultTextColor
        $FileNum = 1
        foreach ($File in $FileList)
        {
            Write-Color $FileNum," - ",$File Cyan,$DefaultTextColor,Cyan
            $FileNum++
        }
        $ChosenNum = Read-Host "Please select the APK file you'd like to use"
        if ($null -eq $FileList[$ChosenNum - 1])
        {
            return Get-AppApkFileName $AppName
        }
        return $FileList[$ChosenNum - 1]
    }
    return $FileList
}

function Get-NameOfAppToPatchFromUser()
{
    Write-Host "Which ReVanced app would you like to install/update?"
    Write-Color "0"," - ","ReVanced Manager" Cyan,$DefaultTextColor,Cyan
    Write-Color "1"," - ","YouTube" Cyan,$DefaultTextColor,Cyan
    Write-Color "2"," - ","YouTube Music" Cyan,$DefaultTextColor,Cyan
    Write-Color "3"," - ","Reddit" Cyan,$DefaultTextColor,Cyan
    Write-Color "Type in the ","number ","of your choice, then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Cyan,$DefaultTextColor
    $ChosenApp = Read-Host
    switch ($ChosenApp)
    {
        0
        {
            Write-Host ''
            return "revanced-manager"
        }
        1
        {
            Write-Host ''
            return "YouTube"
        }
        2
        {
            Write-Host ''
            return "YouTube Music"
        }
        3
        {
            Write-Host ''
            return "Reddit"
        }
        default
        {
            return Get-NameOfAppToPatchFromUser
        }
    }
}

function Get-TargetVersionForAppPatches([string]$AppName)
{
    switch ($AppName)
    {
        "YouTube"
        {
            $AppInternalName = "com.google.android.youtube"
        }
        "YouTube Music"
        {
            $AppInternalName = "com.google.android.apps.youtube.music"
        }
        "Reddit"
        {
            $AppInternalName = "com.reddit.frontpage"
        }
        default
        {
            $AppInternalName = $AppName
        }
    }

    $Patches = Get-Content patches.json | ConvertFrom-Json
    $TargetVersionsOfPatchesForApp = @()
    foreach ($Patch in $Patches)
    {
        $PatchSupportedAppNames = $Patch.compatiblePackages.name
        $DoesPatchHaveTargetVersion = $null -ne $Patch.compatiblePackages.versions
        if ($PatchSupportedAppNames -and $PatchSupportedAppNames.Contains($AppInternalName) -and $DoesPatchHaveTargetVersion)
        {
            $TargetVersionsOfPatchesForApp += ,$Patch.compatiblePackages.versions
        }
    }

    $BestTargetVersion = $null
    foreach ($SetOfVersions in $TargetVersionsOfPatchesForApp)
    {
        $CurrentPatchLatestVersion = $SetOfVersions[-1]
        if ($null -eq $BestTargetVersion)
        {
            $BestTargetVersion = $CurrentPatchLatestVersion
        }
        if ((Compare-Versions $BestTargetVersion $CurrentPatchLatestVersion) -ne 1)
        {
            continue
        }

        $IsCurrentPatchLatestVersionInAllVersionSets = $true
        foreach ($SetOfVersionsAgain in $TargetVersionsOfPatchesForApp)
        {
            if (!$SetOfVersionsAgain.Contains($CurrentPatchLatestVersion))
            {
                $IsCurrentPatchLatestVersionInAllVersionSets = $false
            }
        }
        if ($IsCurrentPatchLatestVersionInAllVersionSets)
        {
            $BestTargetVersion = $CurrentPatchLatestVersion
        }
    }

    if ($null -eq $BestTargetVersion)
    {
        return "any"
    }
    else
    {
        return $BestTargetVersion
    }
}

function Get-VersionFromFileName([string]$FileName)
{
    $NumberRegex = "^\d+$"
    $FileNameCharArray = $FileName.ToCharArray()
    foreach ($Char in $FileNameCharArray)
    {
        if ($Char -match $NumberRegex)
        {
            $FirstNumIndex = $FileNameCharArray.IndexOf($Char)
            break
        }
    }
    
    $Version = $null
    $CurrentIndex = $FirstNumIndex
    foreach ($Char in $FileNameCharArray[$FirstNumIndex..($FileNameCharArray.Length - 1)])
    {
        if ($Char -eq ".")
        {
            if ($FileNameCharArray[($CurrentIndex + 1)] -notmatch $NumberRegex)
            {
                break
            }
        }
        elseif ($Char -notmatch $NumberRegex)
        {
            break
        }
        $Version += $Char
        $CurrentIndex++
    }
    return $Version
}

function Compare-Versions([string]$Version1, [string]$Version2)
{
    $Version1Parts = $Version1.Split(".")
    $Version2Parts = $Version2.Split(".")
    if ($Version1Parts.Count -gt $Version2Parts.Count)
    {
        $LargestPartCount = $Version1Parts.Count
    }
    else
    {
        $LargestPartCount = $Version2Parts.Count
    }
    
    for ($I = 0; $I -lt $Version1Parts.Count; $I++)
    {
        if ($Version1Parts[$I] -gt $Version2Parts[$I])
        {
            return 1
        }
        if ($Version1Parts[$I] -lt $Version2Parts[$I])
        {
            return 2
        }
        if ($I -eq $LargestPartCount - 1)
        {
            return 0
        }
    }
}
#endregion



#region ReVanced functions
function Get-ReVancedPartLatestInfo([string]$PartName)
{
    try
    {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/revanced/$PartName/releases/latest"
    }
    catch
    {
        $ErrorCode = $_.Exception.Response.StatusCode
        switch ($ErrorCode)
        {
            "NotFound"
            {
                Write-Color "ERROR: ","The ReVanced part ","$PartName ","does not exist!" Red,$DefaultTextColor,Yellow,$DefaultTextColor
                Exit-WithMessageAndPause
            }
            default:
            {
                Write-Color "ERROR: ","An error occurred during ","Get-ReVancedPartLatestInfo","! Error code: ","$ErrorCode" Red,$DefaultTextColor,Yellow,$DefaultTextColor,Yellow
                Exit-WithMessageAndPause
            }
        }
    }
}

function Install-ReVancedPartFilesFromInfo([string]$PartName, [PSCustomObject]$PartInfo)
{
    if (!$PartName)
    {
        Write-Color "ERROR! ","`$PartName ","was not specified in function ","""Install-ReVancedPartFiles""","!" Red,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor
        return
    }

    foreach ($FileInfo in $PartInfo.assets)
    {
        $NeededFileExtensions = @("apk","jar","json")
        $FileName = $FileInfo.browser_download_url.Split("/")[-1]
        $FileExtension = $FileName.Split(".")[-1]
        if ($FileExtension -inotin $NeededFileExtensions)
        {
            continue
        }
        Write-Color "Downloading ",$FileName,"..." $DefaultTextColor,Green,$DefaultTextColor
        if (Test-Path "./$FileName")
        {
            Write-Color "WARNING: ","The file ","$FileName ","already exists and will be removed before being re-downloaded." Yellow,$DefaultTextColor,Green,$DefaultTextColor
            Remove-Item "./$FileName"
        }
        Invoke-WebRequest $FileInfo.browser_download_url -OutFile $FileInfo.browser_download_url.Split("/")[-1]
    }
}

function Install-LatestReVancedPartFiles([string]$PartName)
{
    if (!$PartName)
    {
        Write-Host "ERROR! `$PartName was not specified in function ""Find-LatestReVancedPartFile""!"
        return
    }

    Write-Color "Checking for any updates for ","$PartName","..." $DefaultTextColor,Green,$DefaultTextColor
    $PartLatestInfo = Get-ReVancedPartLatestInfo $PartName
    $PartLatestVersion = $PartLatestInfo.tag_name.SubString(1) # SubString is here to remove a "v" at the start of the name
    if (Test-Path "./$PartName-$PartLatestVersion*")
    {
        Write-Color "The latest version of ","$PartName ","is already downloaded." $DefaultTextColor,Green,$DefaultTextColor
        return
    }

    if (Test-Path "./$PartName*")
    {
        $FilesWithPartName = Get-ChildItem -File -Name -Filter "$PartName*"
		foreach ($File in $FilesWithPartName)
		{
            $FileVersion = Get-VersionFromFileName $File
            switch (Compare-Versions $FileVersion $PartLatestVersion)
            {
                0
                {
                    Write-Color "The latest version of ",$PartName," is already downloaded." $DefaultTextColor,Green,$DefaultTextColor
                    return
                }
                1
                {
                    Write-Color "WARNING: ","The version ",$FileVersion," does not actually exist yet, so the file ","$File ","will be removed." Yellow,$DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor
                    Remove-Item $File
                }
                2
                {
                    Write-Color "The new version ","$PartLatestVersion ","is available!" $DefaultTextColor,Green,$DefaultTextColor
                    Write-Color "WARNING: ","The file ",$File," is an older version and will be removed." Yellow,$DefaultTextColor,Yellow,$DefaultTextColor
                    Remove-Item $File
                }
            }
            Install-ReVancedPartFilesFromInfo $PartName $PartLatestInfo
		}
        return
    }
    else
    {
        Write-Color "The file(s) for ",$PartName," do not exist yet! They will now be downloaded." $DefaultTextColor,Green,$DefaultTextColor
        Install-ReVancedPartFilesFromInfo $PartName $PartLatestInfo
    }
}

function Confirm-TargetedApkVersion([string]$FileVersion, [string]$TargetVersion)
{
    if ((Compare-Versions $FileVersion $TargetVersion) -eq 0 -or $TargetVersion -eq "any")
    {
        Write-Color "The target version for some patches (",$TargetVersion,") is the same as the APK version. Extra patches will now be applied!" $DefaultTextColor,Green,$DefaultTextColor
        return
    }

    $MessagePartsArray = @("WARNING: ","The version for your chosen APK file (",$FileVersion,") is ","not ","the same as the targeted version for some patches (",$TargetVersion,").")
    $MessageColorsArray = @("Yellow",$DefaultTextColor,"Cyan",$DefaultTextColor,"Yellow",$DefaultTextColor,"Cyan",$DefaultTextColor)
    Write-Color $MessagePartsArray $MessageColorsArray
    Write-Color "This means that you will ","lose out ","on some patches. Are you sure you want to continue?" $DefaultTextColor,Yellow,$DefaultTextColor
    Write-Color "Type ","Y ","or ","N",", then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor,Cyan -NoNewLine
    switch (Read-Host)
    {
        "n"
        {
            Exit-WithMessageAndPause
        }
        ($_ -notin "y")
        {
            Confirm-TargetedApkVersion $FileVersion $TargetVersion
            return
        }
    }
}

function Install-ReVancedAppToDeviceSerial([string]$AppName, [string]$DeviceSerial)
{
    if (!((Get-AdbDeviceSerials).Contains($DeviceSerial)))
    {
        Write-Color "ERROR! ","The device ID ",$DeviceSerial," is not connected to this PC!" Red,$DefaultTextColor,Yellow,$DefaultTextColor
        Exit-WithMessageAndPause
    }
    
    $ReVancedCliFileName = Get-ChildItem -File -Name -Filter "*revanced-cli*"
    $ReVancedPatchesFileName = Get-ChildItem -File -Name -Filter "*revanced-patches*"
    $ReVancedIntegrationsFileName = Get-ChildItem -File -Name -Filter "*revanced-integrations*"
    $ChosenApkFileName = Get-AppApkFileName $AppName
    
    if ($AppName -eq "revanced-manager")
    {
        Write-Host ''
        ./adb -s $DeviceSerial install -r $ChosenApkFileName
        return
    }

    Confirm-TargetedApkVersion (Get-VersionFromFileName $ChosenApkFileName) (Get-TargetVersionForAppPatches $AppName)
    $SpecificPatches = (Get-SpecificReVancedPatchesFromUser).Split(",")
    
    Write-Host ''
    $ArgumentList = @(
        "-jar $ReVancedCliFileName",
        "patch",
        "--patch-bundle $ReVancedPatchesFileName",
        "--merge $ReVancedIntegrationsFileName",
        "--purge",
        "--device-serial $DeviceSerial",
        "$ChosenApkFileName"
    )
    foreach ($Patch in $SpecificPatches)
    {
        if ($Patch[0] -eq "-")
        {
            $ArgumentList += "--exclude ""$Patch"""
        }
        else
        {
            $ArgumentList += "--include ""$Patch"""
        }
    }
    Start-Process "java" -NoNewWindow -Wait -ArgumentList $ArgumentList

    # Purging the resource cache directory is currently bugged and the ReVanced CLI doesn't remove it
    # So we gotta do it ourselves
    $ReVancedTemporaryFilesFolder = Get-ChildItem -Directory -Name "*-patched-temporary-files*"
    if ($ReVancedTemporaryFilesFolder)
    {
        Remove-item -Recurse $ReVancedTemporaryFilesFolder
    }
}

function Get-SpecificReVancedPatchesFromUser()
{
    Write-Color "Do you want to ","include ","or ","exclude ","any patches from the list of patches for your chosen app?" $DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor
    Write-Host "If so, list them all here, each separated by a comma."
    Write-Host "Put a dash in front of a patch you want to exclude."
    Write-Color "For example: GmsCore support,-Custom branding" $DefaultTextColor,Green
    Write-Host "Leave this blank and press ENTER to not include nor exclude any patches manually."
    return Read-Host
}

function Uninstall-ReVancedLeftovers()
{
    foreach ($File in Get-ChildItem -File -Name -Filter "*PATCHED*")
    {
        Remove-Item $File
    }
}
#endregion



#region ADB functions
function Get-AdbDeviceSerials()
{
    ./adb shell exit | Out-Null
    $AdbDevicesOutput = ./adb devices
    $AdbDevicesList = @()
    foreach ($Line in $AdbDevicesOutput)
    {
        # Only the lines with the device IDs have a tab character
        if (!($Line.Contains("`t")))
        {
            continue
        }
        $AdbDevicesList += $Line.Split("`t")[0]
    }
    return $AdbDevicesList
}

function Assert-NoAdbDeviceSerials()
{
    Write-Color "ERROR: ","No devices were found connected to the computer! Devices must be connected to this PC to have ReVanced apps be installed/updated via this script." Red,$DefaultTextColor
    Write-Color "Press ","ENTER ","when you have ","connected your device(s) ","to this PC." $DefaultTextColor,Cyan,$DefaultTextColor,Yellow,$DefaultTextColor -NoNewLine
    Read-Host

    $DeviceList = Get-AdbDeviceSerials
    if ($DeviceList.Count -eq 0)
    {
        Assert-NoAdbDeviceSerials
        return
    }
}

function Confirm-SingleAdbDeviceToInstallTo([string]$DeviceSerial)
{
    $DeviceName = Get-Variable "DeviceNameForId-$DeviceSerial" -ValueOnly
    Write-Color "Only one device was detected.`nThe device ID is ",$DeviceSerial $DefaultTextColor,Cyan -NoNewLine
    if ($DeviceName)
    {
        Write-Color ", and the name is ",$DeviceName,"." $DefaultTextColor,Cyan,$DefaultTextColor
    }
    else
    {
        Write-Host "."
    }
    Write-Host "Do you want to install/update a ReVanced app on this device?"
    Write-Color "Type ","Y ","or ","N",", then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor,Cyan -NoNewLine
    switch (Read-Host)
    {
        "n"
        {
            Exit-WithMessageAndPause
        }
        ($_ -notin "y")
        {
            Confirm-SingleAdbDeviceToInstallTo $DeviceSerial
            return
        }
    }
}

function Get-AdbDeviceToInstallToFromList()
{
    Write-Host "The following devices were found:"
    $DeviceSerials = Get-AdbDeviceSerials
    $DeviceNum = 1
    foreach ($DeviceSerial in $DeviceSerials)
    {
        $DeviceName = Get-Variable "DeviceNameForId-$DeviceSerial" -ValueOnly

        Write-Color $DeviceNum," - ",$DeviceSerial Cyan,$DefaultTextColor,Cyan -NoNewline
        if ($DeviceName)
        {
            Write-Color " - ",$DeviceName $DefaultTextColor,Cyan -NoNewLine
        }
        Write-Host ''
        $DeviceNum++
    }
    Write-Color "Type in the ","number ","for the device you'd like to install/update ReVanced on, then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Cyan,$DefaultTextColor -NoNewLine
    $ChosenNum = Read-Host
    return $DeviceSerials[$ChosenNum - 1]
}
#endregion



if (!$IsDotSourced)
{
    Set-Title "Unofficial ReVanced Desktop Installer"
    Test-RequiredModule "PSWriteColor"
    Read-DeviceNamesForIdsFromConfig

    Install-LatestReVancedPartFiles "revanced-patches"
    Install-LatestReVancedPartFiles "revanced-integrations"
    Install-LatestReVancedPartFiles "revanced-manager"
    Install-LatestReVancedPartFiles "revanced-cli"
    Write-Host ''

    $DeviceList = Get-AdbDeviceSerials
    if ($DeviceList.Count -eq 0)
    {
        Assert-NoAdbDeviceSerials
        $DeviceList = Get-AdbDeviceSerials
    }
    switch ($DeviceList.Count)
    {
        1
        {
            $DeviceSerial = $DeviceList
            Confirm-SingleAdbDeviceToInstallTo $DeviceSerial
        }
        ($_ -in 2..99)
        {
            $DeviceSerial = Get-AdbDeviceToInstallToFromList
        }
    }
    Write-Host ''
    Install-ReVancedAppToDeviceSerial (Get-NameOfAppToPatchFromUser) $DeviceSerial
    Uninstall-ReVancedLeftovers

    Write-Host "Thank you for using the unofficial ReVanced desktop installer!" -ForegroundColor Green
    Exit-WithMessageAndPause
}
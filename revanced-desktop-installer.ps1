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

function Test-RequiredModule()
{
	$Module = "PSWriteColor"
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

function Read-DeviceNamesForIdsFromConf()
{
    $FileName = $PSCommandPath.Split("\")[-1]
    $FileNameNoext = $FileName.SubString(0, $FileName.Length - 4)
	foreach ($Line in (Get-Content "$FileNameNoExt-device-names.conf"))
	{
		$LineSplit = $Line.Split("=")
		$DeviceId = $LineSplit[0]
		$DeviceName = $LineSplit[1]
		Set-Variable "DeviceNameForId-$DeviceId" $DeviceName -Scope Global
		#Write-Host "The config name for device ID $DeviceId is $DeviceName"
	}
}

function Get-AppApkFileName([string]$AppName)
{
    switch ($AppName)
    {
        "YouTube"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*youtube*apk*" -Exclude "*music*"
        }
        "YouTube Music"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*youtube*music*apk*"
        }
        "Citra"
        {
            $FileList = Get-ChildItem -File -Name -Filter "*citra*"
        }
        "revanced-manager"
        {
            $FileList = Get-ChildItem -File -Name -Filter "revanced-manager*"
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
    Write-Color "3"," - ","Citra" Cyan,$DefaultTextColor,Cyan
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
        2
        {
            Write-Host ''
            return "Citra"
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
        "Citra"
        {
            $AppInternalName = "org.citra.citra_emu"
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
        $File = $FileInfo.browser_download_url.Split("/")[-1]
        Write-Color "Downloading ",$File,"..." $DefaultTextColor,Green,$DefaultTextColor
        if (Test-Path "./$File")
        {
            Write-Color "WARNING: ","The file ","$File ","already exists and will be removed before being re-downloaded." Yellow,$DefaultTextColor,Green,$DefaultTextColor
            Remove-Item "./$File"
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
                    Write-Color "New version ","$PartLatestVersion ","is available!" $DefaultTextColor,Green,$DefaultTextColor
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

function Install-ReVancedAppToDeviceId([string]$AppName, [string]$DeviceId)
{
    if (!((Get-AdbDeviceIds).Contains($DeviceId)))
    {
        Write-Color "ERROR! ","The device ID ",$DeviceId," is not connected to this PC!" Red,$DefaultTextColor,Yellow,$DefaultTextColor
        Exit-WithMessageAndPause
    }
    
    $ReVancedCliFileName = Get-ChildItem -File -Name -Filter "*revanced-cli*"
    $ReVancedPatchesFileName = Get-ChildItem -File -Name -Filter "*revanced-patches*"
    $ReVancedIntegrationsFileName = Get-ChildItem -File -Name -Filter "*revanced-integrations*"
    $ChosenApkFileName = Get-AppApkFileName $AppName
    $ChosenApkFileNameNoExt = $ChosenApkFileName.SubString(0, $ChosenApkFileName.Length - 4)
    
    if ($AppName -eq "revanced-manager")
    {
        Write-Host ''
        ./adb -s $DeviceId install -r $ChosenApkFileName
        return
    }

    Confirm-TargetedApkVersion (Get-VersionFromFileName $ChosenApkFileName) (Get-TargetVersionForAppPatches $AppName)
    $ExcludedPatches = (Get-ExcludedReVancedPatchesFromUser).Split(" ")
    Write-Host ''

    $ArgumentList = @(
        "-jar $ReVancedCliFileName",
        "-c",
        "-b $ReVancedPatchesFileName",
        "-m $ReVancedIntegrationsFileName",
        "-a $ChosenApkFileName",
        "-o ${ChosenApkFileNameNoExt}_PATCHED.apk",
        "-d $DeviceId"
    )
    if ($ExcludedPatches)
    {
        foreach ($Patch in $ExcludedPatches)
        {
            $ArgumentList += "-e $Patch"
        }
    }
    Start-Process "java" -NoNewWindow -Wait -ArgumentList $ArgumentList
}

function Get-ExcludedReVancedPatchesFromUser()
{
    Write-Color "Do you want to ","exclude ","any patches from the list of patches for your chosen app?" $DefaultTextColor,Yellow,$DefaultTextColor
    Write-Host "If so, list them all here, each separated by a space."
    Write-Host "Otherwise, press ENTER to not exclude any patches manually."
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
function Get-AdbDeviceIds()
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

function Assert-NoAdbDeviceIds()
{
    Write-Color "ERROR: ","No devices were found connected to the computer! Devices must be connected to this PC to have ReVanced be installed/updated via this script." Red,$DefaultTextColor
    Write-Color "Press ","ENTER ","when you have ","connected your device(s) ","to this PC." $DefaultTextColor,Cyan,$DefaultTextColor,Yellow,$DefaultTextColor -NoNewLine
    Read-Host

    $DeviceList = Get-AdbDeviceIds
    if ($DeviceList.Count -eq 0)
    {
        Assert-NoAdbDeviceIds
        return
    }
}

function Confirm-SingleAdbDeviceToInstallTo([string]$DeviceId)
{
    $DeviceName = Get-Variable "DeviceNameForId-$DeviceId" -ValueOnly
    Write-Color "Only one device was detected.`nThe device ID is ",$DeviceId $DefaultTextColor,Cyan -NoNewLine
    if ($DeviceName)
    {
        Write-Color ", and the name is ",$DeviceName,"." $DefaultTextColor,Cyan,$DefaultTextColor
    }
    else
    {
        Write-Host "."
    }
    Write-Host "Do you want to install/update ReVanced on this device?"
    Write-Color "Type ","Y ","or ","N",", then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Yellow,$DefaultTextColor,Cyan -NoNewLine
    switch (Read-Host)
    {
        "n"
        {
            Exit-WithMessageAndPause
        }
        ($_ -notin "y")
        {
            Confirm-SingleAdbDeviceToInstallTo $DeviceId
            return
        }
    }
}

function Get-AdbDeviceToInstallToFromList()
{
    Write-Host "The following devices were found:"
    $DeviceIds = Get-AdbDeviceIds
    # FOR TESTING $DeviceIds = @("ZYGFGDDPXT", "ZY2FSFSDFF", "ZSFFSFSDFF")
    $DeviceNum = 1
    foreach ($DeviceId in $DeviceIds)
    {
        $DeviceName = Get-Variable "DeviceNameForId-$DeviceId" -ValueOnly

        Write-Color $DeviceNum," - ",$DeviceId Cyan,$DefaultTextColor,Cyan -NoNewline
        if ($DeviceName)
        {
            Write-Color " - ",$DeviceName $DefaultTextColor,Cyan -NoNewLine
        }
        Write-Host ''
        $DeviceNum++
    }
    Write-Color "Type in the ","number ","for the device you'd like to install/update ReVanced on, then press ","ENTER",": " $DefaultTextColor,Yellow,$DefaultTextColor,Cyan,$DefaultTextColor -NoNewLine
    $ChosenNum = Read-Host
    return $DeviceIds[$ChosenNum - 1]
}
#endregion



if (!$IsDotSourced)
{
    Set-Title "Unofficial ReVanced Desktop Installer"
    Test-RequiredModule
    Read-DeviceNamesForIdsFromConf

    Install-LatestReVancedPartFiles "revanced-patches"
    Install-LatestReVancedPartFiles "revanced-integrations"
    Install-LatestReVancedPartFiles "revanced-manager"
    Install-LatestReVancedPartFiles "revanced-cli"
    Write-Host ''

    $DeviceList = Get-AdbDeviceIds
    if ($DeviceList.Count -eq 0)
    {
        Assert-NoAdbDeviceIds
    }
    switch ($DeviceList.Count)
    {
        1
        {
            $DeviceId = $DeviceList
            Confirm-SingleAdbDeviceToInstallTo $DeviceId
        }
        ($_ -in 2..99)
        {
            $DeviceId = Get-AdbDeviceToInstallToFromList
        }
    }
    Write-Host ''
    Install-ReVancedAppToDeviceId (Get-NameOfAppToPatchFromUser) $DeviceId
    Uninstall-ReVancedLeftovers

    Write-Host "Thank you for using the unofficial ReVanced desktop installer!" -ForegroundColor Green
    Exit-WithMessageAndPause
}
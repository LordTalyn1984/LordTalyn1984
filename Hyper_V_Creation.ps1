<#
.SYNOPSIS
    Pro-Level Hyper-V VM Builder.
    Provisions Hardware -> Mounts ISO -> Injects Network/Domain/SCCM via PS-Direct.
    
.DESCRIPTION
    1. Creates Gen2 VM (Secure Boot).
    2. Creates 100GB OS Disk (C:) and 40GB Log Disk (D:).
    3. Mounts ISO for boot.
    4. Includes a "Post-OS" function to inject IP/Domain/SCCM via PowerShell Direct.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)] [string]$VMName,
    [Parameter(Mandatory=$true)] [string]$IsoFilename, # e.g. "Server2022.iso"
    [Parameter(Mandatory=$true)] [string]$SwitchName,
    
    # Network Config
    [Parameter(Mandatory=$true)] [string]$StaticIP,
    [Parameter(Mandatory=$true)] [int]$SubnetPrefix,   # e.g. 24 for 255.255.255.0
    [Parameter(Mandatory=$true)] [string]$Gateway,
    [Parameter(Mandatory=$true)] [string]$DNS1,
    
    # Domain & SCCM
    [Parameter(Mandatory=$true)] [string]$DomainName,
    [Parameter(Mandatory=$true)] [PSCredential]$DomainCreds,
    [Parameter(Mandatory=$true)] [string]$SCCM_SiteCode
)

# Global Config
$IsoPath   = "C:\ISO\$IsoFilename"
$VmPath    = "C:\Hyper-V\$VMName"
$VhdPath   = "$VmPath\Virtual Hard Disks"

# 1. HARDWARE PROVISIONING
Write-Host ">>> [STEP 1] Provisioning Hardware for $VMName..." -ForegroundColor Cyan

# Check/Create Directories
if (!(Test-Path $VhdPath)) { New-Item -Path $VhdPath -ItemType Directory -Force | Out-Null }

# Create VM (Gen 2 for Modern Standards)
New-VM -Name $VMName -MemoryStartupBytes 4GB -Generation 2 -Path $VmPath -SwitchName $SwitchName | Out-Null
Set-VMProcessor -VMName $VMName -Count 2 | Out-Null
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false # Performance > Savings

# 2. STORAGE ARCHITECTURE (C: & D:)
Write-Host ">>> [STEP 2] Architecting Storage..." -ForegroundColor Cyan

# C: Drive (OS) - 100GB Dynamic
$OSDisk = "$VhdPath\$VMName-OS.vhdx"
New-VHD -Path $OSDisk -SizeBytes 100GB -Dynamic | Out-Null
Add-VMHardDiskDrive -VMName $VMName -Path $OSDisk | Out-Null

# D: Drive (Logs) - 40GB Dynamic
$LogDisk = "$VhdPath\$VMName-Logs.vhdx"
New-VHD -Path $LogDisk -SizeBytes 40GB -Dynamic | Out-Null
Add-VMHardDiskDrive -VMName $VMName -Path $LogDisk | Out-Null

# 3. ISO MOUNT
Write-Host ">>> [STEP 3] Mounting ISO Media..." -ForegroundColor Cyan
if (Test-Path $IsoPath) {
    Add-VMDvdDrive -VMName $VMName -Path $IsoPath
    # Set Boot Order to DVD first for install
    $DVD = Get-VMDvdDrive -VMName $VMName
    Set-VMFirmware -VMName $VMName -FirstBootDevice $DVD
}
else {
    Write-Error "ISO File not found at $IsoPath"
    Return
}

Write-Host ">>> VM Shell Created. Please complete OS Installation via Console." -ForegroundColor Yellow
Write-Host ">>> Once OS is at Login Screen, run the Post-Configuration block." -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# PHASE 2: THE "SENIOR" POST-CONFIGURATION (RUN THIS AFTER OS INSTALL)
# ---------------------------------------------------------------------------

Function Invoke-VmConfig {
    Write-Host ">>> [PHASE 2] Injecting Config via PowerShell Direct..." -ForegroundColor Magenta
    
    # CREDENTIAL HANDLING FOR INSIDE THE VM
    # We pass the $DomainCreds into the script block
    
    Invoke-Command -VMName $VMName -Credential (Get-Credential) -ScriptBlock {
        Param($IP, $Pre, $Gate, $DNS, $Dom, $Cred, $Site, $LogDiskIndex)
        
        # A. CONFIGURE NETWORK (Static IP)
        Write-Output "Configuring Static IP..."
        $NetAdapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select -First 1
        New-NetIPAddress -InterfaceIndex $NetAdapter.ifIndex -IPAddress $IP -PrefixLength $Pre -DefaultGateway $Gate
        Set-DnsClientServerAddress -InterfaceIndex $NetAdapter.ifIndex -ServerAddresses $DNS
        
        # B. INITIALIZE D: DRIVE (LOGS)
        Write-Output "Initializing Log Volume..."
        # Finds the raw disk that isn't the boot disk and inits it
        Get-Disk | Where-Object IsSystem -eq $false | Where-Object PartitionStyle -eq 'RAW' | 
        Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter "D" -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "Logs" -Confirm:$false

        # C. JOIN DOMAIN
        Write-Output "Joining Domain $Dom..."
        Add-Computer -DomainName $Dom -Credential $Cred -Restart -Force
        
        # Note: VM REBOOTS HERE. 
        # SCCM Step needs to happen after reboot and domain login.
    } -ArgumentList $StaticIP, $SubnetPrefix, $Gateway, $DNS1, $DomainName, $DomainCreds, $SCCM_SiteCode
}

# ---------------------------------------------------------------------------
# PHASE 3: SCCM / MECM INJECTION (Run after Domain Join Reboot)
# ---------------------------------------------------------------------------
<#
    Invoke-Command -VMName $VMName -ScriptBlock {
        Param($SiteCode)
        
        # 1. Install SCCM Client (Assuming standard share path)
        $SCCMPath = "\\$env:USERDNSDOMAIN\NETLOGON\ccmsetup.exe" # Or your dedicated path
        Start-Process -FilePath $SCCMPath -ArgumentList "/mp:sccm.server.local /logon SMSSITECODE=$SiteCode" -Wait
        
        # 2. Trigger Machine Policy Retrieval & Eval Cycle (The "Patches Now" Call)
        # This calls the SMS Client Agent WMI Class to force a check-in
        Invoke-WmiMethod -Namespace root\ccm -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000021}"
        Invoke-WmiMethod -Namespace root\ccm -Class SMS_Client -Name TriggerSchedule -ArgumentList "{00000000-0000-0000-0000-000000000113}" # Updates Deployment
        
        Write-Output "SCCM Agent Triggered."
    } -ArgumentList $SCCM_SiteCode
#>
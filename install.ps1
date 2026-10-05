$ErrorActionPreference = "Stop"

$PrivateRepo = "temeboiw/SentinelVF"
$InstallDir = "C:\Program Files\SentinelVF"
$TempDir = Join-Path $env:TEMP "SentinelVFInstaller"

# --------------------------------------------------
# Administrator check
# --------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "Please run PowerShell as Administrator."
    exit 1
}

# --------------------------------------------------
# Get GitHub token
# --------------------------------------------------

Write-Host ""
Write-Host "SentinelVF Installer"
Write-Host ""

$Token = $env:SENTINELVF_GITHUB_TOKEN

if ([string]::IsNullOrWhiteSpace($Token)) {

    $SecureToken = Read-Host "GitHub access token" -AsSecureString

    $Ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureToken
    )

    try {
        $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Ptr)
    }
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Host "No GitHub token supplied."
    exit 1
}

# --------------------------------------------------
# GitHub authentication
# --------------------------------------------------

$ApiHeaders = @{
    Authorization = "Bearer $Token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "SentinelVF-Installer"
}

# --------------------------------------------------
# Prepare temporary directory
# --------------------------------------------------

if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $TempDir `
    -Force | Out-Null

try {

    Write-Host "Checking for the latest SentinelVF release..."

    # Get latest private release
    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$PrivateRepo/releases/latest" `
        -Headers $ApiHeaders

    # Find ZIP internally.
    # Nothing about the asset is printed.
    $Asset = $Release.assets |
        Where-Object {
            $_.name -like "*.zip"
        } |
        Select-Object -First 1

    if (-not $Asset) {
        throw "SentinelVF release package was not found."
    }

    $ZipPath = Join-Path $TempDir "package.zip"

    Write-Host "Downloading SentinelVF..."

    Invoke-WebRequest `
        -Uri $Asset.url `
        -Headers @{
            Authorization = "Bearer $Token"
            Accept = "application/octet-stream"
            "X-GitHub-Api-Version" = "2022-11-28"
            "User-Agent" = "SentinelVF-Installer"
        } `
        -OutFile $ZipPath

    if (-not (Test-Path $ZipPath)) {
        throw "Download failed."
    }

    Write-Host "Installing SentinelVF..."

    # Remove previous installation
    if (Test-Path $InstallDir) {
        Remove-Item `
            $InstallDir `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Path $InstallDir `
        -Force | Out-Null

    # Extract package
    Expand-Archive `
        -Path $ZipPath `
        -DestinationPath $InstallDir `
        -Force

    # --------------------------------------------------
    # Driver installation
    # --------------------------------------------------

    $Inf = Get-ChildItem `
        -Path $InstallDir `
        -Filter "SentinelVFKM.inf" `
        -Recurse `
        -File |
        Select-Object -First 1

    if ($Inf) {

        Write-Host "Installing SentinelVF driver..."

        pnputil.exe `
            /add-driver `
            $Inf.FullName `
            /install *> $null

        $DriverExit = $LASTEXITCODE

        if ($DriverExit -ne 0) {
            Write-Host ""
            Write-Host "Driver installation returned code $DriverExit." -ForegroundColor Yellow
            Write-Host "The SentinelVF files were installed successfully."
        }
    }

    Write-Host ""
    Write-Host "SentinelVF installation complete." -ForegroundColor Green
    Write-Host ""

}
catch {

    Write-Host ""
    Write-Host "SentinelVF installation failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {

    # Remove temporary package
    if (Test-Path $TempDir) {
        Remove-Item `
            $TempDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    # Remove token from memory variable
    $Token = $null
}
